// POST /v1/reports/clip: the app tells admins that a clip would not play on a phone.
// POST /v1/reports/name: a player reports a display name on the leaderboard as offensive.
//
// The app skips the round and marks the clip broken on the device, then sends one report. Reports
// for a track gather in one open `missing_audio` review item (details `source: "player"`), whose
// counts say how often and how each clip failed, so a broken file shows up once in the queue
// however many players hit it. `reporters` holds the distinct players (up to MAX_REPORTERS), so
// one player sending the same report again moves the counts but not the number of players. A
// player may send REPORTS_PER_DAY reports per UTC day.
//
// D1 cost is constant: the rate-limit upsert, then one batch of 2 statements (bump the open item,
// or insert it).
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { CLIP_TYPES } from "../../db/schema";
import { DISPLAY_NAME_MAX } from "../../lib/displayName";
import { ApiError } from "../../lib/errors";
import { parse, readJson } from "../../lib/validate";

export const reports = new Hono<AppEnv>();

export const REPORTS_PER_DAY = 10;
const DAY_MS = 86_400_000;
/** How many distinct reporters an item keeps. Past this the item is plainly widespread. */
export const MAX_REPORTERS = 100;

/** How a clip failed on the phone. */
export const CLIP_REPORT_ERRORS = ["file_missing", "decode_error", "too_short"] as const;

const clipReportSchema = z.strictObject({
  trackId: z.number().int().positive(),
  clipType: z.enum(CLIP_TYPES),
  error: z.enum(CLIP_REPORT_ERRORS),
});

// One row per player. A new day starts the count over; on the same day the count only moves while
// it is under the limit, so no row comes back once the limit is reached.
const COUNT_SQL = `
  INSERT INTO clip_report_counts (user_id, day, count) VALUES (?1, ?2, 1)
  ON CONFLICT (user_id) DO UPDATE SET
    count = CASE WHEN clip_report_counts.day = excluded.day THEN clip_report_counts.count + 1 ELSE 1 END,
    day = excluded.day
  WHERE clip_report_counts.day <> excluded.day OR clip_report_counts.count < ?3
  RETURNING count`;

const PLAYER_ITEM = `
  entity_type = 'track' AND entity_id = ?1 AND reason = 'missing_audio' AND status = 'open'
  AND json_extract(details_json, '$.source') = 'player'`;

// Runs before the insert in the same batch, so a new item is not counted twice. The player joins
// `reporters` unless already there or the list is full.
const BUMP_SQL = `
  UPDATE review_items SET details_json = json_set(
    CASE WHEN EXISTS (SELECT 1 FROM json_each(details_json, '$.reporters') r WHERE r.value = ?5)
           OR COALESCE(json_array_length(details_json, '$.reporters'), 0) >= ${MAX_REPORTERS}
         THEN details_json ELSE json_insert(details_json, '$.reporters[#]', ?5) END,
    '$.reports', COALESCE(json_extract(details_json, '$.reports'), 0) + 1,
    '$.clips.' || ?2, COALESCE(json_extract(details_json, '$.clips.' || ?2), 0) + 1,
    '$.errors.' || ?3, COALESCE(json_extract(details_json, '$.errors.' || ?3), 0) + 1,
    '$.lastReportedAt', ?4)
  WHERE ${PLAYER_ITEM}`;

// A track that is out of the catalog, or unknown, gets no item: there is nothing left to fix.
const INSERT_SQL = `
  INSERT INTO review_items (entity_type, entity_id, reason, details_json, status)
  SELECT 'track', t.id, 'missing_audio',
         json_object('source', 'player', 'reports', 1, 'reporters', json_array(?5),
                     'clips', json_object(?2, 1), 'errors', json_object(?3, 1),
                     'firstReportedAt', ?4, 'lastReportedAt', ?4),
         'open'
  FROM tracks t
  WHERE t.id = ?1 AND t.status NOT IN ('rejected', 'retired')
    AND NOT EXISTS (SELECT 1 FROM review_items WHERE ${PLAYER_ITEM})`;

reports.post("/clip", async (c) => {
  const body = parse(clipReportSchema, await readJson(c));
  const user = c.get("user")!;
  const now = Date.now();

  const counted = await c.env.DB.prepare(COUNT_SQL)
    .bind(user.uid, Math.floor(now / DAY_MS), REPORTS_PER_DAY)
    .first<{ count: number }>();
  if (counted === null) {
    // The count starts over at the next UTC midnight.
    c.header("Retry-After", String(Math.ceil((DAY_MS - (now % DAY_MS)) / 1000)));
    throw new ApiError(429, "rate_limited", `At most ${REPORTS_PER_DAY} clip reports a day`);
  }

  const args = [body.trackId, body.clipType, body.error, now, user.uid] as const;
  await c.env.DB.batch([
    c.env.DB.prepare(BUMP_SQL).bind(...args),
    c.env.DB.prepare(INSERT_SQL).bind(...args),
  ]);
  return c.json({ accepted: true }, 202);
});

// ---- Display names ----
//
// The leaderboard shows names, not user IDs, so a report names the text it saw. Every visible
// player with exactly that name (registered, not hidden, not deleted, not the reporter) gets one
// open `name_report` item (entity_type 'user', entity_ref = the UID); a later report bumps it.
// Admins handle these in the moderation queue: shadow-ban (which resolves the item) or dismiss.
// The answer is the same whether or not a name matched, so it does not reveal who exists.
//
// D1 cost is constant: the rate-limit upsert (routes/v1.ts), then one statement.

const nameReportSchema = z.strictObject({
  displayName: z
    .string()
    .transform((s) => s.normalize("NFC").trim().replace(/ {2,}/g, " "))
    .pipe(z.string().min(1).refine((s) => [...s].length <= DISPLAY_NAME_MAX, `must be at most ${DISPLAY_NAME_MAX} characters`)),
});

/** At most this many players are reported by one request (names are not unique). */
export const NAME_REPORT_MATCHES = 5;

// ?1 name, ?2 reporter uid, ?3 now. `displayName` keeps the name as reported, so an admin can see
// it even after the player renames. The SELECT's WHERE also keeps the upsert's ON from being read
// as a join constraint.
export const NAME_REPORT_SQL = `
  INSERT INTO review_items (entity_type, entity_id, entity_ref, reason, details_json, status)
  SELECT 'user', 0, u.id, 'name_report',
         json_object('displayName', u.display_name, 'reports', 1, 'reporters', json_array(?2),
                     'firstReportedAt', ?3, 'lastReportedAt', ?3),
         'open'
    FROM users u
   WHERE u.display_name = ?1 AND u.id <> ?2
     AND u.is_anonymous = 0 AND u.shadow_banned = 0 AND u.deleted_at IS NULL
   LIMIT ${NAME_REPORT_MATCHES}
  ON CONFLICT (entity_type, entity_ref, reason) WHERE status = 'open' AND entity_ref IS NOT NULL
  DO UPDATE SET details_json = json_set(
    CASE WHEN EXISTS (SELECT 1 FROM json_each(review_items.details_json, '$.reporters') r WHERE r.value = ?2)
           OR COALESCE(json_array_length(review_items.details_json, '$.reporters'), 0) >= ${MAX_REPORTERS}
         THEN review_items.details_json ELSE json_insert(review_items.details_json, '$.reporters[#]', ?2) END,
    '$.reports', COALESCE(json_extract(review_items.details_json, '$.reports'), 0) + 1,
    '$.displayName', json_extract(excluded.details_json, '$.displayName'),
    '$.lastReportedAt', ?3)`;

reports.post("/name", async (c) => {
  const body = parse(nameReportSchema, await readJson(c));
  const user = c.get("user")!;
  await c.env.DB.prepare(NAME_REPORT_SQL).bind(body.displayName, user.uid, Date.now()).all();
  return c.json({ accepted: true }, 202);
});
