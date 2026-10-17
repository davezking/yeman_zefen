import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { cvFromMoments, dayRules, flagAnomalies, weeklyOutlier, type UserDay } from "../src/cron/anomalies";
import { missingDates, rollUpDay, runScheduled } from "../src/cron/rollups";
import { isoWeek } from "../src/lib/period";

const DAY = "2026-10-14";
const START = Date.parse(`${DAY}T00:00:00.000Z`);
const WEEK = isoWeek(START);

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM review_items"),
    env.DB.prepare("DELETE FROM leaderboard_entries"),
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM analytics_daily"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

let n = 0;
const user = (id: string, o: { anonymous?: boolean; shadow?: boolean } = {}) =>
  env.DB.prepare("INSERT INTO users (id, is_anonymous, created_at, shadow_banned) VALUES (?1, ?2, 0, ?3)")
    .bind(id, o.anonymous ? 1 : 0, o.shadow ? 1 : 0)
    .run();

/** One session whose rounds have the given response times; `correct(i)` decides each answer. */
const play = (userId: string, at: number, ms: number[], o: { correct?: (i: number) => boolean; difficulty?: string } = {}) =>
  env.DB.prepare(
    `INSERT INTO game_sessions (id, user_id, mode, difficulty, received_at, rounds, score, track_ids_json, events_json, flagged)
     VALUES (?1, ?2, 'song', ?3, ?4, ?5, 100, '[]', ?6, 0)`,
  )
    .bind(
      `z${++n}`,
      userId,
      o.difficulty ?? "easy",
      at,
      ms.length,
      JSON.stringify({ rounds: ms.map((responseMs, i) => ({ responseMs, correct: (o.correct ?? (() => true))(i) })) }),
    )
    .run();

/** A deterministic human-looking spread around `mean` (about +/-35 %). */
const spread = (count: number, mean: number) => Array.from({ length: count }, (_, i) => Math.round(mean * (1 + 0.35 * Math.sin(i * 2.1))));

const DAY_MS = 86_400_000;
const NEXT = new Date(START + DAY_MS).toISOString().slice(0, 10);
const bot = async (id: string, start = START) => {
  for (let i = 0; i < 6; i++) await play(id, start + i * 7_200_000, Array(10).fill(600));
};
const days = (row: { details_json: string }) => JSON.parse(row.details_json).days as Record<string, Record<string, unknown>>;

const open = async () =>
  (await env.DB.prepare("SELECT entity_type, entity_ref, reason, status, details_json FROM review_items").all<{
    entity_type: string; entity_ref: string; reason: string; status: string; details_json: string;
  }>()).results;

describe("statistics", () => {
  it("coefficient of variation from moments", () => {
    expect(cvFromMoments(1000, 1_000_000)).toBe(0);
    expect(cvFromMoments(1000, 999_999.9999)).toBe(0); // rounding below zero variance
    expect(cvFromMoments(0, 0)).toBeNull();
    // 900 and 1100: mean 1000, mean of squares 1_010_000, sd 100.
    expect(cvFromMoments(1000, 1_010_000)).toBeCloseTo(0.1, 9);
  });

  const base: UserDay = { userId: "u", sessions: 6, rounds: 60, maxSessionsPerHour: 3, hardShare: 0, accuracy: 0.7, medianResponseMs: 3000, responseCv: 0.4 };
  it("applies each threshold at its boundary", () => {
    expect(dayRules(base)).toEqual([]);
    const fast = { ...base, accuracy: 0.98, medianResponseMs: 899 };
    expect(dayRules(fast)).toEqual(["inhuman_accuracy"]);
    expect(dayRules({ ...fast, medianResponseMs: 900 })).toEqual([]);
    expect(dayRules({ ...fast, accuracy: 0.979 })).toEqual([]);
    expect(dayRules({ ...fast, rounds: 49 })).toEqual([]);
    expect(dayRules({ ...base, responseCv: 0.099 })).toEqual(["bot_regularity"]);
    expect(dayRules({ ...base, responseCv: 0.1 })).toEqual([]);
    expect(dayRules({ ...base, responseCv: 0.01, rounds: 29 })).toEqual([]);
    expect(dayRules({ ...base, maxSessionsPerHour: 20 })).toEqual(["session_flood"]);
    expect(dayRules({ ...base, maxSessionsPerHour: 19 })).toEqual([]);
  });
  it("weekly outlier needs both the percentile and a 3x lead", () => {
    expect(weeklyOutlier(3000, 1000, 900)).toBe(true);
    expect(weeklyOutlier(2999, 1000, 900)).toBe(false);
    expect(weeklyOutlier(3000, 1000, 3000)).toBe(false);
    expect(weeklyOutlier(0, 0, 0)).toBe(false);
  });
});

describe("flagAnomalies", () => {
  it("flags a bot (instant, perfect, constant), not an honest player or an elite human", async () => {
    await Promise.all(["honest", "elite", "bot"].map((u) => user(u)));
    // Honest: casual, 60 rounds, 65 % right, slow and varied.
    for (let i = 0; i < 6; i++) await play("honest", START + i * 7_200_000, spread(10, 3500), { correct: (r) => r % 3 !== 0 });
    // Elite human: 99 % right over 60 rounds with fast, but human-variable, answers; 1 s median.
    for (let i = 0; i < 6; i++) await play("elite", START + i * 7_200_000, spread(10, 1100), { correct: (r) => !(i === 0 && r === 0) });
    // Bot: every answer in 600 ms, always right.
    for (let i = 0; i < 6; i++) await play("bot", START + i * 7_200_000, Array(10).fill(600), { difficulty: "hard" });

    const flags = await flagAnomalies(env, DAY);
    expect(flags.map((f) => f.userId)).toEqual(["bot"]);
    expect(flags[0]!.rules).toEqual(["inhuman_accuracy", "bot_regularity"]);

    const items = await open();
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ entity_type: "user", entity_ref: "bot", reason: "score_anomaly", status: "open" });
    const d = days(items[0]!)[DAY];
    expect(d).toMatchObject({ rules: ["inhuman_accuracy", "bot_regularity"], rounds: 60, accuracy: 1, medianResponseMs: 600, responseCv: 0, hardShare: 1 });
  });

  it("an elite human who is fast and accurate trips neither regularity nor accuracy", async () => {
    await user("elite");
    for (let i = 0; i < 6; i++) await play("elite", START + i * 7_200_000, spread(10, 1100));
    expect(await flagAnomalies(env, DAY)).toEqual([]);
    expect(await open()).toEqual([]);
  });

  it("flags 20 sessions within any 60 minutes, even across a clock hour; not 19, or 20 spread over 61", async () => {
    await Promise.all(["flood", "straddle", "busy", "slow"].map((u) => user(u)));
    const h = START + 3_600_000;
    for (let i = 0; i < 20; i++) await play("flood", h + i * 1000, [3000]);
    // 10 at :50-:59, 10 at :00-:09 of the next hour: each clock hour has 10.
    for (let i = 0; i < 10; i++) await play("straddle", h - 600_000 + i * 60_000, [3000]);
    for (let i = 0; i < 10; i++) await play("straddle", h + i * 60_000, [3000]);
    for (let i = 0; i < 19; i++) await play("busy", h + i * 1000, [3000]);
    // 20 sessions, first and last exactly 60 minutes apart: no window of 60 minutes holds all 20.
    for (let i = 0; i < 20; i++) await play("slow", h + Math.round((i * 3_600_000) / 19), [3000]);
    const flags = await flagAnomalies(env, DAY);
    expect(flags.map((f) => f.userId).sort()).toEqual(["flood", "straddle"]);
    expect(flags[0]!.rules).toEqual(["session_flood"]);
  });

  it("takes the exact median of an even number of rounds, in SQL", async () => {
    await user("m");
    // 50 rounds, all right: 25 at 400 ms and 25 at 800 ms, in two sessions. Median (400 + 800) / 2 = 600, CV 1/3.
    await play("m", START, [...Array(15).fill(800), ...Array(10).fill(400)]);
    await play("m", START + 1, [...Array(15).fill(400), ...Array(10).fill(800)]);
    const [f, ...rest] = await flagAnomalies(env, DAY);
    expect(rest).toEqual([]);
    expect(f).toMatchObject({ userId: "m", rules: ["inhuman_accuracy"] });
    expect(f!.metrics).toMatchObject({ medianResponseMs: 600, responseCv: 0.333, accuracy: 1, rounds: 50 });
  });

  it("ignores anonymous, shadow-banned users and other days", async () => {
    await user("anon", { anonymous: true });
    await user("shadow", { shadow: true });
    await user("early");
    for (const u of ["anon", "shadow"]) for (let i = 0; i < 6; i++) await play(u, START + i, Array(10).fill(600));
    for (let i = 0; i < 6; i++) await play("early", START - 1 - i, Array(10).fill(600));
    expect(await flagAnomalies(env, DAY)).toEqual([]);
  });

  it("flags a runaway weekly leader, but not a close race or a lone player below the lead", async () => {
    const board = async (rows: [string, number][]) => {
      await env.DB.prepare("DELETE FROM leaderboard_entries").run();
      for (const [u, p] of rows) {
        await user(u).catch(() => {});
        await env.DB.prepare("INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at) VALUES (?1, 0, ?2, ?3, 0)")
          .bind(WEEK, u, p)
          .run();
      }
    };
    await board([["a", 9000], ["b", 3000], ["c", 100]]);
    const flags = await flagAnomalies(env, DAY);
    expect(flags).toHaveLength(1);
    expect(flags[0]).toMatchObject({ userId: "a", rules: ["weekly_outlier"] });
    expect(days((await open())[0]!)[DAY]).toMatchObject({ rules: ["weekly_outlier"], week: WEEK, weeklyPoints: 9000, runnerUpPoints: 3000 });

    // Dismissed: the same week's lead is not raised again on a later day of the week.
    await env.DB.prepare("UPDATE review_items SET status = 'dismissed'").run();
    expect(await flagAnomalies(env, NEXT)).toEqual([]);
    expect((await open()).map((r) => r.status)).toEqual(["dismissed"]);

    await env.DB.prepare("DELETE FROM review_items").run();
    await board([["a", 8999], ["b", 3000], ["c", 100]]);
    expect(await flagAnomalies(env, DAY)).toEqual([]);
  });

  it("with 1000+ players the leader must beat the others' 99.9th percentile", async () => {
    await env.DB.prepare(`INSERT INTO users (id, is_anonymous, created_at, shadow_banned) SELECT value, 0, 0, 0 FROM json_each(?1)`)
      .bind(JSON.stringify(Array.from({ length: 1500 }, (_, i) => `u${i}`)))
      .run();
    await env.DB.prepare(
      `INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
       SELECT ?1, 0, value, CASE WHEN value = 'u0' THEN 100000 ELSE 10 + (CAST(substr(value, 2) AS INTEGER) % 50) * 200 END, 0
       FROM json_each(?2)`,
    )
      .bind(WEEK, JSON.stringify(Array.from({ length: 1500 }, (_, i) => `u${i}`)))
      .run();
    // Runner-up is ~9810 (a 10x lead) and the p99.9 of the rest is below the leader.
    const flags = await flagAnomalies(env, DAY);
    expect(flags.map((f) => f.userId)).toEqual(["u0"]);
  });

  it("re-running a day does not duplicate an open flag", async () => {
    await user("bot");
    await bot("bot");
    await flagAnomalies(env, DAY);
    await flagAnomalies(env, DAY);
    const items = await open();
    expect(items).toHaveLength(1);
    expect(Object.keys(days(items[0]!))).toEqual([DAY]);
  });

  it("adds a later day's evidence to the open item", async () => {
    await user("bot");
    await bot("bot");
    await flagAnomalies(env, DAY);
    await bot("bot", START + DAY_MS);
    await flagAnomalies(env, NEXT);
    const items = await open();
    expect(items).toHaveLength(1);
    expect(Object.keys(days(items[0]!)).sort()).toEqual([DAY, NEXT]);
  });

  it("a dismissal sticks for that day; new evidence on a later day opens a new item", async () => {
    await user("bot");
    await bot("bot");
    await flagAnomalies(env, DAY);
    await env.DB.prepare("UPDATE review_items SET status = 'dismissed'").run();
    await flagAnomalies(env, DAY);
    expect((await open()).map((r) => r.status)).toEqual(["dismissed"]);
    await bot("bot", START + DAY_MS);
    await flagAnomalies(env, NEXT);
    const items = await open();
    expect(items.map((r) => r.status).sort()).toEqual(["dismissed", "open"]);
    expect(Object.keys(days(items.find((r) => r.status === "open")!))).toEqual([NEXT]);
  });

  it("marks the day as checked, with the number of users flagged", async () => {
    await user("bot");
    await bot("bot");
    await flagAnomalies(env, DAY);
    expect(await env.DB.prepare("SELECT value FROM analytics_daily WHERE date = ?1 AND metric = 'anomaly_pass'").bind(DAY).first()).toEqual({ value: 1 });
  });

  it("only flags: no ban, no score change, no session change", async () => {
    await user("bot");
    for (let i = 0; i < 6; i++) await play("bot", START + i * 7_200_000, Array(10).fill(600));
    await env.DB.prepare("INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at) VALUES (?1, 0, 'bot', 5000, 0)").bind(WEEK).run();
    await flagAnomalies(env, DAY);
    expect(await env.DB.prepare("SELECT shadow_banned, deleted_at FROM users WHERE id = 'bot'").first()).toEqual({ shadow_banned: 0, deleted_at: null });
    expect(await env.DB.prepare("SELECT points FROM leaderboard_entries WHERE user_id = 'bot'").first()).toEqual({ points: 5000 });
    expect(await env.DB.prepare("SELECT SUM(flagged) AS f, SUM(score) AS s FROM game_sessions").first()).toEqual({ f: 0, s: 600 });
  });

  it("rejects a bad date", async () => {
    await expect(flagAnomalies(env, "2026-02-30")).rejects.toThrow("not a calendar date");
  });
});

describe("nightly run", () => {
  it("flags yesterday's bot as part of runScheduled", async () => {
    await user("bot");
    await bot("bot");
    await runScheduled(env, START + DAY_MS + 3_600_000);
    expect((await open()).map((r) => r.entity_ref)).toEqual(["bot"]);
  });

  it("retries a day whose anomaly pass never ran, even though it is already rolled up", async () => {
    await user("bot");
    await bot("bot");
    // The 14th's night ran the roll-ups but its pass failed (no marker); the 15th's run catches up.
    await rollUpDay(env, DAY);
    for (let d = 1; d <= 6; d++) {
      const date = new Date(START - d * DAY_MS).toISOString().slice(0, 10);
      await rollUpDay(env, date);
      await flagAnomalies(env, date);
    }
    await runScheduled(env, START + 2 * DAY_MS + 3_600_000);
    expect((await open()).map((r) => r.entity_ref)).toEqual(["bot"]);
    expect(await missingDates(env, START + 2 * DAY_MS + 3_600_000, "anomaly_pass")).toEqual([]);
  });

  it("a roll-up re-run keeps the day's anomaly marker", async () => {
    await flagAnomalies(env, DAY);
    await rollUpDay(env, DAY);
    expect(await missingDates(env, START + DAY_MS + 1, "anomaly_pass")).not.toContain(DAY);
  });
});
