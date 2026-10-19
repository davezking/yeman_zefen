// POST /v1/reports/clip: the app tells admins that a clip would not play on a phone.
//
// The app skips the round and marks the clip broken on the device, then sends one report. Reports
// for a track gather in one open `missing_audio` review item (details `source: "player"`), whose
// counts say how often and how each clip failed, so a broken file shows up once in the queue
// however many players hit it. A player may send REPORTS_PER_DAY reports per UTC day.
//
// D1 cost is constant: the rate-limit upsert, then one batch of 2 statements (bump the open item,
// or insert it).
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { CLIP_TYPES } from "../../db/schema";
import { ApiError } from "../../lib/errors";
import { parse, readJson } from "../../lib/validate";

export const reports = new Hono<AppEnv>();

export const REPORTS_PER_DAY = 10;
const DAY_MS = 86_400_000;

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

// Runs before the insert in the same batch, so a new item is not counted twice.
const BUMP_SQL = `
  UPDATE review_items SET details_json = json_set(details_json,
    '$.reports', COALESCE(json_extract(details_json, '$.reports'), 0) + 1,
    '$.clips.' || ?2, COALESCE(json_extract(details_json, '$.clips.' || ?2), 0) + 1,
    '$.errors.' || ?3, COALESCE(json_extract(details_json, '$.errors.' || ?3), 0) + 1,
    '$.lastReportedAt', ?4)
  WHERE ${PLAYER_ITEM}`;

// A track that is out of the catalog, or unknown, gets no item: there is nothing left to fix.
const INSERT_SQL = `
  INSERT INTO review_items (entity_type, entity_id, reason, details_json, status)
  SELECT 'track', t.id, 'missing_audio',
         json_object('source', 'player', 'reports', 1,
                     'clips', json_object(?2, 1), 'errors', json_object(?3, 1), 'lastReportedAt', ?4),
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
    throw new ApiError(429, "rate_limited", `At most ${REPORTS_PER_DAY} clip reports a day`);
  }

  const args = [body.trackId, body.clipType, body.error, now] as const;
  await c.env.DB.batch([
    c.env.DB.prepare(BUMP_SQL).bind(...args),
    c.env.DB.prepare(INSERT_SQL).bind(...args),
  ]);
  return c.json({ accepted: true }, 202);
});
