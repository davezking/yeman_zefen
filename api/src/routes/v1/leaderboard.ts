// Leaderboards. GET /v1/leaderboard is the top 100 for a period and era, cached for 60 s.
// GET /v1/leaderboard/me is the caller's own points and rank (registered players only).
//
// Guests may read the board but never appear on it (sessions.ts only writes registered players).
// Shadow-banned and deleted users are hidden from everyone else; a shadow-banned caller still sees
// the rank they would have. Rank = 1 + the number of visible entries with more points, so tied
// players share a rank. Ties in the list break by earliest `updated_at`, then user id.
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { requireUser } from "../../lib/firebaseAuth";
import { periodKey } from "../../lib/period";
import { parse } from "../../lib/validate";

export const leaderboard = new Hono<AppEnv>();

const TOP_N = 100;
const CACHE_SECONDS = 60;
/** How long the app may keep a board. Short, because the edge copy may already be up to 60 s old. */
const CLIENT_CACHE_SECONDS = 15;

const querySchema = z.object({
  period: z.enum(["all", "week"]).default("all"),
  generation: z
    .string()
    .regex(/^\d{1,4}$/, "must be a whole number")
    .default("0")
    .transform(Number),
});

export const TOP_SQL = `
  SELECT u.display_name AS display_name, u.country AS country, e.points AS points
    FROM leaderboard_entries e
    JOIN users u ON u.id = e.user_id
   WHERE e.period = ?1 AND e.generation_id = ?2
     AND u.shadow_banned = 0 AND u.deleted_at IS NULL AND u.is_anonymous = 0
   ORDER BY e.points DESC, e.updated_at ASC, e.user_id ASC
   LIMIT ${TOP_N}`;

// Rank = 1 + everyone above (an index-only count on the points index) − the hidden users above
// (read through users_hidden_idx, which holds only shadow-banned and deleted users). This keeps
// a low-ranked caller from joining every entry above them to users. The caller's own row is read
// without the visibility filter, so a shadow-banned caller gets a rank. CROSS JOIN pins the join
// order (SQLite never reorders it), so the hidden users drive and each costs one PK lookup.
export const OWN_SQL = `
  SELECT e.points AS points,
         1 + (SELECT COUNT(*) FROM leaderboard_entries o
               WHERE o.period = e.period AND o.generation_id = e.generation_id AND o.points > e.points)
           - (SELECT COUNT(*) FROM users h
                CROSS JOIN leaderboard_entries o
                  ON o.period = e.period AND o.generation_id = e.generation_id AND o.user_id = h.id
               WHERE (h.shadow_banned = 1 OR h.deleted_at IS NOT NULL) AND o.points > e.points) AS rank
    FROM leaderboard_entries e
   WHERE e.period = ?1 AND e.generation_id = ?2 AND e.user_id = ?3`;

/**
 * The Cache API key for one board. It is on this Worker's own origin, so dev and prod never share
 * entries, and it holds the resolved week, so a new week starts a new entry.
 */
export function leaderboardCacheRequest(origin: string, period: string, generation: number): Request {
  return new Request(`${origin}/__cache/leaderboard/${encodeURIComponent(period)}/${generation}`);
}

function withClientCache(res: Response): Response {
  const out = new Response(res.body, res);
  out.headers.set("Cache-Control", `public, max-age=${CLIENT_CACHE_SECONDS}`);
  return out;
}

leaderboard.get("/", async (c) => {
  const { period: choice, generation } = parse(querySchema, c.req.query(), "query");
  const period = periodKey(choice, Date.now());

  // The Cache API works only on a custom domain (docs/ops.md); on workers.dev match() always misses.
  const cache = caches.default;
  const key = leaderboardCacheRequest(new URL(c.req.url).origin, period, generation);
  const hit = await cache.match(key);
  if (hit) return withClientCache(hit);

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
  const stored = res.clone();
  stored.headers.set("Cache-Control", `public, max-age=${CACHE_SECONDS}`);
  // A failed cache write must not fail a good read.
  c.executionCtx.waitUntil(
    cache.put(key, stored).catch((err: unknown) => {
      console.error(JSON.stringify({ requestId: c.get("requestId"), event: "leaderboard_cache_put_failed", reason: String(err) }));
    }),
  );
  return withClientCache(res);
});

leaderboard.get("/me", requireUser({ allowAnonymous: false }), async (c) => {
  const { period: choice, generation } = parse(querySchema, c.req.query(), "query");
  const period = periodKey(choice, Date.now());
  const user = c.get("user")!;
  const row = await c.env.DB.prepare(OWN_SQL)
    .bind(period, generation, user.uid)
    .first<{ points: number; rank: number }>();
  c.header("Cache-Control", "private, no-store");
  return c.json({ period, generation, me: row ? { points: row.points, rank: row.rank } : null });
});
