// Moderation (admin role only): the queue of flags, a player's drill-down, and the three actions
// (shadow-ban, void a session, dismiss a flag). Every action needs a note and is written to
// moderation_log with the admin's email, in the same batch (one transaction) as its effect.
//
// D1 cost is constant per request: the queue is 2 queries, the drill-down 5, an action 2 to 6.
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { requireRole } from "../../lib/accessAuth";
import { ApiError } from "../../lib/errors";
import { ALL_TIME, isoWeek } from "../../lib/period";
import { idParam, parse, parseStoredJson, readJson } from "../../lib/validate";

export const moderationRoutes = new Hono<AppEnv>();

export const QUEUE_LIMIT = 100;
export const RECENT_SESSIONS = 25;
export const LOG_LIMIT = 50;
export const VOIDED = "voided";

const adminOnly = requireRole("admin");

const note = z.string().trim().min(1, "a note is required").max(500);
const noteBody = z.strictObject({ note });
const banBody = z
  .strictObject({
    banned: z.boolean(),
    note,
    /** The anomaly flag this ban answers; it is resolved in the same step. */
    reviewItemId: z.number().int().positive().optional(),
  })
  .refine((b) => b.banned || b.reviewItemId === undefined, { message: "only a ban can resolve a flag", path: ["reviewItemId"] });
const textId = z.string().min(1).max(128);

/** The rounds of a stored session, trimmed to what a moderator reads (not the options shown). */
function roundsOf(eventsJson: string) {
  const events = parseStoredJson(eventsJson) as { rounds?: unknown } | null;
  const rounds = Array.isArray(events?.rounds) ? (events.rounds as Record<string, unknown>[]) : [];
  return rounds.map((r) => ({
    trackId: r.trackId ?? null,
    question: r.question ?? null,
    correct: r.correct === true,
    valid: r.valid !== false,
    responseMs: typeof r.responseMs === "number" ? r.responseMs : null,
    hintUsed: r.hintUsed === true,
    points: typeof r.points === "number" ? r.points : 0,
  }));
}

// ---- The queue ----

// Open anomaly flags. Served by review_items_status_reason_idx.
const ANOMALY_QUEUE_SQL = `
  SELECT r.id, r.entity_ref AS userId, r.details_json AS detailsJson, u.display_name AS displayName,
         COALESCE(u.shadow_banned, 0) AS shadowBanned
    FROM review_items r LEFT JOIN users u ON u.id = r.entity_ref
   WHERE r.reason = 'score_anomaly' AND r.status = 'open' AND r.entity_type = 'user'
   ORDER BY r.id
   LIMIT ${QUEUE_LIMIT + 1}`;

// Flagged sessions nobody has voided or dismissed yet, newest first (game_sessions_flagged_idx).
const SESSION_QUEUE_SQL = `
  SELECT s.id, s.user_id AS userId, u.display_name AS displayName, u.shadow_banned AS shadowBanned, s.mode, s.difficulty,
         s.generation_id AS generationId, s.received_at AS receivedAt, s.rounds, s.score, s.flag_reason AS flagReason
    FROM game_sessions s JOIN users u ON u.id = s.user_id
   WHERE s.flagged = 1
     AND NOT EXISTS (SELECT 1 FROM moderation_log m WHERE m.session_id = s.id AND m.action IN ('void_session', 'dismiss_session'))
   ORDER BY s.received_at DESC
   LIMIT ${QUEUE_LIMIT + 1}`;

type AnomalyRow = { id: number; userId: string; detailsJson: string | null; displayName: string | null; shadowBanned: number };
type SessionRow = {
  id: string; userId: string; displayName: string | null; shadowBanned: number; mode: string; difficulty: string | null;
  generationId: number | null; receivedAt: number; rounds: number; score: number; flagReason: string | null;
};

// At most QUEUE_LIMIT of each come back (`more` says there are others); closing items brings the rest up.
moderationRoutes.get("/moderation/queue", adminOnly, async (c) => {
  const [anomalies, sessions] = await c.env.DB.batch([c.env.DB.prepare(ANOMALY_QUEUE_SQL), c.env.DB.prepare(SESSION_QUEUE_SQL)]);
  const a = anomalies!.results as AnomalyRow[];
  const s = sessions!.results as SessionRow[];
  return c.json({
    anomalies: a.slice(0, QUEUE_LIMIT).map(({ detailsJson, shadowBanned, ...row }) => ({
      ...row,
      shadowBanned: shadowBanned === 1,
      details: parseStoredJson(detailsJson),
    })),
    anomaliesMore: a.length > QUEUE_LIMIT,
    sessions: s.slice(0, QUEUE_LIMIT).map(({ shadowBanned, ...row }) => ({ ...row, shadowBanned: shadowBanned === 1 })),
    sessionsMore: s.length > QUEUE_LIMIT,
  });
});

// ---- A player ----

const USER_SQL = `
  SELECT id, display_name AS displayName, is_anonymous AS isAnonymous, country, created_at AS createdAt,
         last_seen_at AS lastSeenAt, shadow_banned AS shadowBanned, deleted_at AS deletedAt
    FROM users WHERE id = ?1`;

const USER_SESSIONS_SQL = `
  SELECT id, mode, difficulty, generation_id AS generationId, received_at AS receivedAt, rounds, score, offline, flagged,
         flag_reason AS flagReason, events_json AS eventsJson
    FROM game_sessions WHERE user_id = ?1 ORDER BY received_at DESC LIMIT ${RECENT_SESSIONS}`;

const USER_FLAGS_SQL = `
  SELECT id, status, details_json AS detailsJson, resolved_by AS resolvedBy, resolved_at AS resolvedAt
    FROM review_items WHERE entity_type = 'user' AND entity_ref = ?1 AND reason = 'score_anomaly' ORDER BY id DESC LIMIT 20`;

const USER_LOG_SQL = `
  SELECT id, at, admin_email AS adminEmail, action, session_id AS sessionId, review_item_id AS reviewItemId, note
    FROM moderation_log WHERE user_id = ?1 ORDER BY at DESC, id DESC LIMIT ${LOG_LIMIT}`;

// All-generations points for all time and this week: primary-key lookups (the key starts with the period).
const USER_POINTS_SQL = `
  SELECT period, points FROM leaderboard_entries WHERE period IN (?2, ?3) AND generation_id = 0 AND user_id = ?1`;

moderationRoutes.get("/moderation/users/:id", adminOnly, async (c) => {
  const userId = parse(textId, c.req.param("id"), "id");
  const week = isoWeek(Date.now());
  const DB = c.env.DB;
  const [user, sessions, flags, log, points] = await DB.batch([
    DB.prepare(USER_SQL).bind(userId),
    DB.prepare(USER_SESSIONS_SQL).bind(userId),
    DB.prepare(USER_FLAGS_SQL).bind(userId),
    DB.prepare(USER_LOG_SQL).bind(userId),
    DB.prepare(USER_POINTS_SQL).bind(userId, ALL_TIME, week),
  ]);
  const row = (user!.results as (Record<string, unknown> & { isAnonymous: number; shadowBanned: number })[])[0];
  if (!row) throw new ApiError(404, "not_found", `User ${userId} not found`);
  const pointsOf = (period: string) => (points!.results as { period: string; points: number }[]).find((p) => p.period === period)?.points ?? 0;

  return c.json({
    user: { ...row, isAnonymous: row.isAnonymous === 1, shadowBanned: row.shadowBanned === 1 },
    points: { all: pointsOf(ALL_TIME), week: pointsOf(week), weekPeriod: week },
    sessions: (sessions!.results as (Record<string, unknown> & { eventsJson: string; offline: number; flagged: number })[]).map(
      ({ eventsJson, offline, flagged, ...s }) => ({ ...s, offline: offline === 1, flagged: flagged === 1, roundDetails: roundsOf(eventsJson) }),
    ),
    flags: (flags!.results as (Record<string, unknown> & { detailsJson: string | null })[]).map(({ detailsJson, ...f }) => ({
      ...f,
      details: parseStoredJson(detailsJson),
    })),
    log: log!.results,
  });
});

// ---- Actions ----

// The log row for an action that runs only when the statement before it changed a row, so a repeated
// request logs nothing. `changes()` is that previous statement's row count (a D1 batch is one connection).
const LOG_IF_CHANGED_SQL = `
  INSERT INTO moderation_log (at, admin_email, action, user_id, review_item_id, note)
  SELECT ?1, ?2, ?3, ?4, ?5, ?6 WHERE changes() > 0`;

const BAN_SQL = "UPDATE users SET shadow_banned = ?2 WHERE id = ?1 AND shadow_banned <> ?2 RETURNING id";

const FLAG_SQL = "SELECT entity_type AS entityType, entity_ref AS userId, reason, status FROM review_items WHERE id = ?1";

// Banning answers the flag it came from. Its own log row, so the flag's closing is recorded even when the
// player was already banned (the ban then changes and logs nothing).
const RESOLVE_FLAG_SQL = `
  UPDATE review_items SET status = 'resolved', resolved_by = ?3, resolved_at = ?4
   WHERE id = ?1 AND entity_type = 'user' AND entity_ref = ?2 AND reason = 'score_anomaly' AND status = 'open'
   RETURNING id`;

// Banning hides the player from everyone else's boards at once (those reads filter on shadow_banned; the
// cached top 100 follows within its 60 s). Their points are kept, so lifting the ban restores them.
// A `reviewItemId` must be this player's open anomaly flag; otherwise nothing is done (404 or 409).
moderationRoutes.post("/users/:id/shadow-ban", adminOnly, async (c) => {
  const userId = parse(textId, c.req.param("id"), "id");
  const body = parse(banBody, await readJson(c));
  const admin = c.get("admin")!.email;
  const DB = c.env.DB;
  const exists = await DB.prepare("SELECT id FROM users WHERE id = ?1").bind(userId).first();
  if (!exists) throw new ApiError(404, "not_found", `User ${userId} not found`);
  if (body.reviewItemId !== undefined) {
    const flag = await DB.prepare(FLAG_SQL).bind(body.reviewItemId).first<{ entityType: string; userId: string | null; reason: string; status: string }>();
    if (!flag || flag.entityType !== "user" || flag.reason !== "score_anomaly" || flag.userId !== userId) {
      throw new ApiError(404, "not_found", `Flag ${body.reviewItemId} is not an anomaly flag for user ${userId}`);
    }
    if (flag.status !== "open") throw new ApiError(409, "already_closed", `Flag ${body.reviewItemId} is already ${flag.status}`);
  }

  const now = Date.now();
  const statements = [
    DB.prepare(BAN_SQL).bind(userId, body.banned ? 1 : 0),
    DB.prepare(LOG_IF_CHANGED_SQL).bind(now, admin, body.banned ? "shadow_ban" : "shadow_unban", userId, null, body.note),
  ];
  if (body.reviewItemId !== undefined) {
    // Guarded again in SQL, so a flag another admin closed in the meantime is neither resolved nor logged.
    statements.push(
      DB.prepare(RESOLVE_FLAG_SQL).bind(body.reviewItemId, userId, admin, now),
      DB.prepare(LOG_IF_CHANGED_SQL).bind(now, admin, "resolve_flag", userId, body.reviewItemId, body.note),
    );
  }
  const results = await DB.batch(statements);
  return c.json({
    userId,
    shadowBanned: body.banned,
    changed: results[0]!.results.length > 0,
    flagResolved: (results[2]?.results.length ?? 0) > 0,
  });
});

const SESSION_SQL = `
  SELECT user_id AS userId, score, flagged, flag_reason AS flagReason, generation_id AS generationId, received_at AS receivedAt
    FROM game_sessions WHERE id = ?1`;
type StoredSession = { userId: string; score: number; flagged: number; flagReason: string | null; generationId: number | null; receivedAt: number };

// Takes the session's score back off the rows it was added to (all time and its week, all eras and its
// era), but only while the session still counts (flagged = 0): the guard is evaluated before the session
// is marked, in the same batch, so a repeat or a concurrent void finds it already marked and subtracts
// nothing. Clamped at 0. updated_at is left alone, so a tie keeps its order. ?2 periods, ?3 eras.
const SUBTRACT_SQL = `
  UPDATE leaderboard_entries
     SET points = MAX(0, points - (SELECT score FROM game_sessions WHERE id = ?1))
   WHERE user_id = (SELECT user_id FROM game_sessions WHERE id = ?1)
     AND period IN (SELECT value FROM json_each(?2))
     AND generation_id IN (SELECT value FROM json_each(?3))
     AND EXISTS (SELECT 1 FROM game_sessions WHERE id = ?1 AND flagged = 0)`;

const MARK_VOID_SQL = `
  UPDATE game_sessions
     SET flagged = 1, flag_reason = CASE WHEN flag_reason IS NULL THEN '${VOIDED}' ELSE flag_reason || ',${VOIDED}' END
   WHERE id = ?1 AND (flag_reason IS NULL OR ',' || flag_reason || ',' NOT LIKE '%,${VOIDED},%')
   RETURNING id`;

// One void or dismissal per session: the unique index turns a repeat into a no-op. ?1 at, ?2 admin, ?3 action,
// ?4 session, ?5 note, ?6 details. The session must be flagged and not voided (a dismissal), which the
// insert itself checks so a void that lands after the route's own read still wins.
const LOG_DISMISS_SQL = `
  INSERT INTO moderation_log (at, admin_email, action, user_id, session_id, note)
  SELECT ?1, ?2, 'dismiss_session', user_id, id, ?4
    FROM game_sessions
   WHERE id = ?3 AND flagged = 1 AND (flag_reason IS NULL OR ',' || flag_reason || ',' NOT LIKE '%,${VOIDED},%')
  ON CONFLICT (session_id, action) WHERE action IN ('void_session', 'dismiss_session') DO NOTHING
  RETURNING id`;

// The void's log row, written first in the batch so it can record what the subtraction is about to take:
// the most any one row loses, which the floor at 0 can make less than the score. ?1 at, ?2 admin, ?3 session,
// ?4 note, ?5 periods, ?6 eras. A repeat conflicts and returns nothing.
const LOG_VOID_SQL = `
  INSERT INTO moderation_log (at, admin_email, action, user_id, session_id, note, details_json)
  SELECT ?1, ?2, 'void_session', s.user_id, s.id, ?4,
         json_object('score', s.score, 'pointsRemoved', CASE WHEN s.flagged = 0 THEN COALESCE((
           SELECT MAX(MIN(e.points, s.score)) FROM leaderboard_entries e
            WHERE e.user_id = s.user_id
              AND e.period IN (SELECT value FROM json_each(?5))
              AND e.generation_id IN (SELECT value FROM json_each(?6))), 0) ELSE 0 END)
    FROM game_sessions s
   WHERE s.id = ?3
  ON CONFLICT (session_id, action) WHERE action IN ('void_session', 'dismiss_session') DO NOTHING
  RETURNING json_extract(details_json, '$.pointsRemoved') AS pointsRemoved`;

// Idempotent: voiding a voided session answers 200 with `voided: false` and changes nothing. A session
// that was flagged when it was played never reached a board, so there is nothing to take back.
// Limitation: a session played while its player was shadow-banned also never added points, and the schema
// does not record that, so voiding it would still subtract its score (never below 0).
moderationRoutes.post("/sessions/:id/void", adminOnly, async (c) => {
  const sessionId = parse(textId, c.req.param("id"), "id");
  const { note: why } = parse(noteBody, await readJson(c));
  const admin = c.get("admin")!.email;
  const DB = c.env.DB;
  const session = await DB.prepare(SESSION_SQL).bind(sessionId).first<StoredSession>();
  if (!session) throw new ApiError(404, "not_found", `Session ${sessionId} not found`);

  // The same periods and eras the session's points were added to (sessions.ts).
  const periods = JSON.stringify([ALL_TIME, isoWeek(session.receivedAt)]);
  const eras = JSON.stringify(session.generationId ? [0, session.generationId] : [0]);
  const [logged, , marked] = await DB.batch([
    DB.prepare(LOG_VOID_SQL).bind(Date.now(), admin, sessionId, why, periods, eras),
    DB.prepare(SUBTRACT_SQL).bind(sessionId, periods, eras),
    DB.prepare(MARK_VOID_SQL).bind(sessionId),
  ]);
  const voided = marked!.results.length > 0;
  const removed = (logged!.results as { pointsRemoved: number }[])[0]?.pointsRemoved ?? 0;
  return c.json({ sessionId, voided, pointsRemoved: voided ? removed : 0 });
});

// Marks a flagged session as reviewed and left as it is: it stays out of the boards (it was flagged when
// played) and leaves the queue. A voided session cannot be dismissed.
moderationRoutes.post("/sessions/:id/dismiss", adminOnly, async (c) => {
  const sessionId = parse(textId, c.req.param("id"), "id");
  const { note: why } = parse(noteBody, await readJson(c));
  const admin = c.get("admin")!.email;
  const DB = c.env.DB;
  const session = await DB.prepare(SESSION_SQL).bind(sessionId).first<StoredSession>();
  if (!session) throw new ApiError(404, "not_found", `Session ${sessionId} not found`);
  if (session.flagged !== 1) throw new ApiError(409, "not_flagged", "This session is not flagged");

  const logged = await DB.prepare(LOG_DISMISS_SQL).bind(Date.now(), admin, sessionId, why).all();
  if (logged.results.length > 0) return c.json({ sessionId, dismissed: true });
  // Nothing written: dismissed before (a no-op), or voided, possibly just now by another admin.
  const voided = await DB.prepare(
    `SELECT 1 FROM moderation_log WHERE session_id = ?1 AND action = 'void_session'`,
  ).bind(sessionId).first();
  if (voided) throw new ApiError(409, "already_voided", "This session was voided");
  return c.json({ sessionId, dismissed: false });
});

const DISMISS_FLAG_SQL = `
  UPDATE review_items SET status = 'dismissed', resolved_by = ?2, resolved_at = ?3
   WHERE id = ?1 AND entity_type = 'user' AND reason = 'score_anomaly' AND status = 'open'
   RETURNING entity_ref AS userId`;

const LOG_FLAG_SQL = `
  INSERT INTO moderation_log (at, admin_email, action, user_id, review_item_id, note)
  SELECT ?1, ?2, 'dismiss_flag', entity_ref, id, ?4 FROM review_items WHERE id = ?3 AND changes() > 0`;

moderationRoutes.post("/moderation/flags/:id/dismiss", adminOnly, async (c) => {
  const id = idParam(c);
  const { note: why } = parse(noteBody, await readJson(c));
  const admin = c.get("admin")!.email;
  const DB = c.env.DB;
  const now = Date.now();
  const [closed] = await DB.batch([
    DB.prepare(DISMISS_FLAG_SQL).bind(id, admin, now),
    DB.prepare(LOG_FLAG_SQL).bind(now, admin, id, why),
  ]);
  if (closed!.results.length === 0) {
    const existing = await DB.prepare("SELECT status, reason FROM review_items WHERE id = ?1").bind(id).first<{ status: string; reason: string }>();
    if (!existing || existing.reason !== "score_anomaly") throw new ApiError(404, "not_found", `Flag ${id} not found`);
    throw new ApiError(409, "already_closed", `Flag ${id} is already ${existing.status}`);
  }
  return c.json({ id, status: "dismissed" });
});
