// Nightly roll-ups: game_sessions -> royalty_daily, ad_events_daily, analytics_daily.
// Dates are UTC `YYYY-MM-DD`; a session belongs to the day its received_at (server clock) falls in.
// Each run REPLACES the day's rows in one batch (delete, then insert), so reruns give identical rows
// and a failure leaves the day either untouched or complete.
import type { Bindings } from "../env";
import { DAY_MS, dayBounds, utcDate } from "../lib/dayRange";
import { ANOMALY_PASS_METRIC, ANOMALY_QUERIES, flagAnomalies } from "./anomalies";

export { dayBounds, utcDate };
/** How far back a run looks for days that were never rolled up. */
export const BACKFILL_DAYS = 7;
/** Country stored for sessions Cloudflare could not place. */
export const UNKNOWN_COUNTRY = "XX";

export type RollupSummary = {
  date: string;
  sessions: number;
  rounds: number;
  /** Rows written to royalty_daily, ad_events_daily and analytics_daily (analytics includes the 3 retention rows for earlier cohorts). */
  royaltyRows: number;
  adRows: number;
  analyticsRows: number;
};

// ?1 date, ?2 start (inclusive), ?3 end (exclusive).
const SESSIONS_IN_DAY = "received_at >= ?2 AND received_at < ?3";

/** Retention counts are keyed by cohort date and written by a LATER day's run, so a day's own re-run must keep them. */
export const RETENTION_METRICS = ["retention_d1", "retention_d7", "retention_d30"] as const;
/** Rows a day's roll-up does not own: retention (later days write it) and the anomaly pass's done-marker. */
const KEPT_METRICS = [...RETENTION_METRICS, ANOMALY_PASS_METRIC];

const DELETE_SQL = [
  "DELETE FROM royalty_daily WHERE date = ?1",
  "DELETE FROM ad_events_daily WHERE date = ?1",
  `DELETE FROM analytics_daily WHERE date = ?1 AND metric NOT IN (${KEPT_METRICS.map((m) => `'${m}'`).join(", ")})`,
];

// Every track in track_ids_json is one play, right or wrong, flagged or not (FR-22). A play of an ID
// that is not in tracks is left out (royalty_daily.track_id is a foreign key, and one bad ID must not
// fail the whole day); POST /v1/sessions only accepts catalog tracks, so this is a safety net.
const ROYALTY_SQL = `
  INSERT INTO royalty_daily (date, track_id, plays)
  SELECT ?1, CAST(j.value AS INTEGER), COUNT(*)
  FROM game_sessions s, json_each(s.track_ids_json) j
  WHERE s.${SESSIONS_IN_DAY} AND CAST(j.value AS INTEGER) IN (SELECT id FROM tracks)
  GROUP BY CAST(j.value AS INTEGER)`;

// events_json is written by POST /v1/sessions, but a malformed row must cost only its own ads, not the day.
const ad = (field: string) => `COALESCE(CASE WHEN json_valid(events_json) THEN json_extract(events_json, '$.ads.${field}') END, 0)`;

const ADS_SQL = `
  INSERT INTO ad_events_daily (date, country, format, event, count)
  SELECT ?1, COALESCE(country, '${UNKNOWN_COUNTRY}'), 'interstitial', 'shown',
         SUM(${ad("interstitialShown")})
  FROM game_sessions WHERE ${SESSIONS_IN_DAY}
  GROUP BY COALESCE(country, '${UNKNOWN_COUNTRY}')
  HAVING SUM(${ad("interstitialShown")}) > 0
  UNION ALL
  SELECT ?1, COALESCE(country, '${UNKNOWN_COUNTRY}'), 'rewarded', 'completed',
         SUM(${ad("rewardedCompleted")})
  FROM game_sessions WHERE ${SESSIONS_IN_DAY}
  GROUP BY COALESCE(country, '${UNKNOWN_COUNTRY}')
  HAVING SUM(${ad("rewardedCompleted")}) > 0`;

// D1 allows only a few terms in a compound SELECT, so the metrics are two statements.
// rounds_per_session is stored x100 and rounded, because the value column is an integer.
// RETURNING hands back sessions and rounds for the summary line without another query.
const TOTALS_SQL = `
  WITH t AS (
    SELECT COUNT(*) AS n, COALESCE(SUM(rounds), 0) AS r, COUNT(DISTINCT user_id) AS u
    FROM game_sessions WHERE ${SESSIONS_IN_DAY}
  )
  INSERT INTO analytics_daily (date, metric, dimension, value)
  SELECT ?1, 'sessions', '', n FROM t
  UNION ALL SELECT ?1, 'rounds', '', r FROM t
  UNION ALL SELECT ?1, 'rounds_per_session', '', CASE WHEN n = 0 THEN 0 ELSE (r * 100 + n / 2) / n END FROM t
  UNION ALL SELECT ?1, 'dau', '', u FROM t
  RETURNING metric, value`;

// new_users, plus one plays_by_country row per country (dimension = country code). The 'deleted'
// placeholder user counts as one player in dau, and is not a new user.
const BREAKDOWN_SQL = `
  INSERT INTO analytics_daily (date, metric, dimension, value)
  SELECT ?1, 'new_users', '', COUNT(*) FROM users WHERE created_at >= ?2 AND created_at < ?3 AND id <> 'deleted'
  UNION ALL
  SELECT ?1, 'plays_by_country', COALESCE(country, '${UNKNOWN_COUNTRY}'), SUM(json_array_length(track_ids_json))
  FROM game_sessions WHERE ${SESSIONS_IN_DAY}
  GROUP BY COALESCE(country, '${UNKNOWN_COUNTRY}')`;

// Retention (FR-23): of the users created on cohort day C (new_users' definition), how many played on
// C+1, C+7 and C+30. Day ?1 is the "played on" day, so it writes the rows of the three cohorts
// behind it: retention_d1 for ?1-1, retention_d7 for ?1-7, retention_d30 for ?1-30. The value is a
// COUNT of users, not a percentage: the share is retained / new_users, and counts add up across a
// week of cohorts. A row exists once its day has been rolled up (no row = not known yet, not zero).
const RETENTION_SQL = `
  WITH h(n, metric) AS (VALUES (1, 'retention_d1'), (7, 'retention_d7'), (30, 'retention_d30'))
  INSERT OR REPLACE INTO analytics_daily (date, metric, dimension, value)
  SELECT date(?1, '-' || n || ' days'), metric, '',
         -- Starts from the day's sessions (indexed by received_at), not from all users.
         (SELECT COUNT(DISTINCT s.user_id) FROM game_sessions s JOIN users u ON u.id = s.user_id
           WHERE s.received_at >= ?2 AND s.received_at < ?3
             AND u.id <> 'deleted'
             AND u.created_at >= ?2 - n * ${DAY_MS} AND u.created_at < ?3 - n * ${DAY_MS})
    FROM h`;

/** The inserts in rollUpDay's batch, after DELETE_SQL; STATEMENTS_PER_DAY is derived from both. */
const INSERT_SQL = [ROYALTY_SQL, ADS_SQL, TOTALS_SQL, BREAKDOWN_SQL, RETENTION_SQL];
const STATEMENTS_PER_DAY = DELETE_SQL.length + INSERT_SQL.length;
/** D1 queries one cron run may make: the Free plan allows 50, and 1 is kept spare. */
export const RUN_QUERY_BUDGET = 49;
/** The run's own statements: missing roll-up days, missing anomaly days, and the rate-limit prune. */
const RUN_READS = 3;
/** A rate-limit bucket idle this long is full again, so its row can go. */
const RATE_LIMIT_IDLE_MS = DAY_MS;
/**
 * Days one run rolls up at most: as many as fit once the reads and one anomaly pass (yesterday's,
 * which every run makes) are paid for. Whatever is left over goes to anomaly passes for missed days.
 */
export const MAX_DAYS_PER_RUN = Math.floor((RUN_QUERY_BUDGET - RUN_READS - ANOMALY_QUERIES) / STATEMENTS_PER_DAY);

/**
 * Roll up one UTC day, replacing whatever the three tables held for it (retention rows, which belong
 * to earlier cohorts, are written alongside). Eight statements in one batch, however many sessions
 * the day had. Throws on a bad date.
 */
export async function rollUpDay(env: Pick<Bindings, "DB">, date: string): Promise<RollupSummary> {
  const bounds = dayBounds(date);
  if (!bounds) throw new Error(`not a calendar date: ${date}`);
  const bind = (sql: string) => env.DB.prepare(sql).bind(date, bounds.start, bounds.end);
  const results = await env.DB.batch([
    ...DELETE_SQL.map((sql) => env.DB.prepare(sql).bind(date)),
    ...INSERT_SQL.map(bind),
  ]);
  const changes = (i: number) => results[i]!.meta.changes ?? 0;
  const total = (name: string) => (results[5]!.results as { metric: string; value: number }[]).find((r) => r.metric === name)!.value;
  return {
    date,
    sessions: total("sessions"),
    rounds: total("rounds"),
    royaltyRows: changes(3),
    adRows: changes(4),
    analyticsRows: changes(5) + changes(6) + changes(7),
  };
}

/**
 * The days in the last BACKFILL_DAYS (yesterday and back) without a `metric` row, oldest first. A day is
 * rolled up once it has its 'sessions' metric (written even for a day with no sessions), and
 * anomaly-checked once it has ANOMALY_PASS_METRIC.
 */
export async function missingDates(env: Pick<Bindings, "DB">, now: number, metric: string = "sessions"): Promise<string[]> {
  const days = Array.from({ length: BACKFILL_DAYS }, (_, i) => utcDate(now - (BACKFILL_DAYS - i) * DAY_MS));
  const { results } = await env.DB.prepare(
    "SELECT DISTINCT date FROM analytics_daily WHERE metric = ?2 AND date IN (SELECT value FROM json_each(?1))",
  )
    .bind(JSON.stringify(days), metric)
    .all<{ date: string }>();
  const done = new Set(results.map((r) => r.date));
  return days.filter((d) => !done.has(d));
}

/**
 * What the cron runs, in two parts that fail separately:
 * 1. Roll-ups: yesterday (recomputed even if present, so late rows are picked up) plus any day in the
 *    last week that was never rolled up, at most MAX_DAYS_PER_RUN (yesterday first, then the oldest missing).
 * 2. Anomaly passes: yesterday (again recomputed) plus any day in the last week whose pass never
 *    finished, as many as the remaining query budget allows.
 * A failing day does not stop the others; the run then throws, so the failure shows in Cloudflare, and
 * the next run picks the day up again. Everything stays inside RUN_QUERY_BUDGET (Free plan: 50 per invocation).
 */
export async function runScheduled(env: Pick<Bindings, "DB">, now: number = Date.now()): Promise<RollupSummary[]> {
  const yesterday = utcDate(now - DAY_MS);
  const missing = (await missingDates(env, now)).filter((d) => d !== yesterday);
  const todo = [yesterday, ...missing].slice(0, MAX_DAYS_PER_RUN);
  const done: RollupSummary[] = [];
  const failed: string[] = [];
  for (const date of todo.sort()) {
    try {
      const s = await rollUpDay(env, date);
      console.log(
        `rollup ${s.date}: sessions=${s.sessions} rounds=${s.rounds} royalty_rows=${s.royaltyRows} ad_rows=${s.adRows} analytics_rows=${s.analyticsRows}`,
      );
      done.push(s);
    } catch (e) {
      failed.push(date);
      console.error(`rollup ${date} failed`, e);
    }
  }

  const passes = Math.floor((RUN_QUERY_BUDGET - RUN_READS - todo.length * STATEMENTS_PER_DAY) / ANOMALY_QUERIES);
  const unchecked = (await missingDates(env, now, ANOMALY_PASS_METRIC)).filter((d) => d !== yesterday);
  for (const date of [yesterday, ...unchecked].slice(0, passes).sort()) {
    try {
      const flags = await flagAnomalies(env, date);
      console.log(`anomalies ${date}: users_flagged=${flags.length}`);
    } catch (e) {
      failed.push(`anomalies ${date}`);
      console.error(`anomaly pass ${date} failed`, e);
    }
  }
  try {
    await env.DB.prepare("DELETE FROM rate_limits WHERE updated_at < ?1").bind(now - RATE_LIMIT_IDLE_MS).all();
  } catch (e) {
    failed.push("rate_limits prune");
    console.error("rate_limits prune failed", e);
  }
  if (failed.length > 0) throw new Error(`nightly run failed for ${failed.join(", ")}`);
  return done;
}
