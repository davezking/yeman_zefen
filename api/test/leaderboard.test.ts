import { env, exports } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { leaderboardCacheRequest, OWN_SQL, TOP_SQL } from "../src/routes/v1/leaderboard";
import { currentIsoWeek } from "../src/lib/period";
import { installFirebaseJwks, player, removeFirebaseJwks } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);

const WEEK = currentIsoWeek();
const ORIGIN = "https://api.test";
const REG = { provider: "password" };

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM leaderboard_entries"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
  for (const period of ["all", WEEK]) for (const g of [0, 3]) await caches.default.delete(leaderboardCacheRequest(ORIGIN, period, g));
});

type Seed = { id: string; name?: string | null; country?: string | null; points: number; at?: number; banned?: boolean; deleted?: boolean; period?: string; gen?: number };
async function seed(rows: Seed[]) {
  await env.DB.batch(
    rows.flatMap((r) => [
      env.DB.prepare(
        "INSERT OR IGNORE INTO users (id, display_name, country, is_anonymous, created_at, shadow_banned, deleted_at) VALUES (?, ?, ?, 0, 1, ?, ?)",
      ).bind(r.id, r.name === undefined ? r.id : r.name, r.country ?? "ET", r.banned ? 1 : 0, r.deleted ? 5 : null),
      env.DB.prepare(
        "INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at) VALUES (?, ?, ?, ?, ?)",
      ).bind(r.period ?? "all", r.gen ?? 0, r.id, r.points, r.at ?? 1000),
    ]),
  );
}

/** The cache write runs in waitUntil, after the response; wait for it to land. */
async function waitForCache(period: string, generation: number) {
  for (let i = 0; i < 50; i++) {
    if (await caches.default.match(leaderboardCacheRequest(ORIGIN, period, generation))) return;
    await new Promise((r) => setTimeout(r, 10));
  }
  throw new Error("leaderboard was never cached");
}

type Board = { period: string; generation: number; entries: { rank: number; displayName: string | null; country: string | null; points: number }[] };

describe("GET /v1/leaderboard", () => {
  it("lists the top entries by points, earliest update first on ties, with shared ranks", async () => {
    await seed([
      { id: "a", points: 500, at: 30 },
      { id: "b", points: 900, at: 20 },
      { id: "c", points: 500, at: 10 },
      { id: "d", points: 100, at: 5 },
    ]);
    const res = await player("guest-1", "/v1/leaderboard");
    expect(res.status).toBe(200);
    const body = (await res.json()) as Board;
    expect(body.period).toBe("all");
    expect(body.generation).toBe(0);
    expect(body.entries.map((e) => [e.displayName, e.rank, e.points])).toEqual([
      ["b", 1, 900], ["c", 2, 500], ["a", 2, 500], ["d", 4, 100],
    ]);
    expect(body.entries[0]).toEqual({ rank: 1, displayName: "b", country: "ET", points: 900 });
  });

  it("returns at most 100 entries", async () => {
    await seed(Array.from({ length: 120 }, (_, i) => ({ id: `u${i}`, points: i })));
    const body = (await (await player("guest-1", "/v1/leaderboard")).json()) as Board;
    expect(body.entries).toHaveLength(100);
    expect(body.entries[0]!.points).toBe(119);
    expect(body.entries[99]!.points).toBe(20);
  });

  it("hides shadow-banned and deleted users", async () => {
    await seed([
      { id: "ok", points: 10 },
      { id: "banned", points: 999, banned: true },
      { id: "gone", points: 998, deleted: true },
    ]);
    const body = (await (await player("guest-1", "/v1/leaderboard")).json()) as Board;
    expect(body.entries.map((e) => e.displayName)).toEqual(["ok"]);
  });

  it("never lists a guest, even if an entry exists for one", async () => {
    await seed([{ id: "ok", points: 10 }, { id: "guest", points: 50 }]);
    await env.DB.prepare("UPDATE users SET is_anonymous = 1 WHERE id = 'guest'").run();
    const body = (await (await player("g", "/v1/leaderboard")).json()) as Board;
    expect(body.entries.map((e) => e.displayName)).toEqual(["ok"]);
  });

  it("separates periods and generations", async () => {
    await seed([
      { id: "all0", points: 1 },
      { id: "wk0", points: 2, period: WEEK },
      { id: "all3", points: 3, gen: 3 },
    ]);
    const names = async (q: string) => ((await (await player("g", `/v1/leaderboard${q}`)).json()) as Board).entries.map((e) => e.displayName);
    expect(await names("")).toEqual(["all0"]);
    expect(await names("?period=week")).toEqual(["wk0"]);
    expect(await names("?generation=3")).toEqual(["all3"]);
    const week = (await (await player("g", "/v1/leaderboard?period=week")).json()) as Board;
    expect(week.period).toBe(WEEK);
  });

  it("serves from the 60 s cache until it is cleared", async () => {
    await seed([{ id: "a", points: 5 }]);
    const first = await player("g", "/v1/leaderboard");
    expect(first.headers.get("cache-control")).toBe("public, max-age=15");
    await first.arrayBuffer();
    await waitForCache("all", 0);
    await seed([{ id: "b", points: 50 }]);
    const hit = await player("g", "/v1/leaderboard");
    expect(hit.headers.get("cache-control")).toBe("public, max-age=15");
    const cached = (await hit.json()) as Board;
    expect(cached.entries.map((e) => e.displayName)).toEqual(["a"]);
    await caches.default.delete(leaderboardCacheRequest(ORIGIN, "all", 0));
    const fresh = (await (await player("g", "/v1/leaderboard")).json()) as Board;
    expect(fresh.entries.map((e) => e.displayName)).toEqual(["b", "a"]);
  });

  it("rejects bad queries and requires a token", async () => {
    for (const q of ["?period=month", "?generation=-1", "?generation=abc"]) {
      const res = await player("g", `/v1/leaderboard${q}`);
      expect(res.status).toBe(400);
      expect(((await res.json()) as { error: { code: string } }).error.code).toBe("validation_error");
    }
    const anon = await exports.default.fetch(new Request("https://api.test/v1/leaderboard"));
    expect(anon.status).toBe(401);
  });
});

describe("GET /v1/leaderboard/me", () => {
  type Me = { period: string; generation: number; me: { points: number; rank: number } | null };
  const me = async (uid: string, q = "", guest = false) =>
    player(uid, `/v1/leaderboard/me${q}`, guest ? {} : REG);

  it("gives a guest 403 registration_required", async () => {
    const res = await me("guest-1", "", true);
    expect(res.status).toBe(403);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("registration_required");
  });

  it("returns points and rank, with ties sharing a rank", async () => {
    await seed([
      { id: "top", points: 900 },
      { id: "t1", points: 500 },
      { id: "t2", points: 500 },
      { id: "low", points: 100 },
    ]);
    expect(((await (await me("top")).json()) as Me).me).toEqual({ points: 900, rank: 1 });
    expect(((await (await me("t2")).json()) as Me).me).toEqual({ points: 500, rank: 2 });
    expect(((await (await me("low")).json()) as Me).me).toEqual({ points: 100, rank: 4 });
  });

  it("returns null with no entry for that period", async () => {
    await seed([{ id: "x", points: 5 }]);
    const body = (await (await me("x", "?period=week")).json()) as Me;
    expect(body.me).toBeNull();
    expect(((await (await me("nobody")).json()) as Me).me).toBeNull();
  });

  it("shows a shadow-banned caller the rank they would have, and does not count them for others", async () => {
    await seed([
      { id: "p1", points: 300 },
      { id: "ghost", points: 200, banned: true },
      { id: "p2", points: 100 },
    ]);
    expect(((await (await me("ghost")).json()) as Me).me).toEqual({ points: 200, rank: 2 });
    expect(((await (await me("p2")).json()) as Me).me).toEqual({ points: 100, rank: 2 });
    const board = (await (await player("g", "/v1/leaderboard")).json()) as Board;
    expect(board.entries.map((e) => e.displayName)).toEqual(["p1", "p2"]);
  });
});

describe("performance at 50k entries", () => {
  it("uses the points index and answers quickly", async () => {
    const N = 50_000;
    // One INSERT…SELECT over a numbers CTE keeps the seed inside the query budget.
    await env.DB.prepare(
      `WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < ?1)
       INSERT INTO users (id, display_name, country, is_anonymous, created_at, shadow_banned)
       SELECT 'bulk' || i, 'P' || i, 'ET', 0, 1, i % 50 = 0 FROM n`,
    ).bind(N).run();
    await env.DB.prepare(
      `INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
       SELECT 'all', 0, id, (CAST(substr(id, 5) AS INTEGER) * 7919) % 100000, 1 FROM users WHERE id LIKE 'bulk%'`,
    ).run();

    const planOf = async (query: string, ...binds: unknown[]) =>
      (await env.DB.prepare(`EXPLAIN QUERY PLAN ${query}`).bind(...binds).all<{ detail: string }>()).results
        .map((r) => r.detail)
        .join("\n");
    const topPlan = await planOf(TOP_SQL, "all", 0);
    expect(topPlan).toContain("leaderboard_period_gen_points_idx");
    expect(topPlan).not.toMatch(/SCAN e\b/);
    const ownPlan = await planOf(OWN_SQL, "all", 0, "bulk25");
    expect(ownPlan).toContain("COVERING INDEX leaderboard_period_gen_points_idx");
    expect(ownPlan).toContain("users_hidden_idx");
    expect(ownPlan).not.toMatch(/SCAN (o|e)\b/);

    const t0 = Date.now();
    const top = (await (await player("g", "/v1/leaderboard")).json()) as Board;
    const topMs = Date.now() - t0;
    expect(top.entries).toHaveLength(100);

    const t1 = Date.now();
    const mine = (await (await player("bulk25", "/v1/leaderboard/me", REG)).json()) as { me: { rank: number } | null };
    const meMs = Date.now() - t1;
    expect(mine.me?.rank).toBeGreaterThan(0);
    console.log(`leaderboard 50k: top100 ${topMs} ms, me ${meMs} ms`);
    // Loose guards so a slow CI runner does not flake; the plan checks above are the real test.
    expect(topMs).toBeLessThan(2000);
    expect(meMs).toBeLessThan(2000);
  }, 60_000);
});
