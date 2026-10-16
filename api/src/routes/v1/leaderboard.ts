// Leaderboards. GET /v1/leaderboard is the top 100 for a period and era, cached for 60 s at the edge.
// GET /v1/leaderboard/me is the caller's own points and rank (registered players only).
//
// Guests may read the board but never appear on it (sessions.ts only writes registered players).
// Shadow-banned and deleted users are hidden from everyone else; a shadow-banned caller still sees
// the rank they would have. Rank = 1 + the number of visible entries with more points, so tied
// players share a rank. Ties in the list break by earliest `updated_at`, then user id.
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { requireUser } from "../../lib/firebaseAuth";
import { periodKey } from "../../lib/period";

export const leaderboard = new Hono<AppEnv>();

const TOP_N = 100;
const CACHE_SECONDS = 60;

const querySchema = z.object({
  period: z.enum(["all", "week"]).default("all"),
  generation: z
    .string()
    .regex(/^\d{1,4}$/, "must be a whole number")
    .default("0")
    .transform(Number),
});

function parseQuery(c: { req: { query(): Record<string, string> } }) {
  const parsed = querySchema.safeParse(c.req.query());
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    throw new ApiError(400, "invalid_request", `${issue?.path.join(".") ?? "query"}: ${issue?.message ?? "invalid"}`);
  }
  return parsed.data;
}

const TOP_SQL = `
  SELECT u.display_name AS display_name, u.country AS country, e.points AS points
    FROM leaderboard_entries e
    JOIN users u ON u.id = e.user_id
   WHERE e.period = ?1 AND e.generation_id = ?2 AND u.shadow_banned = 0 AND u.deleted_at IS NULL
   ORDER BY e.points DESC, e.updated_at ASC, e.user_id ASC
   LIMIT ${TOP_N}`;

// The caller's row is read without the visibility filter, so a shadow-banned caller gets a rank;
// only rows they would be ranked against are filtered.
const OWN_SQL = `
  SELECT e.points AS points,
         1 + (SELECT COUNT(*)
                FROM leaderboard_entries o
                JOIN users ou ON ou.id = o.user_id
               WHERE o.period = e.period AND o.generation_id = e.generation_id AND o.points > e.points
                 AND ou.shadow_banned = 0 AND ou.deleted_at IS NULL) AS rank
    FROM leaderboard_entries e
   WHERE e.period = ?1 AND e.generation_id = ?2 AND e.user_id = ?3`;

/** The Cache API key for one board. Includes the resolved week, so a new week starts a new entry. */
export function leaderboardCacheRequest(period: string, generation: number): Request {
  return new Request(`https://leaderboard.cache.internal/${encodeURIComponent(period)}/${generation}`);
}

leaderboard.get("/", async (c) => {
  const { period: choice, generation } = parseQuery(c);
  const period = periodKey(choice, Date.now());

  const cache = caches.default;
  const key = leaderboardCacheRequest(period, generation);
  const hit = await cache.match(key);
  if (hit) return hit;

  const { results } = await c.env.DB.prepare(TOP_SQL)
    .bind(period, generation)
    .all<{ display_name: string | null; country: string | null; points: number }>();

  let rank = 0;
  let prevPoints = -1;
  const entries = results.map((r, i) => {
    if (r.points !== prevPoints) {
      rank = i + 1;
      prevPoints = r.points;
    }
    return { rank, displayName: r.display_name, country: r.country, points: r.points };
  });

  const res = c.json({ period, generation, entries });
  res.headers.set("Cache-Control", `public, max-age=${CACHE_SECONDS}`);
  await cache.put(key, res.clone());
  return res;
});

leaderboard.get("/me", requireUser({ allowAnonymous: false }), async (c) => {
  const { period: choice, generation } = parseQuery(c);
  const period = periodKey(choice, Date.now());
  const user = c.get("user")!;
  const row = await c.env.DB.prepare(OWN_SQL)
    .bind(period, generation, user.uid)
    .first<{ points: number; rank: number }>();
  c.header("Cache-Control", "private, no-store");
  return c.json({ period, generation, me: row ? { points: row.points, rank: row.rank } : null });
});
