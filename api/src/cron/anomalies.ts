// Nightly anomaly pass: looks across one UTC day of sessions and opens a review item per suspicious
// registered user. It only flags. It never bans, hides, or changes a score; a human decides.
// Re-running a day cannot duplicate a flag: review_items_open_ref_uq allows one open item per user.
import type { Bindings } from "../env";
import { dayBounds } from "./rollups";
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
/** A session takes at least ~10 s, so 20 in one clock hour is more than 3x what one hand can do. */
export const MAX_SESSIONS_PER_HOUR = 20;
/** Top of the weekly board must beat the 99.9th percentile of everyone else... */
export const WEEKLY_PERCENTILE = 0.999;
/** ...and also lead the runner-up by this factor, so a close race at the top is never flagged. */
export const WEEKLY_LEAD_FACTOR = 3;

const HOUR_MS = 3_600_000;
const GENERATION_ALL = 0;

export type Rule = "inhuman_accuracy" | "bot_regularity" | "session_flood" | "weekly_outlier";

export type UserDay = {
  userId: string;
  sessions: number;
  rounds: number;
  maxSessionsPerHour: number;
  hardShare: number;
  /** Null until the user has at least MIN_ROUNDS_REGULARITY rounds in the day. */
  accuracy: number | null;
  medianResponseMs: number | null;
  responseCv: number | null;
};

export type Flag = { userId: string; rules: Rule[]; metrics: Record<string, number | string | null> };

export function median(xs: readonly number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/** Standard deviation over mean (population form); 0 for a constant series, null for an empty or zero-mean one. */
export function coefficientOfVariation(xs: readonly number[]): number | null {
  if (xs.length === 0) return null;
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
  if (mean === 0) return null;
  const variance = xs.reduce((a, b) => a + (b - mean) ** 2, 0) / xs.length;
  return Math.sqrt(variance) / mean;
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
  return top > percentile && top >= WEEKLY_LEAD_FACTOR * second && top > 0;
}

// ?1 start, ?2 end of the day. Registered (non-anonymous), visible users only.
const USERS_SQL = `
  WITH day AS (
    SELECT s.user_id, s.id, s.rounds, s.difficulty, s.received_at
    FROM game_sessions s JOIN users u ON u.id = s.user_id
    WHERE s.received_at >= ?1 AND s.received_at < ?2
      AND u.is_anonymous = 0 AND u.shadow_banned = 0 AND u.deleted_at IS NULL
  ), hourly AS (
    SELECT user_id, COUNT(*) AS n FROM day GROUP BY user_id, received_at / ${HOUR_MS}
  )
  SELECT d.user_id AS userId, COUNT(*) AS sessions, SUM(d.rounds) AS rounds,
         SUM(d.difficulty = 'hard') AS hard,
         (SELECT MAX(n) FROM hourly h WHERE h.user_id = d.user_id) AS maxPerHour
  FROM day d GROUP BY d.user_id
  HAVING SUM(d.rounds) >= ${MIN_ROUNDS_REGULARITY} OR maxPerHour >= ${MAX_SESSIONS_PER_HOUR}`;

// Round-level data only for users who can trip a round-based rule (>= MIN_ROUNDS_REGULARITY rounds).
const ROUNDS_SQL = `
  SELECT s.user_id AS userId, json_extract(j.value, '$.responseMs') AS ms, json_extract(j.value, '$.correct') AS correct
  FROM game_sessions s, json_each(s.events_json, '$.rounds') j
  WHERE s.received_at >= ?1 AND s.received_at < ?2 AND json_valid(s.events_json)
    AND s.user_id IN (SELECT value FROM json_each(?3))`;

const BOARD_SQL = `
  SELECT e.user_id AS userId, e.points FROM leaderboard_entries e JOIN users u ON u.id = e.user_id
  WHERE e.period = ?1 AND e.generation_id = ${GENERATION_ALL} AND u.shadow_banned = 0 AND u.deleted_at IS NULL
  ORDER BY e.points DESC LIMIT 2`;

// The p99.9 of everyone but the leader, by nearest rank: the k-th lowest of n others, k = ceil(0.999 n).
const PERCENTILE_SQL = `
  WITH others AS (
    SELECT e.points FROM leaderboard_entries e JOIN users u ON u.id = e.user_id
    WHERE e.period = ?1 AND e.generation_id = ${GENERATION_ALL} AND e.user_id <> ?2
      AND u.shadow_banned = 0 AND u.deleted_at IS NULL
  )
  SELECT (SELECT points FROM others ORDER BY points LIMIT 1
          OFFSET MAX(0, CAST((SELECT COUNT(*) FROM others) * ${WEEKLY_PERCENTILE} + 0.999999 AS INTEGER) - 1)) AS p`;

// One statement for any number of flags (CLAUDE.md query budget). OR IGNORE skips users who already have an open item.
const FLAG_SQL = `
  INSERT OR IGNORE INTO review_items (entity_type, entity_id, entity_ref, reason, details_json, status)
  SELECT 'user', 0, json_extract(value, '$.userId'), 'score_anomaly', json_extract(value, '$.details'), 'open'
  FROM json_each(?1)`;

/** D1 queries one call makes at most (users, rounds, board, percentile, insert). */
export const ANOMALY_QUERIES = 5;

/** Find and flag suspicious users for the UTC day `date`. Returns the flags it computed (some may already have been open). */
export async function flagAnomalies(env: Pick<Bindings, "DB">, date: string): Promise<Flag[]> {
  const bounds = dayBounds(date);
  if (!bounds) throw new Error(`not a calendar date: ${date}`);
  const { results: users } = await env.DB.prepare(USERS_SQL)
    .bind(bounds.start, bounds.end)
    .all<{ userId: string; sessions: number; rounds: number; hard: number; maxPerHour: number }>();

  const needRounds = users.filter((u) => u.rounds >= MIN_ROUNDS_REGULARITY).map((u) => u.userId);
  const byUser = new Map<string, { ms: number[]; correct: number }>();
  if (needRounds.length > 0) {
    const { results } = await env.DB.prepare(ROUNDS_SQL)
      .bind(bounds.start, bounds.end, JSON.stringify(needRounds))
      .all<{ userId: string; ms: number; correct: number }>();
    for (const r of results) {
      const e = byUser.get(r.userId) ?? { ms: [], correct: 0 };
      e.ms.push(r.ms);
      e.correct += r.correct ? 1 : 0;
      byUser.set(r.userId, e);
    }
  }

  const flags = new Map<string, Flag>();
  for (const u of users) {
    const r = byUser.get(u.userId);
    const n = r?.ms.length ?? 0;
    const day: UserDay = {
      userId: u.userId,
      sessions: u.sessions,
      rounds: u.rounds,
      maxSessionsPerHour: u.maxPerHour,
      hardShare: u.hard / u.sessions,
      accuracy: r && n > 0 ? r.correct / n : null,
      medianResponseMs: r && n > 0 ? median(r.ms) : null,
      responseCv: r ? coefficientOfVariation(r.ms) : null,
    };
    const rules = dayRules(day);
    if (rules.length > 0) flags.set(u.userId, { userId: u.userId, rules, metrics: metricsOf(day) });
  }

  // Weekly outlier: the leader of the ISO week this day falls in.
  const week = isoWeek(bounds.start);
  const { results: board } = await env.DB.prepare(BOARD_SQL).bind(week).all<{ userId: string; points: number }>();
  if (board.length === 2) {
    const [top, second] = board as [{ userId: string; points: number }, { userId: string; points: number }];
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
  if (list.length > 0) {
    const payload = list.map((f) => ({ userId: f.userId, details: JSON.stringify({ date, rules: f.rules, ...f.metrics }) }));
    await env.DB.prepare(FLAG_SQL).bind(JSON.stringify(payload)).run();
  }
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
