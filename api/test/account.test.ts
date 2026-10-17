import { env, exports } from "cloudflare:workers";
import { generateKeyPair } from "jose";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { isoWeekSql } from "../src/lib/backfill";
import { isoWeek } from "../src/lib/period";
import { MERGE_TOKEN_MAX_AGE_S } from "../src/routes/me";
import { countingDb, installFirebaseJwks, makeArtist, makeTrack, removeFirebaseJwks, resetCatalog, signFirebaseToken } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);

const ERA = 3;
const GOOGLE = "google.com";
const DAY = 86_400_000;
let trackIds: number[] = [];

beforeAll(async () => {
  await resetCatalog();
  const artists = await Promise.all(["ሀ", "ለ", "ሐ", "መ"].map((n) => makeArtist(`መለያ ${n}`)));
  trackIds = (await Promise.all(artists.map((a) => makeTrack(a.id, { generationId: ERA, status: "approved" })))).map((t) => t.id);
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM leaderboard_entries"),
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

/** `correct` right song answers at 2000 ms (143 points each on intro/easy), the rest wrong. */
function session(correct: number, generationId = 0) {
  const now = Date.now();
  const t = (i: number) => trackIds[i % trackIds.length]!;
  return {
    id: crypto.randomUUID(),
    mode: "intro",
    generationId,
    difficulty: "easy",
    clientStartedAt: now - 60_000,
    clientEndedAt: now - 1000,
    offline: false,
    rounds: [0, 1, 2, 3].map((i) => ({
      trackId: t(i),
      question: "song",
      optionIds: [t(i), t(i + 1), t(i + 2), t(i + 3)],
      chosenId: i < correct ? t(i) : t(i + 1),
      responseMs: 2000,
      hintUsed: false,
    })),
    ads: { interstitialShown: 0, rewardedCompleted: 0 },
  };
}

async function call(path: string, token: string, body?: unknown, DB?: D1Database) {
  const req = new Request(`https://api.test${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, ...(body === undefined ? {} : { "content-type": "application/json" }) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!DB) return exports.default.fetch(req);
  const { default: app } = await import("../src/index");
  return app.fetch(req, { ...env, DB });
}

async function postSession(uid: string, body: unknown, provider?: string) {
  const res = await call("/v1/sessions", await signFirebaseToken(uid, { provider }), body);
  expect(res.status).toBe(200);
  return (await res.json()) as { score: number; flagged: boolean };
}

const registered = async (uid: string) => call("/v1/me/registered", await signFirebaseToken(uid, { provider: GOOGLE }));
const merge = async (uid: string, anonymousIdToken: string) =>
  call("/v1/me/merge", await signFirebaseToken(uid, { provider: GOOGLE }), { anonymousIdToken });

async function board(uid: string) {
  const { results } = await env.DB.prepare(
    "SELECT period, generation_id, points FROM leaderboard_entries WHERE user_id = ? ORDER BY period, generation_id",
  ).bind(uid).all<{ period: string; generation_id: number; points: number }>();
  return results;
}

async function sessionOwners() {
  const { results } = await env.DB.prepare("SELECT user_id, COUNT(*) AS n FROM game_sessions GROUP BY user_id ORDER BY user_id").all();
  return results;
}

const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

/** Store a session row directly, for backfill cases the live endpoint cannot produce (old weeks). */
async function storeRow(uid: string, row: { score: number; receivedAt: number; generationId?: number; flagged?: boolean }) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR IGNORE INTO users (id, is_anonymous, created_at) VALUES (?, 1, 1)").bind(uid),
    env.DB.prepare(
      `INSERT INTO game_sessions (id, user_id, mode, generation_id, difficulty, received_at, rounds, score, track_ids_json, events_json, flagged)
       VALUES (?, ?, 'intro', ?, 'easy', ?, 4, ?, '[]', '{}', ?)`,
    ).bind(crypto.randomUUID(), uid, row.generationId ?? 0, row.receivedAt, row.score, row.flagged ? 1 : 0),
  ]);
}

describe("isoWeekSql", () => {
  it("matches isoWeek() for every day across three year boundaries", async () => {
    const start = Date.UTC(2024, 11, 20, 13);
    const days = Array.from({ length: 800 }, (_, i) => start + i * DAY);
    const { results } = await env.DB.prepare(
      `SELECT j.value AS ms, ${isoWeekSql("j.value")} AS week FROM json_each(?1) j`,
    ).bind(JSON.stringify(days)).all<{ ms: number; week: string }>();
    expect(results).toHaveLength(days.length);
    for (const r of results) expect(r.week, new Date(r.ms).toISOString()).toBe(isoWeek(r.ms));
  });

  it("puts 2026-12-31 and 2027-01-01 in 2026-W53, and Monday 00:00 in the next week", async () => {
    const at = [Date.UTC(2026, 11, 31), Date.UTC(2027, 0, 1), Date.UTC(2027, 0, 3, 23, 59, 59, 999), Date.UTC(2027, 0, 4)];
    const { results } = await env.DB.prepare(`SELECT ${isoWeekSql("j.value")} AS week FROM json_each(?1) j`)
      .bind(JSON.stringify(at)).all<{ week: string }>();
    expect(results.map((r) => r.week)).toEqual(["2026-W53", "2026-W53", "2026-W53", "2027-W01"]);
  });
});

describe("POST /v1/me/registered", () => {
  it("a guest with 3 synced sessions who links Google ranks with exactly those points", async () => {
    const scores = [];
    for (const n of [1, 2, 3]) scores.push((await postSession("u-link", session(n))).score);
    const eraScore = (await postSession("u-link", session(1, ERA))).score;
    expect(await board("u-link")).toEqual([]); // guests never rank

    const res = await registered("u-link");
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ id: "u-link", isAnonymous: false });

    const total = scores.reduce((a, b) => a + b, 0) + eraScore;
    const week = isoWeek(Date.now());
    expect(await board("u-link")).toEqual([
      { period: week, generation_id: 0, points: total },
      { period: week, generation_id: ERA, points: eraScore },
      { period: "all", generation_id: 0, points: total },
      { period: "all", generation_id: ERA, points: eraScore },
    ].sort((a, b) => (a.period < b.period ? -1 : a.period > b.period ? 1 : a.generation_id - b.generation_id)));

    // The leaderboard endpoint sees it too.
    const me = await exports.default.fetch(new Request("https://api.test/v1/leaderboard/me", {
      headers: { authorization: `Bearer ${await signFirebaseToken("u-link", { provider: GOOGLE })}` },
    }));
    expect(((await me.json()) as { me: { points: number } }).me.points).toBe(total);
  });

  it("is idempotent, and later sessions add on top without double counting", async () => {
    await postSession("u-rep", session(2));
    await registered("u-rep");
    const once = await board("u-rep");
    await registered("u-rep");
    expect(await board("u-rep")).toEqual(once);

    const more = await postSession("u-rep", session(1), GOOGLE);
    const after = await board("u-rep");
    expect(after.find((r) => r.period === "all")!.points).toBe(once.find((r) => r.period === "all")!.points + more.score);
    // A rebuild gives the same rows the live writes built.
    await registered("u-rep");
    expect(await board("u-rep")).toEqual(after);
  });

  it("rebuilds old weeks by their server receive time and skips flagged and zero sessions", async () => {
    const w1 = Date.UTC(2026, 11, 30, 10); // 2026-W53
    const w2 = Date.UTC(2027, 0, 5, 10); // 2027-W01
    await storeRow("u-old", { score: 100, receivedAt: w1 });
    await storeRow("u-old", { score: 50, receivedAt: w1 + 3600_000, generationId: ERA });
    await storeRow("u-old", { score: 70, receivedAt: w2 });
    await storeRow("u-old", { score: 999, receivedAt: w2, flagged: true });
    await storeRow("u-old", { score: 0, receivedAt: w2, generationId: 4 });
    await registered("u-old");
    expect(await board("u-old")).toEqual([
      { period: "2026-W53", generation_id: 0, points: 150 },
      { period: "2026-W53", generation_id: ERA, points: 50 },
      { period: "2027-W01", generation_id: 0, points: 70 },
      { period: "all", generation_id: 0, points: 220 },
      { period: "all", generation_id: ERA, points: 50 },
    ]);
    const row = await env.DB.prepare("SELECT updated_at FROM leaderboard_entries WHERE user_id = 'u-old' AND period = 'all' AND generation_id = 0").first();
    expect(row).toEqual({ updated_at: w2 });
  });

  it("gives a shadow-banned player no new rows and keeps the ones they had", async () => {
    await storeRow("u-ban", { score: 100, receivedAt: Date.now() });
    await env.DB.prepare("UPDATE users SET shadow_banned = 1 WHERE id = 'u-ban'").run();
    expect((await registered("u-ban")).status).toBe(200);
    expect(await board("u-ban")).toEqual([]);

    // Points from before a ban survive a rebuild, so lifting the ban restores them.
    await env.DB.prepare("UPDATE users SET shadow_banned = 0 WHERE id = 'u-ban'").run();
    await registered("u-ban");
    const before = await board("u-ban");
    expect(before.find((r) => r.period === "all")!.points).toBe(100);
    await env.DB.prepare("UPDATE users SET shadow_banned = 1 WHERE id = 'u-ban'").run();
    await registered("u-ban");
    expect(await board("u-ban")).toEqual(before);
  });

  it("refuses a guest token", async () => {
    const res = await call("/v1/me/registered", await signFirebaseToken("u-g"));
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("registration_required");
  });

  it("a guest token cached after linking does not turn the account back into a guest", async () => {
    await registered("u-stale");
    const res = await postSession("u-stale", session(2)); // old anonymous token
    const user = await env.DB.prepare("SELECT is_anonymous FROM users WHERE id = 'u-stale'").first();
    expect(user).toEqual({ is_anonymous: 0 });
    expect((await board("u-stale")).find((r) => r.period === "all")!.points).toBe(res.score);
  });
});

describe("POST /v1/me/merge", () => {
  it("moves a second phone's guest sessions into the existing account, counted once", async () => {
    // The existing account already has history of its own.
    const own = await postSession("u-main", session(3), GOOGLE);
    const g1 = await postSession("u-phone2", session(1));
    const g2 = await postSession("u-phone2", session(2));
    const guestToken = await signFirebaseToken("u-phone2");

    const res = await merge("u-main", guestToken);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ id: "u-main", isAnonymous: false, mergedSessions: 2 });

    const all = (await board("u-main")).find((r) => r.period === "all" && r.generation_id === 0)!;
    expect(all.points).toBe(own.score + g1.score + g2.score);
    expect(await sessionOwners()).toEqual([{ user_id: "u-main", n: 3 }]);
    expect(await env.DB.prepare("SELECT id FROM users WHERE id = 'u-phone2'").first()).toBeNull();

    // A replay (the app retrying after a lost response) moves nothing and changes nothing.
    const again = await merge("u-main", guestToken);
    expect(again.status).toBe(200);
    expect(await again.json()).toMatchObject({ mergedSessions: 0 });
    expect((await board("u-main")).find((r) => r.period === "all" && r.generation_id === 0)!.points).toBe(all.points);
  });

  it("accepts a guest token up to 30 days old", async () => {
    await postSession("u-old-guest", session(1));
    const token = await signFirebaseToken("u-old-guest", { ageS: MERGE_TOKEN_MAX_AGE_S - 3600 });
    const res = await merge("u-acct", token);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ mergedSessions: 1 });
  });

  it("rejects a guest token older than 30 days, or a forged one, with 401", async () => {
    await postSession("u-g2", session(1));
    const old = await merge("u-acct", await signFirebaseToken("u-g2", { ageS: MERGE_TOKEN_MAX_AGE_S + 120 }));
    expect(old.status).toBe(401);
    expect(await errorCode(old)).toBe("invalid_anonymous_token");

    const other = (await generateKeyPair("RS256")).privateKey;
    const forged = await merge("u-acct", await signFirebaseToken("u-g2", { key: other }));
    expect(forged.status).toBe(401);
    expect((await merge("u-acct", "not.a.jwt")).status).toBe(401);
    expect(await sessionOwners()).toEqual([{ user_id: "u-g2", n: 1 }]);
  });

  it("never merges a registered account: 409 for a registered token or a uid that has registered", async () => {
    await postSession("u-victim", session(3), GOOGLE);
    // A token that is not a guest token.
    const reg = await merge("u-thief", await signFirebaseToken("u-victim", { provider: GOOGLE }));
    expect(reg.status).toBe(409);
    expect(await errorCode(reg)).toBe("not_a_guest");

    // An old guest token for a uid that has since linked a provider of its own.
    const oldGuestToken = await signFirebaseToken("u-victim", { ageS: 7200 });
    const linked = await merge("u-thief", oldGuestToken);
    expect(linked.status).toBe(409);
    expect(await errorCode(linked)).toBe("already_registered");
    expect(await sessionOwners()).toEqual([{ user_id: "u-victim", n: 1 }]);
    expect(await board("u-thief")).toEqual([]);
  });

  it("requires the caller to be registered", async () => {
    const res = await call("/v1/me/merge", await signFirebaseToken("u-g3"), { anonymousIdToken: await signFirebaseToken("u-g4") });
    expect(res.status).toBe(403);
  });

  it("treats the caller's own guest token as a registration", async () => {
    const s = await postSession("u-same", session(2));
    const res = await merge("u-same", await signFirebaseToken("u-same"));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ mergedSessions: 0, isAnonymous: false });
    expect((await board("u-same")).find((r) => r.period === "all")!.points).toBe(s.score);
  });

  it("works for a guest that never synced, and carries a guest's shadow ban", async () => {
    expect((await merge("u-a", await signFirebaseToken("u-never"))).status).toBe(200);

    await postSession("u-cheat", session(3));
    await env.DB.prepare("UPDATE users SET shadow_banned = 1 WHERE id = 'u-cheat'").run();
    const res = await merge("u-b", await signFirebaseToken("u-cheat"));
    expect(res.status).toBe(200);
    expect(await env.DB.prepare("SELECT shadow_banned FROM users WHERE id = 'u-b'").first()).toEqual({ shadow_banned: 1 });
    expect(await board("u-b")).toEqual([]);
  });

  it("validates the body", async () => {
    const res = await call("/v1/me/merge", await signFirebaseToken("u-c", { provider: GOOGLE }), { token: "x" });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("validation_error");
  });

  it("uses a constant number of D1 queries however many sessions move", async () => {
    for (let i = 0; i < 8; i++) await storeRow("u-many", { score: 10, receivedAt: Date.now() - i * DAY });
    const { db, counter } = countingDb(env.DB);
    const res = await call("/v1/me/merge", await signFirebaseToken("u-into", { provider: GOOGLE }), {
      anonymousIdToken: await signFirebaseToken("u-many"),
    }, db);
    expect(res.status).toBe(200);
    expect(counter.queries).toBe(8);
  });
});
