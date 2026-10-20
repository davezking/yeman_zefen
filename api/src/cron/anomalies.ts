// Nightly anomaly pass: looks across one UTC day of sessions and opens a review item per suspicious
// registered user. It only flags. It never bans, hides, or changes a score; a human decides.
//
// One user has at most one OPEN score_anomaly item (review_items_open_ref_uq). Its details_json is
// {"days": {"YYYY-MM-DD": {rules, metrics...}}}: a later day's evidence is merged into the open item,
// and re-running a day overwrites only that day's entry. A day (or, for the weekly rule, a week) that
// already led to an item, open or closed, is not raised again, so a dismissal sticks.
import type { Bindings } from "../env";
import { dayBounds } from "../lib/dayRange";
import { isoWeek } from "../lib/period";

/** Accuracy at or above this over MIN_ROUNDS_ACCURACY rounds is only plausible for a bot when answers are also instant. */
export const BOT_ACCURACY = 0.98;
/** Too few rounds to tell skill from luck below this. */
export const MIN_ROUNDS_ACCURACY = 50;
/** A median under this is faster than a person can hear a 3 s clip, recognise it, and tap. */
export const BOT_MEDIAN_MS = 900;
/** Humans vary: even elite players' response times spread by 25 % or more of their mean; a script sits near 0. */
export const BOT_MAX_CV = 0.1;
/** The spread is noisy on a handful of answers, so a regularity verdict needs this many rounds. */
export const MIN_ROUNDS_REGULARITY = 30;
/** A session takes at least ~10 s, so 20 in any 60 minutes is more than 3x what one hand keeps up. */
export const MAX_SESSIONS_PER_HOUR = 20;
/** Top of the weekly board must beat the 99.9th percentile of everyone else... */
export const WEEKLY_PERCENTILE = 0.999;
/** ...and also lead the runner-up by this factor, so a close race at the top is never flagged. */
export const WEEKLY_LEAD_FACTOR = 3;

/** analytics_daily metric that marks a day's pass as done (value = users flagged), so missed days are retried. */
export const ANOMALY_PASS_METRIC = "anomaly_pass";
/** D1 queries one pass makes at most: users, rounds, board, percentile, and a batch of two (flags + marker; each counts). */
export const ANOMALY_QUERIES = 6;

const HOUR_MS = 3_600_000;
const GENERATION_ALL = 0;

export type Rule = "inhuman_accuracy" | "bot_regularity" | "session_flood" | "weekly_outlier";

export type UserDay = {
  userId: string;
  sessions: number;
  rounds: number;
  maxSessionsPerHour: number;
  hardShare: number;
  /** Null for users with fewer than MIN_ROUNDS_REGULARITY rounds (their rounds are not loaded). */
  accuracy: number | null;
  medianResponseMs: number | null;
  responseCv: number | null;
};

export type Flag = { userId: string; rules: Rule[]; metrics: Record<string, number | string | null> };

/** Coefficient of variation (population form) from the mean and the mean of squares; null for a zero mean. */
export function cvFromMoments(mean: number, meanOfSquares: number): number | null {
  if (mean === 0) return null;
  // Rounding can push a zero variance slightly negative.
  return Math.sqrt(Math.max(0, meanOfSquares - mean * mean)) / mean;
}

/** The per-day rules (the weekly one needs the board and is evaluated separately). */
export function dayRules(u: UserDay): Rule[] {
  const rules: Rule[] = [];
  if (
    u.rounds >= MIN_ROUNDS_ACCURACY &&
    u.accuracy !== null && u.accuracy >= BOT_ACCURACY &&
    u.medianResponseMs !== null && u.medianResponseMs < BOT_MEDIAN_MS
  ) {
    rules.push("inhuman_accuracy");
  }
  if (u.rounds >= MIN_ROUNDS_REGULARITY && u.responseCv !== null && u.responseCv < BOT_MAX_CV) rules.push("bot_regularity");
  if (u.maxSessionsPerHour >= MAX_SESSIONS_PER_HOUR) rules.push("session_flood");
  return rules;
}

/** Whether the board leader is a weekly outlier: above the p99.9 of the others, and >= 3x the runner-up. */
export function weeklyOutlier(top: number, second: number, percentile: number): boolean {
  return top > 0 && top > percentile && top >= WEEKLY_LEAD_FACTOR * second;
}

// ?1 start, ?2 end of the day. Registered (non-anonymous), visible users only.
// perHour counts each session's own and the previous 60 minutes' sessions (a sliding window, so a burst
// across a clock-hour boundary still counts), in one pass over the day.
const USERS_SQL = `
  WITH day AS (
    SELECT s.user_id, s.rounds, s.difficulty,
           COUNT(*) OVER (PARTITION BY s.user_id ORDER BY s.received_at RANGE BETWEEN ${HOUR_MS - 1} PRECEDING AND CURRENT ROW) AS perHour
    FROM game_sessions s JOIN users u ON u.id = s.user_id
    WHERE s.received_at >= ?1 AND s.received_at < ?2
      AND u.is_anonymous = 0 AND u.shadow_banned = 0 AND u.deleted_at IS NULL
  )
  SELECT user_id AS userId, COUNT(*) AS sessions, SUM(rounds) AS rounds,
         SUM(difficulty = 'hard') AS hard, MAX(perHour) AS maxPerHour
  FROM day GROUP BY user_id
  HAVING SUM(rounds) >= ${MIN_ROUNDS_REGULARITY} OR MAX(perHour) >= ${MAX_SESSIONS_PER_HOUR}`;

// Round statistics, one row per user, for the users who can trip a round-based rule (?3). The median is
// the middle row (or the mean of the two middle rows) of each user's sorted response times.
const ROUNDS_SQL = `
  WITH r AS (
    SELECT s.user_id AS u, CAST(json_extract(j.value, '$.responseMs') AS REAL) AS ms, json_extract(j.value, '$.correct') = 1 AS ok
    FROM game_sessions s, json_each(s.events_json, '$.rounds') j
    WHERE s.received_at >= ?1 AND s.received_at < ?2 AND json_valid(s.events_json)
      AND s.user_id IN (SELECT value FROM json_each(?3))
  ), ranked AS (
    SELECT u, ms, ok, ROW_NUMBER() OVER (PARTITION BY u ORDER BY ms) AS rn, COUNT(*) OVER (PARTITION BY u) AS n FROM r
  )
  SELECT u AS userId, COUNT(*) AS n, SUM(ok) AS correct, AVG(ms) AS mean, AVG(ms * ms) AS meanSq,
         AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN ms END) AS median
  FROM ranked GROUP BY u`;

const VISIBLE = "u.shadow_banned = 0 AND u.deleted_at IS NULL";

// The board's top two for the week (?1), and whether they were already flagged for this week on
// another day than ?2 (a re-run of ?2 itself recomputes the rule).
const BOARD_SQL = `
  SELECT e.user_id AS userId, e.points,
         EXISTS (SELECT 1 FROM review_items r, json_each(r.details_json, '$.days') d
                  WHERE r.entity_type = 'user' AND r.entity_ref = e.user_id AND r.reason = 'score_anomaly'
                    AND d.key <> ?2 AND json_extract(d.value, '$.week') = ?1) AS flagged
  FROM leaderboard_entries e JOIN users u ON u.id = e.user_id
  WHERE e.period = ?1 AND e.generation_id = ${GENERATION_ALL} AND ${VISIBLE}
  ORDER BY e.points DESC LIMIT 2`;

// The p99.9 of everyone but the leader (?2), by nearest rank: the k-th lowest of n others, k = ceil(0.999 n).
const PERCENTILE_SQL = `
  WITH others AS (
    SELECT e.points FROM leaderboard_entries e JOIN users u ON u.id = e.user_id
    WHERE e.period = ?1 AND e.generation_id = ${GENERATION_ALL} AND e.user_id <> ?2 AND ${VISIBLE}
  )
  SELECT (SELECT points FROM others ORDER BY points LIMIT 1
          OFFSET MAX(0, CAST((SELECT COUNT(*) FROM others) * ${WEEKLY_PERCENTILE} + 0.999999 AS INTEGER) - 1)) AS p`;

// One statement for any number of flags (CLAUDE.md query budget). ?1 the flags, ?2 the date.
// A user whose item (any status) already covers this date is skipped, so a dismissal is not undone by
// a re-run. Otherwise the day's evidence opens an item, or is merged into the open one; only the
// duplicate case is absorbed (no OR IGNORE, which would also swallow constraint failures).
const FLAG_SQL = `
  INSERT INTO review_items (entity_type, entity_id, entity_ref, reason, details_json, status)
  SELECT 'user', 0, json_extract(f.value, '$.userId'), 'score_anomaly',
         json_object('days', json_object(?2, json(json_extract(f.value, '$.details')))), 'open'
  FROM json_each(?1) f
  WHERE NOT EXISTS (
    SELECT 1 FROM review_items r
    WHERE r.entity_type = 'user' AND r.entity_ref = json_extract(f.value, '$.userId') AND r.reason = 'score_anomaly'
      AND r.status <> 'open' AND json_type(r.details_json, '$.days."' || ?2 || '"') IS NOT NULL)
  ON CONFLICT (entity_type, entity_ref, reason) WHERE status = 'open' AND entity_ref IS NOT NULL
  DO UPDATE SET details_json = json_patch(review_items.details_json, excluded.details_json)`;

const MARK_SQL = `INSERT OR REPLACE INTO analytics_daily (date, metric, dimension, value) VALUES (?1, '${ANOMALY_PASS_METRIC}', '', ?2)`;

/** Find and flag suspicious users for the UTC day `date`, then mark the day done. Returns the users it flagged. */
export async function flagAnomalies(env: Pick<Bindings, "DB">, date: string): Promise<Flag[]> {
  const bounds = dayBounds(date);
  if (!bounds) throw new Error(`not a calendar date: ${date}`);
  const { results: users } = await env.DB.prepare(USERS_SQL)
    .bind(bounds.start, bounds.end)
    .all<{ userId: string; sessions: number; rounds: number; hard: number; maxPerHour: number }>();

  const needRounds = users.filter((u) => u.rounds >= MIN_ROUNDS_REGULARITY).map((u) => u.userId);
  type RoundStats = { userId: string; n: number; correct: number; mean: number; meanSq: number; median: number };
  const stats = new Map<string, RoundStats>();
  if (needRounds.length > 0) {
    const { results } = await env.DB.prepare(ROUNDS_SQL).bind(bounds.start, bounds.end, JSON.stringify(needRounds)).all<RoundStats>();
    for (const r of results) stats.set(r.userId, r);
  }

  const flags = new Map<string, Flag>();
  for (const u of users) {
    const r = stats.get(u.userId);
    const day: UserDay = {
      userId: u.userId,
      sessions: u.sessions,
      rounds: u.rounds,
      maxSessionsPerHour: u.maxPerHour,
      hardShare: u.hard / u.sessions,
      accuracy: r ? r.correct / r.n : null,
      medianResponseMs: r ? r.median : null,
      responseCv: r ? cvFromMoments(r.mean, r.meanSq) : null,
    };
    const rules = dayRules(day);
    if (rules.length > 0) flags.set(u.userId, { userId: u.userId, rules, metrics: metricsOf(day) });
  }

  // Weekly outlier: the leader of the ISO week this day falls in, once per week.
  const week = isoWeek(bounds.start);
  const { results: board } = await env.DB.prepare(BOARD_SQL).bind(week, date).all<{ userId: string; points: number; flagged: number }>();
  const [top, second] = board;
  if (top && second && !top.flagged) {
    const { results } = await env.DB.prepare(PERCENTILE_SQL).bind(week, top.userId).all<{ p: number | null }>();
    const p = results[0]?.p ?? 0;
    if (weeklyOutlier(top.points, second.points, p)) {
      const f = flags.get(top.userId) ?? { userId: top.userId, rules: [], metrics: {} };
      f.rules.push("weekly_outlier");
      Object.assign(f.metrics, { week, weeklyPoints: top.points, runnerUpPoints: second.points, weeklyP999: p });
      flags.set(top.userId, f);
    }
  }

  const list = [...flags.values()];
  const payload = list.map((f) => ({ userId: f.userId, details: JSON.stringify({ rules: f.rules, ...f.metrics }) }));
  await env.DB.batch([
    ...(list.length > 0 ? [env.DB.prepare(FLAG_SQL).bind(JSON.stringify(payload), date)] : []),
    env.DB.prepare(MARK_SQL).bind(date, list.length),
  ]);
  return list;
}

function metricsOf(u: UserDay): Flag["metrics"] {
  const r = (x: number | null, d = 3) => (x === null ? null : Number(x.toFixed(d)));
  return {
    sessions: u.sessions,
    rounds: u.rounds,
    maxSessionsPerHour: u.maxSessionsPerHour,
    hardShare: r(u.hardShare),
    accuracy: r(u.accuracy),
    medianResponseMs: r(u.medianResponseMs, 0),
    responseCv: r(u.responseCv),
  };
}
