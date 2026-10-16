// Nightly roll-ups: game_sessions -> royalty_daily, ad_events_daily, analytics_daily.
// Dates are UTC `YYYY-MM-DD`; a session belongs to the day its received_at (server clock) falls in.
// Each run REPLACES the day's rows in one batch (delete, then insert), so reruns give identical rows
// and a failure leaves the day either untouched or complete.
import type { Bindings } from "../env";

const DAY_MS = 86_400_000;
/** How far back a run looks for days that were never rolled up. */
export const BACKFILL_DAYS = 7;
/** D1 statements in rollUpDay's batch: 3 deletes + royalty + ads + 2 analytics. */
const STATEMENTS_PER_DAY = 7;
/** Days one run rolls up at most, derived so that a run (plus its 1 read) stays under the Free plan's 50 queries. */
export const MAX_DAYS_PER_RUN = Math.floor((45 - 1) / STATEMENTS_PER_DAY);
/** Country stored for sessions Cloudflare could not place. */
export const UNKNOWN_COUNTRY = "XX";

export type RollupSummary = {
  date: string;
  sessions: number;
  rounds: number;
  /** Rows written to royalty_daily, ad_events_daily and analytics_daily. */
  royaltyRows: number;
  adRows: number;
  analyticsRows: number;
};

/** `YYYY-MM-DD` for the UTC day containing `ms`. */
export function utcDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** [start, end) of a UTC day in epoch ms, or null when `date` is not a real calendar day. */
export function dayBounds(date: string): { start: number; end: number } | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const start = Date.parse(`${date}T00:00:00.000Z`);
  if (Number.isNaN(start) || utcDate(start) !== date) return null;
  return { start, end: start + DAY_MS };
}

// ?1 date, ?2 start (inclusive), ?3 end (exclusive).
const SESSIONS_IN_DAY = "received_at >= ?2 AND received_at < ?3";

const DELETE_SQL = ["royalty_daily", "ad_events_daily", "analytics_daily"].map((t) => `DELETE FROM ${t} WHERE date = ?1`);

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

/**
 * Roll up one UTC day, replacing whatever the three tables held for it. Seven statements in one
 * batch, however many sessions the day had. Throws on a bad date.
 */
export async function rollUpDay(env: Pick<Bindings, "DB">, date: string): Promise<RollupSummary> {
  const bounds = dayBounds(date);
  if (!bounds) throw new Error(`not a calendar date: ${date}`);
  const bind = (sql: string) => env.DB.prepare(sql).bind(date, bounds.start, bounds.end);
  const results = await env.DB.batch([
    ...DELETE_SQL.map((sql) => env.DB.prepare(sql).bind(date)),
    bind(ROYALTY_SQL),
    bind(ADS_SQL),
    bind(TOTALS_SQL),
    bind(BREAKDOWN_SQL),
  ]);
  const changes = (i: number) => results[i]!.meta.changes ?? 0;
  const total = (name: string) => (results[5]!.results as { metric: string; value: number }[]).find((r) => r.metric === name)!.value;
  return {
    date,
    sessions: total("sessions"),
    rounds: total("rounds"),
    royaltyRows: changes(3),
    adRows: changes(4),
    analyticsRows: changes(5) + changes(6),
  };
}

/** The days in the last BACKFILL_DAYS (yesterday and back) that have no roll-up yet, oldest first. */
export async function missingDates(env: Pick<Bindings, "DB">, now: number): Promise<string[]> {
  const days = Array.from({ length: BACKFILL_DAYS }, (_, i) => utcDate(now - (BACKFILL_DAYS - i) * DAY_MS));
  // A day is done once it has its 'sessions' metric: that row is written even for a day with no sessions.
  const { results } = await env.DB.prepare(
    "SELECT DISTINCT date FROM analytics_daily WHERE metric = 'sessions' AND date IN (SELECT value FROM json_each(?1))",
  )
    .bind(JSON.stringify(days))
    .all<{ date: string }>();
  const done = new Set(results.map((r) => r.date));
  return days.filter((d) => !done.has(d));
}

/**
 * What the cron runs: yesterday (recomputed even if present, so late rows are picked up) plus any day
 * in the last week that was never rolled up. A failing day does not stop the others; the run then
 * throws, so the failure shows in Cloudflare, and the next run picks the day up again.
 * At most MAX_DAYS_PER_RUN days per run (yesterday first, then the oldest missing), to stay inside the
 * Free plan's 50 queries per invocation; with a week missing, the admin endpoint or the next night's run covers the rest.
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
  if (failed.length > 0) throw new Error(`rollup failed for ${failed.join(", ")}`);
  return done;
}
