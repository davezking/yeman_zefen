// POST /v1/sessions: the server-authoritative score for one finished session.
// Spec: docs/session-payload.md (the payload), docs/scoring.md (the rules).
//
// The app sends round events, never a score. The server checks every round against the catalog,
// scores it, stores one game_sessions row, and adds the score to the leaderboards when the player
// is registered, not shadow-banned, and the session is not flagged.
//
// D1 cost is constant: 2 reads (one batch) and at most 3 statements (one batch): the user touch,
// one leaderboard upsert (up to 4 rows) and the session row.
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { requestCountry } from "../../lib/country";
import { ApiError } from "../../lib/errors";
import { DELETED_USER_ID, type PlayerUser } from "../../lib/firebaseAuth";
import { ALL_TIME, isoWeek } from "../../lib/period";
import { DIFFICULTIES, GAME_MODES, scoreSession, windowMs, type Difficulty, type GameMode } from "../../lib/scoring";
import { parse, parseJsonText } from "../../lib/validate";

export const sessions = new Hono<AppEnv>();

export const MAX_ROUNDS = 50;
export const OPTION_COUNT = 4;
/** The sum of response times may exceed the session's duration by this much (device clock jitter). */
export const DURATION_TOLERANCE_MS = 10_000;
/** How old `clientStartedAt` may be: sessions queue offline for up to this long. */
export const MAX_SESSION_AGE_MS = 14 * 86_400_000;
/** How far in the future the device clock may be. */
export const MAX_CLOCK_AHEAD_MS = 5 * 60_000;
/** A non-null answer this long after the window closed cannot come from the app, which ends the round as a timeout. */
export const LATE_ANSWER_TOLERANCE_MS = 1000;
/** No real round takes longer; it keeps the arithmetic far from overflow. */
const MAX_RESPONSE_MS = 3_600_000;
/** A 50-round payload is about 6 KB (all ASCII, so characters are bytes). */
const MAX_BODY_CHARS = 32 * 1024;

export const QUESTION_KINDS = ["song", "artist", "era"] as const;
type QuestionKind = (typeof QUESTION_KINDS)[number];

type CatalogKind = "t" | "a" | "g";
/** Which catalog table a question's options are ids of. */
const OPTION_KIND: Record<QuestionKind, CatalogKind> = { song: "t", artist: "a", era: "g" };
const KIND_LABEL: Record<CatalogKind, string> = { t: "track", a: "artist", g: "era" };

/** Why a session is flagged. A flagged session is stored (royalty counts) but never reaches a leaderboard. */
export type FlagReason =
  | "fast_response"
  | "late_answer"
  | "duration_mismatch"
  | "clock_out_of_range"
  | "era_mismatch"
  | "catalog_mismatch";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const catalogId = z.number().int().positive();

// Unknown keys are stripped rather than rejected: a newer app may add a field before the server
// knows it, and the offline queue parks a 4xx for good.
const round = z.object({
  trackId: catalogId,
  question: z.enum(QUESTION_KINDS),
  optionIds: z
    .array(catalogId)
    .length(OPTION_COUNT)
    .refine((ids) => new Set(ids).size === ids.length, "options must be distinct"),
  chosenId: catalogId.nullable(),
  responseMs: z.number().int().min(0).max(MAX_RESPONSE_MS),
  hintUsed: z.boolean(),
});

export const sessionPayloadSchema = z.object({
  id: z.string().regex(UUID, "must be a UUID").transform((s) => s.toLowerCase()),
  mode: z.enum(GAME_MODES),
  generationId: z.number().int().min(0),
  difficulty: z.enum(DIFFICULTIES),
  clientStartedAt: z.number().int().min(0),
  clientEndedAt: z.number().int().min(0),
  offline: z.boolean(),
  rounds: z.array(round).min(1).max(MAX_ROUNDS),
  ads: z.object({
    interstitialShown: z.number().int().min(0).max(1000),
    rewardedCompleted: z.number().int().min(0).max(1000),
  }),
});

type Payload = z.infer<typeof sessionPayloadSchema>;

export type SessionResult = { score: number; rounds: { points: number; correct: boolean }[]; flagged: boolean };

/** What events_json holds: the events as sent, plus each round's result (replays return it). */
type StoredEvents = {
  clientEndedAt: number;
  rounds: (Payload["rounds"][number] & { points: number; correct: boolean; valid: boolean })[];
  ads: Payload["ads"];
};

type CatalogRow = { kind: CatalogKind; id: number; artist_id: number | null; generation_id: number | null };
type StoredRow = { user_id: string; score: number; flagged: number; events_json: string };

const CATALOG_SQL = `
  SELECT 't' AS kind, id, artist_id, generation_id FROM tracks WHERE id IN (SELECT value FROM json_each(?1))
  UNION ALL SELECT 'a', id, NULL, NULL FROM artists WHERE id IN (SELECT value FROM json_each(?2))
  UNION ALL SELECT 'g', id, NULL, NULL FROM generations WHERE id IN (SELECT value FROM json_each(?3))`;

const STORED_SQL = "SELECT user_id, score, flagged, events_json FROM game_sessions WHERE id = ?1";

const USER_TOUCH_SQL = `
  INSERT INTO users (id, display_name, is_anonymous, country, created_at, last_seen_at)
  VALUES (?1, NULL, ?2, ?3, ?4, ?4)
  ON CONFLICT (id) DO UPDATE SET
    is_anonymous = MIN(users.is_anonymous, excluded.is_anonymous),
    last_seen_at = excluded.last_seen_at,
    country = COALESCE(excluded.country, users.country)`;

// Runs before the session insert in the same batch (a D1 batch is one transaction), so the
// NOT EXISTS sees whether this id was already stored: a replay, even a concurrent one, adds
// nothing. The registered and shadow-ban checks read the row as it is at write time (after the
// user touch), so a guest token still cached right after linking counts for the account.
// One statement for every row the session adds to: json_each supplies the periods (?1) and the
// generations (?2), so a guest's session (which adds nothing) costs one statement, not four.
const LEADERBOARD_SQL = `
  INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
  SELECT p.value, g.value, u.id, ?3, ?4
    FROM users u
    CROSS JOIN json_each(?1) p
    CROSS JOIN json_each(?2) g
   WHERE u.id = ?5 AND u.is_anonymous = 0 AND u.shadow_banned = 0
     AND NOT EXISTS (SELECT 1 FROM game_sessions WHERE id = ?6)
  ON CONFLICT (period, generation_id, user_id) DO UPDATE SET
    points = points + excluded.points,
    updated_at = excluded.updated_at`;

const SESSION_SQL = `
  INSERT INTO game_sessions (id, user_id, mode, generation_id, difficulty, client_started_at, received_at,
                             rounds, score, track_ids_json, events_json, offline, country, flagged, flag_reason)
  VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
  ON CONFLICT (id) DO NOTHING
  RETURNING id`;

function invalid(message: string): never {
  throw new ApiError(422, "invalid_session", message);
}

/** The stored result for `id`, or a 409 when another player owns it. */
function storedResult(row: StoredRow, user: PlayerUser): SessionResult {
  // After DELETE /v1/me the row belongs to the placeholder user. A retry from the deleted account
  // must still read as stored (or its queue would keep it forever); the result is not personal.
  if (row.user_id !== user.uid && row.user_id !== DELETED_USER_ID) {
    throw new ApiError(409, "session_conflict", "This session id belongs to another player");
  }
  const events = JSON.parse(row.events_json) as StoredEvents;
  return {
    score: row.score,
    rounds: events.rounds.map((r) => ({ points: r.points, correct: r.correct })),
    flagged: row.flagged === 1,
  };
}

/** The catalog ids the session refers to, by table, for one lookup query. */
function referencedIds(p: Payload): Record<CatalogKind, number[]> {
  const ids: Record<CatalogKind, Set<number>> = { t: new Set(), a: new Set(), g: new Set() };
  if (p.generationId !== 0) ids.g.add(p.generationId);
  for (const r of p.rounds) {
    ids.t.add(r.trackId);
    for (const id of r.optionIds) ids[OPTION_KIND[r.question]].add(id);
  }
  return { t: [...ids.t], a: [...ids.a], g: [...ids.g] };
}

/**
 * Score every round against the catalog. Throws 422 for a payload that cannot have come from a real
 * game. Artist and era rounds that no longer match the catalog are flagged instead: an admin can
 * merge an artist or change a track's era after a pack was downloaded, and an honest session
 * queued offline must not be lost for it (the queue parks a 4xx for good).
 */
function scoreAgainstCatalog(p: Payload, catalog: CatalogRow[], now: number) {
  const tracks = new Map<number, CatalogRow>();
  const known: Record<CatalogKind, Set<number>> = { t: new Set(), a: new Set(), g: new Set() };
  for (const row of catalog) {
    known[row.kind].add(row.id);
    if (row.kind === "t") tracks.set(row.id, row);
  }
  if (p.generationId !== 0 && !known.g.has(p.generationId)) invalid(`generationId: unknown era ${p.generationId}`);

  const flags = new Set<FlagReason>();
  const mode: GameMode = p.mode;
  // Which Era? has no era filter, so its sessions are for all eras and count on the all-eras boards.
  if (mode === "generation" && p.generationId !== 0) invalid("generationId: must be 0 in generation mode");
  const difficulty: Difficulty = p.difficulty;
  const window = windowMs(mode, difficulty);

  const answers = p.rounds.map((r, i) => {
    const at = `rounds.${i}`;
    const track = tracks.get(r.trackId);
    if (!track) invalid(`${at}.trackId: unknown track ${r.trackId}`);
    if ((mode === "generation") !== (r.question === "era")) {
      invalid(`${at}.question: ${r.question} questions are not asked in ${mode} mode`);
    }
    if (r.chosenId !== null && !r.optionIds.includes(r.chosenId)) invalid(`${at}.chosenId: not one of the options`);

    // The id the player has to pick: the track itself, its artist, or its era.
    const answer = r.question === "song" ? track.id : r.question === "artist" ? track.artist_id : track.generation_id;
    const kind = OPTION_KIND[r.question];
    const unknown = r.optionIds.find((id) => !known[kind].has(id));
    const answerShown = answer !== null && r.optionIds.includes(answer);
    let correct = r.chosenId === answer;
    if (r.question === "song") {
      // Tracks are never deleted, so a song round that does not match is forged.
      if (unknown !== undefined) invalid(`${at}.optionIds: unknown ${KIND_LABEL[kind]} ${unknown}`);
      if (!answerShown) invalid(`${at}.optionIds: the correct answer is not among the options`);
    } else if (unknown !== undefined || !answerShown) {
      flags.add("catalog_mismatch");
      correct = false;
    }

    if (p.generationId !== 0 && track.generation_id !== p.generationId) flags.add("era_mismatch");
    if (r.chosenId !== null && r.responseMs > window + LATE_ANSWER_TOLERANCE_MS) flags.add("late_answer");
    return { correct, responseMs: r.responseMs, hintUsed: r.hintUsed };
  });

  const session = scoreSession(mode, difficulty, answers);
  if (session.flagged) flags.add("fast_response");
  const rounds = p.rounds.map((r, i) => {
    const s = session.rounds[i]!;
    return { ...r, points: s.points, correct: s.correct, valid: s.valid };
  });

  const duration = p.clientEndedAt - p.clientStartedAt;
  const responseTotal = rounds.reduce((sum, r) => sum + r.responseMs, 0);
  if (duration < 0 || responseTotal > duration + DURATION_TOLERANCE_MS) flags.add("duration_mismatch");
  if (p.clientStartedAt < now - MAX_SESSION_AGE_MS || p.clientEndedAt > now + MAX_CLOCK_AHEAD_MS) {
    flags.add("clock_out_of_range");
  }

  return { rounds, score: session.total, flags };
}

sessions.post("/", async (c) => {
  const user = c.get("user")!;
  // Refuse a declared oversize body before reading it; the length check after catches chunked ones.
  const tooLarge = () => new ApiError(413, "payload_too_large", "Session payload is too large");
  if (Number(c.req.header("content-length") ?? 0) > MAX_BODY_CHARS) throw tooLarge();
  const text = await c.req.text();
  if (text.length > MAX_BODY_CHARS) throw tooLarge();
  const p = parse(sessionPayloadSchema, parseJsonText(text));
  const DB = c.env.DB;
  const now = Date.now();

  const ids = referencedIds(p);
  const [stored, catalog] = await DB.batch([
    DB.prepare(STORED_SQL).bind(p.id),
    DB.prepare(CATALOG_SQL).bind(
      JSON.stringify(ids.t),
      JSON.stringify(ids.a),
      JSON.stringify(ids.g),
    ),
  ]);
  // Idempotency comes first: a stored session is returned as it was scored, even if the catalog
  // has changed since.
  const existing = (stored!.results as StoredRow[])[0];
  if (existing) return c.json(storedResult(existing, user));

  const { rounds, score, flags } = scoreAgainstCatalog(p, catalog!.results as CatalogRow[], now);
  const flagged = flags.size > 0;
  const country = requestCountry(c.req.raw);
  const events: StoredEvents = { clientEndedAt: p.clientEndedAt, rounds, ads: p.ads };

  const statements = [DB.prepare(USER_TOUCH_SQL).bind(user.uid, user.isAnonymous ? 1 : 0, country, now)];
  if (!flagged && score > 0) {
    // The server's clock decides the week, so a device clock cannot move points between weeks.
    const periods = [ALL_TIME, isoWeek(now)];
    const generations = p.generationId === 0 ? [0] : [0, p.generationId];
    statements.push(
      DB.prepare(LEADERBOARD_SQL).bind(JSON.stringify(periods), JSON.stringify(generations), score, now, user.uid, p.id),
    );
  }
  statements.push(
    DB.prepare(SESSION_SQL).bind(
      p.id,
      user.uid,
      p.mode,
      p.generationId,
      p.difficulty,
      p.clientStartedAt,
      now,
      rounds.length,
      score,
      JSON.stringify(rounds.map((r) => r.trackId)),
      JSON.stringify(events),
      p.offline ? 1 : 0,
      country,
      flagged ? 1 : 0,
      flagged ? [...flags].sort().join(",") : null,
    ),
  );
  const results = await DB.batch(statements);
  if (results.at(-1)!.results.length === 0) {
    // Another request stored this id between our read and our write; answer as a replay.
    const row = await DB.prepare(STORED_SQL).bind(p.id).first<StoredRow>();
    if (!row) throw new Error(`session ${p.id} conflicted but is not stored`);
    return c.json(storedResult(row, user));
  }

  const result: SessionResult = { score, rounds: rounds.map((r) => ({ points: r.points, correct: r.correct })), flagged };
  return c.json(result);
});
