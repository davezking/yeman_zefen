import { env } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { MAX_DAYS_PER_RUN, dayBounds, missingDates, rollUpDay, runScheduled, utcDate } from "../src/cron/rollups";
import { api, countingDb, makeArtist, makeTrack, installTestJwks, removeTestJwks, resetCatalog, seedAdmins } from "./helpers";

const DAY = "2026-10-14";
const DAY_START = Date.parse(`${DAY}T00:00:00.000Z`);
const MS = 86_400_000;

let t: number[] = [];

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
  await resetCatalog();
  const artist = await makeArtist("አርቲስት");
  t = (await Promise.all([1, 2, 3, 4].map(() => makeTrack(artist.id, { status: "approved" })))).map((x) => x.id);
});
afterAll(removeTestJwks);

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM royalty_daily"),
    env.DB.prepare("DELETE FROM ad_events_daily"),
    env.DB.prepare("DELETE FROM analytics_daily"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

let n = 0;
async function user(id: string, createdAt: number) {
  await env.DB.prepare("INSERT OR IGNORE INTO users (id, is_anonymous, created_at) VALUES (?1, 1, ?2)").bind(id, createdAt).run();
}
async function session(
  userId: string,
  receivedAt: number,
  tracks: number[],
  o: { country?: string | null; interstitial?: number; rewarded?: number; flagged?: boolean } = {},
) {
  await env.DB.prepare(
    `INSERT INTO game_sessions (id, user_id, mode, received_at, rounds, score, track_ids_json, events_json, country, flagged)
     VALUES (?1, ?2, 'song', ?3, ?4, 0, ?5, ?6, ?7, ?8)`,
  )
    .bind(
      `s${++n}`,
      userId,
      receivedAt,
      tracks.length,
      JSON.stringify(tracks),
      JSON.stringify({ clientEndedAt: 0, rounds: [], ads: { interstitialShown: o.interstitial ?? 0, rewardedCompleted: o.rewarded ?? 0 } }),
      o.country === undefined ? "ET" : o.country,
      o.flagged ? 1 : 0,
    )
    .run();
}

async function dump(date: string) {
  const q = (sql: string) => env.DB.prepare(sql).bind(date).all();
  return {
    royalty: (await q("SELECT * FROM royalty_daily WHERE date = ?1 ORDER BY track_id")).results,
    ads: (await q("SELECT * FROM ad_events_daily WHERE date = ?1 ORDER BY country, format, event")).results,
    analytics: (await q("SELECT * FROM analytics_daily WHERE date = ?1 ORDER BY metric, dimension")).results,
  };
}
const metric = (rows: { metric: string; dimension: string; value: number }[], m: string, d = "") =>
  rows.find((r) => r.metric === m && r.dimension === d)?.value;

async function seedDay() {
  await user("a", DAY_START - 5 * MS);
  await user("b", DAY_START + 1000); // new on DAY
  await user("c", DAY_START + 2000); // new on DAY, no session
  await session("a", DAY_START + 1000, [t[0]!, t[1]!, t[1]!], { interstitial: 2, rewarded: 1 });
  await session("a", DAY_START + 5000, [t[0]!], { interstitial: 1, country: "US" });
  await session("b", DAY_START + 9000, [t[2]!, t[0]!], { country: null, rewarded: 2, flagged: true });
  await session("deleted", DAY_START + 9500, [t[3]!], { country: "ET" });
}

describe("rollUpDay", () => {
  it("counts every played track, wrong rounds and flagged sessions included", async () => {
    await seedDay();
    const s = await rollUpDay(env, DAY);
    const { royalty } = await dump(DAY);
    expect(royalty.map((r) => [(r as { track_id: number }).track_id, (r as { plays: number }).plays])).toEqual([
      [t[0], 3],
      [t[1], 2],
      [t[2], 1],
      [t[3], 1],
    ]);
    expect(s).toMatchObject({ date: DAY, sessions: 4, rounds: 7, royaltyRows: 4 });
  });

  it("royalty total equals the sum of json_array_length(track_ids_json)", async () => {
    await seedDay();
    await rollUpDay(env, DAY);
    const total = await env.DB.prepare("SELECT SUM(plays) AS v FROM royalty_daily WHERE date = ?1").bind(DAY).first<{ v: number }>();
    const expected = await env.DB.prepare(
      "SELECT SUM(json_array_length(track_ids_json)) AS v FROM game_sessions WHERE received_at >= ?1 AND received_at < ?2",
    )
      .bind(DAY_START, DAY_START + MS)
      .first<{ v: number }>();
    expect(total!.v).toBe(expected!.v);
    expect(total!.v).toBe(7);
  });

  it("rolls up ads per country and format, skipping zeros", async () => {
    await seedDay();
    await rollUpDay(env, DAY);
    const { ads } = await dump(DAY);
    expect(ads).toEqual([
      { date: DAY, country: "ET", format: "interstitial", event: "shown", count: 2 },
      { date: DAY, country: "ET", format: "rewarded", event: "completed", count: 1 },
      { date: DAY, country: "US", format: "interstitial", event: "shown", count: 1 },
      { date: DAY, country: "XX", format: "rewarded", event: "completed", count: 2 },
    ]);
  });

  it("rolls up the analytics metrics", async () => {
    await seedDay();
    await rollUpDay(env, DAY);
    const { analytics } = (await dump(DAY)) as unknown as { analytics: { metric: string; dimension: string; value: number }[] };
    expect(metric(analytics, "sessions")).toBe(4);
    expect(metric(analytics, "rounds")).toBe(7);
    expect(metric(analytics, "rounds_per_session")).toBe(175); // 7 / 4 = 1.75, stored x100
    expect(metric(analytics, "dau")).toBe(3); // a, b, and the deleted placeholder as one player
    expect(metric(analytics, "new_users")).toBe(2); // b and c; not a, not the placeholder
    expect(metric(analytics, "plays_by_country", "ET")).toBe(4);
    expect(metric(analytics, "plays_by_country", "US")).toBe(1);
    expect(metric(analytics, "plays_by_country", "XX")).toBe(2);
  });

  it("writes zero rows for a day with no sessions, and marks the day done", async () => {
    const s = await rollUpDay(env, DAY);
    expect(s).toMatchObject({ sessions: 0, rounds: 0, royaltyRows: 0, adRows: 0 });
    const { royalty, ads, analytics } = (await dump(DAY)) as unknown as { royalty: unknown[]; ads: unknown[]; analytics: { metric: string; value: number }[] };
    expect(royalty).toEqual([]);
    expect(ads).toEqual([]);
    expect(analytics.map((r) => r.metric).sort()).toEqual(["dau", "new_users", "rounds", "rounds_per_session", "sessions"]);
    expect(analytics.every((r) => r.value === 0)).toBe(true);
  });

  it("running twice gives identical rows, and a rerun replaces stale ones", async () => {
    await seedDay();
    await rollUpDay(env, DAY);
    const first = await dump(DAY);
    await rollUpDay(env, DAY);
    expect(await dump(DAY)).toEqual(first);

    // A stale row for a track no session played, and a late session: both are corrected by a rerun.
    await env.DB.prepare("UPDATE royalty_daily SET plays = 99 WHERE date = ?1 AND track_id = ?2").bind(DAY, t[3]).run();
    await session("b", DAY_START + 20_000, [t[3]!]);
    await rollUpDay(env, DAY);
    const after = (await dump(DAY)).royalty as { track_id: number; plays: number }[];
    expect(after.find((r) => r.track_id === t[3])?.plays).toBe(2);
  });

  it("does not touch other days", async () => {
    await session("deleted", DAY_START - 1000, [t[0]!]);
    await rollUpDay(env, "2026-10-13");
    await rollUpDay(env, DAY);
    expect((await dump("2026-10-13")).royalty).toHaveLength(1);
  });

  it("puts 23:59:59.999 UTC on its own day and 00:00:00.000 on the next", async () => {
    const end = DAY_START + MS;
    await session("deleted", end - 1000, [t[0]!]); // 23:59:59
    await session("deleted", end - 1, [t[0]!]); // 23:59:59.999
    await session("deleted", end, [t[1]!]); // next day, 00:00:00.000
    await session("deleted", DAY_START, [t[2]!]); // this day, 00:00:00.000
    await rollUpDay(env, DAY);
    await rollUpDay(env, utcDate(end));
    const plays = (r: unknown[]) => (r as { track_id: number; plays: number }[]).map((x) => [x.track_id, x.plays]);
    expect(plays((await dump(DAY)).royalty)).toEqual([[t[0], 2], [t[2], 1]]);
    expect(plays((await dump(utcDate(end))).royalty)).toEqual([[t[1], 1]]);
  });

  it("rejects a date that is not a calendar day", async () => {
    await expect(rollUpDay(env, "2026-02-30")).rejects.toThrow();
    await expect(rollUpDay(env, "2026-1-1")).rejects.toThrow();
    expect(dayBounds("2026-10-14")).toEqual({ start: DAY_START, end: DAY_START + MS });
  });
});

describe("runScheduled", () => {
  const NOW = Date.parse("2026-10-16T00:30:00.000Z"); // the cron fires; yesterday is 2026-10-15

  it("rolls up yesterday", async () => {
    await session("deleted", Date.parse("2026-10-15T12:00:00Z"), [t[0]!]);
    const done = await runScheduled(env, NOW);
    expect(done.map((d) => d.date)).toContain("2026-10-15");
    expect((await dump("2026-10-15")).royalty).toHaveLength(1);
  });

  it("fills the days of the last week that were never rolled up, and only those", async () => {
    await rollUpDay(env, "2026-10-12");
    await rollUpDay(env, "2026-10-13");
    expect(await missingDates(env, NOW)).toEqual(["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-14", "2026-10-15"]);
    const done = await runScheduled(env, NOW);
    expect(done.map((d) => d.date)).toEqual(["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-14", "2026-10-15"]);
    expect(await missingDates(env, NOW)).toEqual([]);
    // Next night: only the new yesterday is missing; older days are not recomputed.
    const next = await runScheduled(env, NOW + MS);
    expect(next.map((d) => d.date)).toEqual(["2026-10-16"]);
  });

  it("recovers a missed night on the next run", async () => {
    await session("deleted", Date.parse("2026-10-14T12:00:00Z"), [t[1]!]);
    for (const d of ["09", "10", "11", "12", "13", "14"]) await rollUpDay(env, `2026-10-${d}`);
    // The night of the 15th rolled up the 14th (above) and everything before it.
    // The night of the 16th never ran; the 17th's run fills the 15th and 16th.
    const done = await runScheduled(env, NOW + MS);
    expect(done.map((d) => d.date)).toEqual(["2026-10-15", "2026-10-16"]);
  });

  it("stays inside the Free plan's 50 queries even with the whole week missing", async () => {
    const { db, counter } = countingDb(env.DB);
    const done = await runScheduled({ DB: db }, NOW);
    expect(done).toHaveLength(MAX_DAYS_PER_RUN);
    expect(counter.queries).toBeLessThanOrEqual(45);
    // The day left over is picked up by the next night's run.
    expect(await missingDates(env, NOW)).toHaveLength(7 - MAX_DAYS_PER_RUN);
  });

  it("keeps going when one day fails, then throws", async () => {
    // A DB whose batch fails for one date; everything else goes to the real one.
    const real = env.DB;
    const flaky = {
      prepare: (sql: string) => ({
        bind: (...v: unknown[]) => ({ v, inner: real.prepare(sql).bind(...v), all: () => real.prepare(sql).bind(...v).all() }),
      }),
      batch: (stmts: { v: unknown[]; inner: D1PreparedStatement }[]) =>
        stmts[0]!.v[0] === "2026-10-12" ? Promise.reject(new Error("boom")) : real.batch(stmts.map((x) => x.inner)),
    } as unknown as D1Database;
    await expect(runScheduled({ DB: flaky }, NOW)).rejects.toThrow(/2026-10-12/);
    // The 12th is still missing; the 13th and 14th were cut by the per-run cap, not by the failure.
    expect(await missingDates(env, NOW)).toEqual(["2026-10-12", "2026-10-13", "2026-10-14"]);
    await runScheduled(env, NOW);
    expect(await missingDates(env, NOW)).toEqual([]);
  });

  it("leaves out a play of an unknown track instead of failing the day", async () => {
    await session("deleted", DAY_START + 1000, [t[0]!, 999_999], { interstitial: 1 });
    await rollUpDay(env, DAY);
    const { royalty, ads } = await dump(DAY);
    expect(royalty).toEqual([{ date: DAY, track_id: t[0], plays: 1 }]);
    expect(ads).toHaveLength(1);
  });

  it("a malformed events_json costs only its own ads", async () => {
    await session("deleted", DAY_START + 1000, [t[0]!], { interstitial: 2 });
    await env.DB.prepare(
      `INSERT INTO game_sessions (id, user_id, mode, received_at, rounds, score, track_ids_json, events_json, country)
       VALUES ('bad', 'deleted', 'song', ?1, 1, 0, ?2, 'not json', 'ET')`,
    )
      .bind(DAY_START + 2000, JSON.stringify([t[1]]))
      .run();
    await rollUpDay(env, DAY);
    const { royalty, ads } = await dump(DAY);
    expect(royalty).toHaveLength(2);
    expect(ads).toEqual([{ date: DAY, country: "ET", format: "interstitial", event: "shown", count: 2 }]);
  });
});

describe("POST /admin/rollups/run", () => {
  it("rolls up the given day", async () => {
    await seedDay();
    const res = await api("/admin/rollups/run", { body: { date: DAY } });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      rollup: { date: DAY, sessions: 4, rounds: 7, royaltyRows: 4, adRows: 4, analyticsRows: 8 },
    });
  });

  it("is admins only", async () => {
    expect((await api("/admin/rollups/run", { body: { date: DAY }, as: "editor" })).status).toBe(403);
  });

  it.each([
    [{}],
    [{ date: "2026-02-30" }],
    [{ date: "yesterday" }],
    [{ date: utcDate(Date.now()) }],
    [{ date: utcDate(Date.now() + 3 * MS) }],
    [{ date: DAY, extra: 1 }],
  ])("refuses %j", async (body) => {
    const res = await api("/admin/rollups/run", { body });
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("validation_error");
  });
});
