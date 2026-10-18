import { env } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { isoWeek } from "../src/lib/period";
import { leaderboardCacheRequest } from "../src/routes/v1/leaderboard";
import { adminWithQueryCount, api, installFirebaseJwks, installTestJwks, player, rawRequest, removeFirebaseJwks, removeTestJwks, seedAdmins } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await installFirebaseJwks();
  await seedAdmins();
});
afterAll(() => {
  removeTestJwks();
  removeFirebaseJwks();
});

const RECEIVED = Date.parse("2026-10-14T10:00:00Z");
const WEEK = isoWeek(RECEIVED);
const NOTE = "checked the rounds by hand";

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM moderation_log"),
    env.DB.prepare("DELETE FROM review_items"),
    env.DB.prepare("DELETE FROM leaderboard_entries"),
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

const user = (id: string, o: { banned?: boolean; name?: string } = {}) =>
  env.DB.prepare("INSERT INTO users (id, display_name, is_anonymous, country, created_at, shadow_banned) VALUES (?1, ?2, 0, 'ET', 1, ?3)")
    .bind(id, o.name ?? id, o.banned ? 1 : 0)
    .run();

type Session = { id: string; userId: string; score?: number; flagged?: boolean; reason?: string | null; gen?: number; at?: number; rounds?: unknown[] };
const session = (s: Session) =>
  env.DB.prepare(
    `INSERT INTO game_sessions (id, user_id, mode, difficulty, generation_id, received_at, rounds, score, track_ids_json, events_json, flagged, flag_reason)
     VALUES (?1, ?2, 'song', 'easy', ?3, ?4, ?5, ?6, '[]', ?7, ?8, ?9)`,
  )
    .bind(
      s.id, s.userId, s.gen ?? 0, s.at ?? RECEIVED, (s.rounds ?? []).length, s.score ?? 100,
      JSON.stringify({ rounds: s.rounds ?? [] }), s.flagged ? 1 : 0, s.flagged ? (s.reason ?? "fast_response") : null,
    )
    .run();

const board = (userId: string, period: string, gen = 0, points = 500) =>
  env.DB.prepare("INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at) VALUES (?1, ?2, ?3, ?4, 1000)")
    .bind(period, gen, userId, points)
    .run();

const points = async (userId: string) =>
  (await env.DB.prepare("SELECT period, generation_id AS gen, points FROM leaderboard_entries WHERE user_id = ?1 ORDER BY period, gen").bind(userId).all<{ period: string; gen: number; points: number }>()).results;

const logRows = async () =>
  (await env.DB.prepare("SELECT admin_email, action, user_id, session_id, review_item_id, note FROM moderation_log ORDER BY id").all<Record<string, unknown>>()).results;

const flag = async (userId: string) =>
  (await env.DB.prepare(
    `INSERT INTO review_items (entity_type, entity_id, entity_ref, reason, details_json, status)
     VALUES ('user', 0, ?1, 'score_anomaly', '{"days":{"2026-10-14":{"rules":["bot_regularity"]}}}', 'open') RETURNING id`,
  ).bind(userId).first<{ id: number }>())!.id;

const post = (path: string, body: unknown, as: "admin" | "editor" = "admin") => api(path, { body, as });

describe("access", () => {
  it("is for the admin role only", async () => {
    await user("u1");
    for (const [method, path, body] of [
      ["GET", "/admin/moderation/queue", undefined],
      ["GET", "/admin/moderation/users/u1", undefined],
      ["POST", "/admin/users/u1/shadow-ban", { banned: true, note: NOTE }],
      ["POST", "/admin/sessions/s1/void", { note: NOTE }],
      ["POST", "/admin/sessions/s1/dismiss", { note: NOTE }],
      ["POST", "/admin/moderation/flags/1/dismiss", { note: NOTE }],
    ] as const) {
      const res = await api(path, { method, body, as: "editor" });
      expect(res.status, `${method} ${path}`).toBe(403);
      expect((await rawRequest(path, { method })).status, `${method} ${path} unauthenticated`).toBe(401);
    }
    expect(await logRows()).toEqual([]);
  });
});

describe("GET /admin/moderation/queue", () => {
  it("lists open anomaly flags and flagged sessions nobody has closed", async () => {
    await user("u1", { name: "Abebe" });
    await user("u2", { banned: true });
    const flagId = await flag("u1");
    const closed = await flag("u2");
    await env.DB.prepare("UPDATE review_items SET status = 'dismissed' WHERE id = ?1").bind(closed).run();
    await session({ id: "new", userId: "u1", flagged: true, at: RECEIVED + 10, reason: "late_answer" });
    await session({ id: "old", userId: "u2", flagged: true, at: RECEIVED });
    await session({ id: "clean", userId: "u1" });
    await session({ id: "done", userId: "u1", flagged: true });
    expect((await post("/admin/sessions/done/dismiss", { note: NOTE })).status).toBe(200);

    const body = (await (await api("/admin/moderation/queue")).json()) as {
      anomalies: { id: number; userId: string; displayName: string; shadowBanned: boolean; details: { days: unknown } }[];
      sessions: { id: string; flagReason: string; shadowBanned: boolean; score: number }[];
      anomaliesMore: boolean;
      sessionsMore: boolean;
    };
    expect(body.anomalies).toHaveLength(1);
    expect(body.anomalies[0]).toMatchObject({ id: flagId, userId: "u1", displayName: "Abebe", shadowBanned: false });
    expect(body.anomalies[0]!.details.days).toBeDefined();
    expect(body.sessions.map((s) => s.id)).toEqual(["new", "old"]);
    expect(body.sessions[0]).toMatchObject({ flagReason: "late_answer", shadowBanned: false });
    expect(body.sessions[1]!.shadowBanned).toBe(true);
    expect(body.anomaliesMore || body.sessionsMore).toBe(false);
  });

  it("drops a session once it is voided", async () => {
    await user("u1");
    await session({ id: "s1", userId: "u1", flagged: true });
    await post("/admin/sessions/s1/void", { note: NOTE });
    const body = (await (await api("/admin/moderation/queue")).json()) as { sessions: unknown[] };
    expect(body.sessions).toEqual([]);
  });
});

describe("GET /admin/moderation/users/:id", () => {
  it("returns the profile, recent sessions with their rounds, flags, points and the log", async () => {
    await user("u1", { name: "Abebe" });
    await board("u1", "all", 0, 700);
    await board("u1", WEEK, 0, 300);
    await board("u1", "all", 2, 50);
    const rounds = [
      { trackId: 7, question: "song", optionIds: [1, 2, 3, 7], chosenId: 7, responseMs: 1200, hintUsed: false, points: 140, correct: true, valid: true },
      { trackId: 8, question: "artist", optionIds: [1, 2, 3, 4], chosenId: null, responseMs: 5000, hintUsed: true, points: 0, correct: false, valid: true },
    ];
    await session({ id: "s1", userId: "u1", rounds, score: 140 });
    await session({ id: "s2", userId: "u1", at: RECEIVED + 5, flagged: true });
    await env.DB.prepare("UPDATE game_sessions SET events_json = 'not json' WHERE id = 's2'").run();
    const flagId = await flag("u1");
    await post("/admin/users/u1/shadow-ban", { banned: true, note: NOTE });

    const res = await api("/admin/moderation/users/u1");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any; // eslint-disable-line @typescript-eslint/no-explicit-any -- test reads a loosely typed body
    expect(body.user).toMatchObject({ id: "u1", displayName: "Abebe", shadowBanned: true, isAnonymous: false, country: "ET" });
    expect(body.points.all).toBe(700);
    expect(body.points.week).toBe(body.points.weekPeriod === WEEK ? 300 : 0);
    expect(body.sessions.map((s: { id: string }) => s.id)).toEqual(["s2", "s1"]);
    expect(body.sessions[0]).toMatchObject({ flagged: true, roundDetails: [] });
    expect(body.sessions[1].roundDetails).toEqual([
      { trackId: 7, question: "song", correct: true, valid: true, responseMs: 1200, hintUsed: false, points: 140 },
      { trackId: 8, question: "artist", correct: false, valid: true, responseMs: 5000, hintUsed: true, points: 0 },
    ]);
    expect(body.sessions[1].eventsJson).toBeUndefined();
    expect(body.flags).toHaveLength(1);
    expect(body.flags[0]).toMatchObject({ id: flagId, status: "open" });
    expect(body.log).toHaveLength(1);
    expect(body.log[0]).toMatchObject({ adminEmail: "admin@yz.test", action: "shadow_ban", note: NOTE });
  });

  it("answers 404 for an unknown player", async () => {
    const res = await api("/admin/moderation/users/nobody");
    expect(res.status).toBe(404);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("not_found");
  });
});

describe("POST /admin/users/:id/shadow-ban", () => {
  it("bans, logs who and why, and leaves the points alone", async () => {
    await user("u1");
    await board("u1", "all", 0, 800);
    const res = await post("/admin/users/u1/shadow-ban", { banned: true, note: `  ${NOTE}  ` });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ userId: "u1", shadowBanned: true, changed: true });
    expect((await env.DB.prepare("SELECT shadow_banned AS b FROM users WHERE id = 'u1'").first<{ b: number }>())!.b).toBe(1);
    expect(await points("u1")).toEqual([{ period: "all", gen: 0, points: 800 }]);
    expect(await logRows()).toEqual([
      { admin_email: "admin@yz.test", action: "shadow_ban", user_id: "u1", session_id: null, review_item_id: null, note: NOTE },
    ]);
  });

  it("unbanning keeps every point and is logged as an unban", async () => {
    await user("u1", { banned: true });
    await board("u1", "all", 0, 800);
    await board("u1", WEEK, 0, 120);
    const res = await post("/admin/users/u1/shadow-ban", { banned: false, note: "appeal upheld" });
    expect(await res.json()).toMatchObject({ shadowBanned: false, changed: true });
    expect(await points("u1")).toEqual([{ period: WEEK, gen: 0, points: 120 }, { period: "all", gen: 0, points: 800 }].sort((a, b) => a.period.localeCompare(b.period)));
    expect((await logRows()).map((r) => r.action)).toEqual(["shadow_unban"]);
  });

  it("is idempotent: banning a banned player changes and logs nothing", async () => {
    await user("u1");
    await post("/admin/users/u1/shadow-ban", { banned: true, note: NOTE });
    const again = await post("/admin/users/u1/shadow-ban", { banned: true, note: "again" });
    expect(await again.json()).toMatchObject({ shadowBanned: true, changed: false });
    expect(await logRows()).toHaveLength(1);
  });

  it("resolves the anomaly flag it answers, and only that player's open flag", async () => {
    await user("u1");
    await user("u2");
    const mine = await flag("u1");
    const theirs = await flag("u2");
    const res = await post("/admin/users/u1/shadow-ban", { banned: true, note: NOTE, reviewItemId: theirs });
    expect(res.status).toBe(200);
    const status = async (id: number) => (await env.DB.prepare("SELECT status, resolved_by AS by FROM review_items WHERE id = ?1").bind(id).first<{ status: string; by: string | null }>())!;
    expect((await status(theirs)).status).toBe("open");
    expect((await status(mine)).status).toBe("open");

    await post("/admin/users/u1/shadow-ban", { banned: false, note: "undo" });
    await post("/admin/users/u1/shadow-ban", { banned: true, note: NOTE, reviewItemId: mine });
    expect(await status(mine)).toEqual({ status: "resolved", by: "admin@yz.test" });
    expect((await logRows()).at(-1)).toMatchObject({ action: "shadow_ban", review_item_id: mine });
  });

  it("requires a note, and rejects unknown fields and bad values", async () => {
    await user("u1");
    for (const body of [{ banned: true }, { banned: true, note: "   " }, { banned: true, note: "x".repeat(501) }, { banned: "yes", note: NOTE }, { banned: true, note: NOTE, extra: 1 }]) {
      expect((await post("/admin/users/u1/shadow-ban", body)).status, JSON.stringify(body).slice(0, 60)).toBe(400);
    }
    expect((await env.DB.prepare("SELECT shadow_banned AS b FROM users WHERE id = 'u1'").first<{ b: number }>())!.b).toBe(0);
    expect(await logRows()).toEqual([]);
  });

  it("answers 404 for an unknown player", async () => {
    expect((await post("/admin/users/nobody/shadow-ban", { banned: true, note: NOTE })).status).toBe(404);
    expect(await logRows()).toEqual([]);
  });

  it("drops the player from the public top 100 once the 60 s cache lapses", async () => {
    await user("hidden", { name: "Hidden" });
    await user("shown", { name: "Shown" });
    await board("hidden", "all", 0, 900);
    await board("shown", "all", 0, 100);
    const key = leaderboardCacheRequest("https://api.test", "all", 0);
    await caches.default.delete(key);
    const names = async () => ((await (await player("g", "/v1/leaderboard")).json()) as { entries: { displayName: string }[] }).entries.map((e) => e.displayName);

    expect(await names()).toEqual(["Hidden", "Shown"]);
    let cached = await caches.default.match(key);
    for (let i = 0; i < 50 && !cached; i++) {
      await new Promise((r) => setTimeout(r, 10));
      cached = await caches.default.match(key);
    }
    expect(cached?.headers.get("cache-control")).toBe("public, max-age=60");

    await post("/admin/users/hidden/shadow-ban", { banned: true, note: NOTE });
    await caches.default.delete(key); // what the 60 s expiry does
    expect(await names()).toEqual(["Shown"]);
  });
});

describe("POST /admin/sessions/:id/void", () => {
  it("takes the score off every row the session was added to, and logs it", async () => {
    await user("u1");
    for (const [period, gen] of [["all", 0], ["all", 3], [WEEK, 0], [WEEK, 3], ["all", 5]] as const) await board("u1", period, gen, 500);
    await session({ id: "s1", userId: "u1", score: 120, gen: 3 });

    const res = await post("/admin/sessions/s1/void", { note: NOTE });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ sessionId: "s1", voided: true, pointsRemoved: 120 });
    const rows = await points("u1");
    const at = (period: string, gen: number) => rows.find((r) => r.period === period && r.gen === gen)!.points;
    expect([at("all", 0), at("all", 3), at(WEEK, 0), at(WEEK, 3)]).toEqual([380, 380, 380, 380]);
    expect(at("all", 5)).toBe(500); // another era is not touched
    const stored = await env.DB.prepare("SELECT flagged, flag_reason AS reason FROM game_sessions WHERE id = 's1'").first<{ flagged: number; reason: string }>();
    expect(stored).toEqual({ flagged: 1, reason: "voided" });
    expect(await logRows()).toEqual([
      { admin_email: "admin@yz.test", action: "void_session", user_id: "u1", session_id: "s1", review_item_id: null, note: NOTE },
    ]);
  });

  it("voiding twice subtracts only once and logs only once", async () => {
    await user("u1");
    await board("u1", "all", 0, 500);
    await board("u1", WEEK, 0, 500);
    await session({ id: "s1", userId: "u1", score: 100 });

    const first = await post("/admin/sessions/s1/void", { note: NOTE });
    const second = await post("/admin/sessions/s1/void", { note: "second try" });
    expect(await first.json()).toMatchObject({ voided: true, pointsRemoved: 100 });
    expect(second.status).toBe(200);
    expect(await second.json()).toEqual({ sessionId: "s1", voided: false, pointsRemoved: 0 });
    expect((await points("u1")).map((r) => r.points)).toEqual([400, 400]);
    expect(await logRows()).toHaveLength(1);
    expect((await logRows())[0]!.note).toBe(NOTE);
  });

  it("two voids at once subtract once", async () => {
    await user("u1");
    await board("u1", "all", 0, 500);
    await session({ id: "s1", userId: "u1", score: 100 });
    const results = await Promise.all([post("/admin/sessions/s1/void", { note: "a" }), post("/admin/sessions/s1/void", { note: "b" })]);
    expect(results.map((r) => r.status)).toEqual([200, 200]);
    expect((await points("u1")).map((r) => r.points)).toEqual([400]);
    expect(await logRows()).toHaveLength(1);
  });

  it("never takes a row below zero", async () => {
    await user("u1");
    await board("u1", "all", 0, 30);
    await session({ id: "s1", userId: "u1", score: 100 });
    await post("/admin/sessions/s1/void", { note: NOTE });
    expect((await points("u1")).map((r) => r.points)).toEqual([0]);
  });

  it("takes nothing back for a session that was flagged when played, but still closes it", async () => {
    await user("u1");
    await board("u1", "all", 0, 500);
    await session({ id: "s1", userId: "u1", score: 100, flagged: true, reason: "late_answer" });
    const res = await post("/admin/sessions/s1/void", { note: NOTE });
    expect(await res.json()).toEqual({ sessionId: "s1", voided: true, pointsRemoved: 0 });
    expect((await points("u1")).map((r) => r.points)).toEqual([500]);
    expect((await env.DB.prepare("SELECT flag_reason AS r FROM game_sessions WHERE id = 's1'").first<{ r: string }>())!.r).toBe("late_answer,voided");
    const queue = (await (await api("/admin/moderation/queue")).json()) as { sessions: unknown[] };
    expect(queue.sessions).toEqual([]);
  });

  it("can void a session after dismissing it", async () => {
    await user("u1");
    await session({ id: "s1", userId: "u1", flagged: true });
    await post("/admin/sessions/s1/dismiss", { note: "looked fine" });
    expect((await post("/admin/sessions/s1/void", { note: "changed my mind" })).status).toBe(200);
    expect((await logRows()).map((r) => r.action)).toEqual(["dismiss_session", "void_session"]);
  });

  it("requires a note and a known session", async () => {
    await user("u1");
    await board("u1", "all", 0, 500);
    await session({ id: "s1", userId: "u1" });
    expect((await post("/admin/sessions/s1/void", {})).status).toBe(400);
    expect((await post("/admin/sessions/s1/void", { note: " " })).status).toBe(400);
    expect((await post("/admin/sessions/nope/void", { note: NOTE })).status).toBe(404);
    expect((await points("u1")).map((r) => r.points)).toEqual([500]);
    expect(await logRows()).toEqual([]);
  });
});

describe("dismissing", () => {
  it("dismisses a flagged session once, keeping its score off the boards", async () => {
    await user("u1");
    await board("u1", "all", 0, 500);
    await session({ id: "s1", userId: "u1", flagged: true });
    const res = await post("/admin/sessions/s1/dismiss", { note: "device clock was off" });
    expect(await res.json()).toEqual({ sessionId: "s1", dismissed: true });
    expect(await (await post("/admin/sessions/s1/dismiss", { note: "again" })).json()).toEqual({ sessionId: "s1", dismissed: false });
    expect((await points("u1")).map((r) => r.points)).toEqual([500]);
    expect(await logRows()).toEqual([
      { admin_email: "admin@yz.test", action: "dismiss_session", user_id: "u1", session_id: "s1", review_item_id: null, note: "device clock was off" },
    ]);
  });

  it("refuses a session that is not flagged or was voided, and an unknown one", async () => {
    await user("u1");
    await session({ id: "clean", userId: "u1" });
    await session({ id: "bad", userId: "u1", flagged: true });
    await post("/admin/sessions/bad/void", { note: NOTE });
    const code = async (id: string, note = NOTE) => {
      const res = await post(`/admin/sessions/${id}/dismiss`, { note });
      return [res.status, ((await res.json()) as { error?: { code: string } }).error?.code];
    };
    expect(await code("clean")).toEqual([409, "not_flagged"]);
    expect(await code("bad")).toEqual([409, "already_voided"]);
    expect(await code("nope")).toEqual([404, "not_found"]);
    expect(await code("bad", " ")).toEqual([400, "validation_error"]);
  });

  it("dismisses an anomaly flag with a note, once", async () => {
    await user("u1");
    const id = await flag("u1");
    const res = await post(`/admin/moderation/flags/${id}/dismiss`, { note: "just a fast player" });
    expect(await res.json()).toEqual({ id, status: "dismissed" });
    expect(await env.DB.prepare("SELECT status, resolved_by AS by FROM review_items WHERE id = ?1").bind(id).first()).toEqual({ status: "dismissed", by: "admin@yz.test" });
    expect(await logRows()).toEqual([
      { admin_email: "admin@yz.test", action: "dismiss_flag", user_id: "u1", session_id: null, review_item_id: id, note: "just a fast player" },
    ]);

    const again = await post(`/admin/moderation/flags/${id}/dismiss`, { note: NOTE });
    expect(again.status).toBe(409);
    expect(((await again.json()) as { error: { code: string } }).error.code).toBe("already_closed");
    expect(await logRows()).toHaveLength(1);
  });

  it("requires a note, and only dismisses anomaly flags", async () => {
    await user("u1");
    const id = await flag("u1");
    expect((await post(`/admin/moderation/flags/${id}/dismiss`, {})).status).toBe(400);
    expect((await post("/admin/moderation/flags/9999/dismiss", { note: NOTE })).status).toBe(404);
    const track = await env.DB.prepare(
      `INSERT INTO review_items (entity_type, entity_id, reason, status) VALUES ('track', 1, 'era_unknown', 'open') RETURNING id`,
    ).first<{ id: number }>();
    expect((await post(`/admin/moderation/flags/${track!.id}/dismiss`, { note: NOTE })).status).toBe(404);
    expect(await logRows()).toEqual([]);
  });

  it("the track review routes cannot close an anomaly flag without a note and a log entry", async () => {
    await user("u1");
    const id = await flag("u1");
    for (const action of ["dismiss", "resolve"]) {
      expect((await api(`/admin/review-items/${id}/${action}`, { method: "POST" })).status).toBe(404);
    }
    expect((await env.DB.prepare("SELECT status FROM review_items WHERE id = ?1").bind(id).first<{ status: string }>())!.status).toBe("open");
  });
});

describe("query budget", () => {
  // The Free plan allows 50 D1 queries per request and a request's count must not grow with the data.
  it("each endpoint uses a fixed number of queries however many flags, sessions and rounds there are", async () => {
    await user("u1");
    const rounds = Array.from({ length: 50 }, (_, i) => ({ trackId: i + 1, question: "song", correct: true, valid: true, responseMs: 1000, hintUsed: false, points: 100 }));
    for (let i = 0; i < 30; i++) await session({ id: `s${i}`, userId: "u1", flagged: true, at: RECEIVED + i, rounds });
    for (let i = 0; i < 30; i++) await user(`f${i}`);
    for (let i = 0; i < 30; i++) await flag(`f${i}`);
    await board("u1", "all", 0, 5000);
    await board("u1", WEEK, 0, 5000);

    const queue = await adminWithQueryCount("/admin/moderation/queue");
    const detail = await adminWithQueryCount("/admin/moderation/users/u1");
    const ban = await adminWithQueryCount("/admin/users/u1/shadow-ban", { body: { banned: true, note: NOTE } });
    const voided = await adminWithQueryCount("/admin/sessions/s1/void", { body: { note: NOTE } });
    const dismissed = await adminWithQueryCount("/admin/sessions/s2/dismiss", { body: { note: NOTE } });
    for (const r of [queue, detail, ban, voided, dismissed]) expect(r.response.status).toBe(200);
    // The admin check is one query; the rest is the endpoint's own.
    expect([queue.queries, detail.queries, ban.queries, voided.queries, dismissed.queries]).toEqual([3, 6, 4, 5, 3]);
  });
});
