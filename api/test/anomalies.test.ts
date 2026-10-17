import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { coefficientOfVariation, dayRules, flagAnomalies, median, weeklyOutlier, type UserDay } from "../src/cron/anomalies";
import { runScheduled } from "../src/cron/rollups";
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

const open = async () =>
  (await env.DB.prepare("SELECT entity_type, entity_ref, reason, status, details_json FROM review_items").all<{
    entity_type: string; entity_ref: string; reason: string; status: string; details_json: string;
  }>()).results;

describe("statistics", () => {
  it("median and coefficient of variation", () => {
    expect(median([5, 1, 3])).toBe(3);
    expect(median([1, 2, 3, 4])).toBe(2.5);
    expect(coefficientOfVariation([1000, 1000, 1000])).toBe(0);
    expect(coefficientOfVariation([])).toBeNull();
    expect(coefficientOfVariation([0, 0])).toBeNull();
    expect(coefficientOfVariation([900, 1100])).toBeCloseTo(0.1, 5);
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
    const d = JSON.parse(items[0]!.details_json);
    expect(d).toMatchObject({ date: DAY, rounds: 60, accuracy: 1, medianResponseMs: 600, responseCv: 0, hardShare: 1 });
  });

  it("an elite human who is fast and accurate trips neither regularity nor accuracy", async () => {
    await user("elite");
    for (let i = 0; i < 6; i++) await play("elite", START + i * 7_200_000, spread(10, 1100));
    expect(await flagAnomalies(env, DAY)).toEqual([]);
    expect(await open()).toEqual([]);
  });

  it("flags 20 sessions in one clock hour, not 19 spread over two", async () => {
    await Promise.all([user("flood"), user("busy")]);
    for (let i = 0; i < 20; i++) await play("flood", START + 3_600_000 + i * 1000, [3000]);
    for (let i = 0; i < 19; i++) await play("busy", START + 3_600_000 + i * 1000, [3000]);
    for (let i = 0; i < 5; i++) await play("busy", START + 7_200_000 + i * 1000, [3000]);
    const flags = await flagAnomalies(env, DAY);
    expect(flags).toHaveLength(1);
    expect(flags[0]).toMatchObject({ userId: "flood", rules: ["session_flood"] });
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
    expect(JSON.parse((await open())[0]!.details_json)).toMatchObject({ week: WEEK, weeklyPoints: 9000, runnerUpPoints: 3000 });

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

  it("re-running a day does not duplicate an open flag; a closed one can be raised again", async () => {
    await user("bot");
    for (let i = 0; i < 6; i++) await play("bot", START + i * 7_200_000, Array(10).fill(600));
    await flagAnomalies(env, DAY);
    await flagAnomalies(env, DAY);
    expect(await open()).toHaveLength(1);
    await env.DB.prepare("UPDATE review_items SET status = 'dismissed'").run();
    await flagAnomalies(env, DAY);
    expect((await open()).map((r) => r.status).sort()).toEqual(["dismissed", "open"]);
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
    for (let i = 0; i < 6; i++) await play("bot", START + i * 7_200_000, Array(10).fill(600));
    await runScheduled(env, START + 86_400_000 + 3_600_000);
    expect((await open()).map((r) => r.entity_ref)).toEqual(["bot"]);
  });
});
