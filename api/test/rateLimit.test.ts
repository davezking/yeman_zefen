import { env, exports } from "cloudflare:workers";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { runScheduled } from "../src/cron/rollups";
import type { AppEnv } from "../src/env";
import { onError } from "../src/lib/errors";
import { UID_RULES, ipRateLimit, takeToken } from "../src/lib/rateLimit";
import { installFirebaseJwks, player, removeFirebaseJwks } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);

const HOUR = 3_600_000;

describe("token bucket (D1)", () => {
  it("lets a full burst through, then refuses with the time until the next token", async () => {
    const t0 = 1_000_000_000_000;
    for (let i = 0; i < UID_RULES.sessions.burst; i++) {
      expect(await takeToken(env.DB, "sessions:bucket-1", UID_RULES.sessions, t0)).toEqual({ allowed: true });
    }
    // 60 an hour is one token a minute.
    expect(await takeToken(env.DB, "sessions:bucket-1", UID_RULES.sessions, t0)).toEqual({
      allowed: false,
      retryAfterS: 60,
    });
    // Half a minute later the wait is shorter, and nothing was spent by the refusals.
    expect(await takeToken(env.DB, "sessions:bucket-1", UID_RULES.sessions, t0 + 30_000)).toEqual({
      allowed: false,
      retryAfterS: 30,
    });
    expect(await takeToken(env.DB, "sessions:bucket-1", UID_RULES.sessions, t0 + 61_000)).toEqual({ allowed: true });
  });

  it("refills to the burst size and no further", async () => {
    const t0 = 2_000_000_000_000;
    for (let i = 0; i < 5; i++) await takeToken(env.DB, "merge:bucket-2", UID_RULES.merge, t0);
    expect((await takeToken(env.DB, "merge:bucket-2", UID_RULES.merge, t0)).allowed).toBe(false);
    // Days later the bucket is full (5), not 5 * days.
    const later = t0 + 3 * 24 * HOUR;
    for (let i = 0; i < 5; i++) expect((await takeToken(env.DB, "merge:bucket-2", UID_RULES.merge, later)).allowed).toBe(true);
    expect((await takeToken(env.DB, "merge:bucket-2", UID_RULES.merge, later)).allowed).toBe(false);
  });

  it("keeps a bucket per key", async () => {
    const t0 = 3_000_000_000_000;
    for (let i = 0; i < 5; i++) await takeToken(env.DB, "merge:bucket-3a", UID_RULES.merge, t0);
    expect((await takeToken(env.DB, "merge:bucket-3a", UID_RULES.merge, t0)).allowed).toBe(false);
    expect((await takeToken(env.DB, "merge:bucket-3b", UID_RULES.merge, t0)).allowed).toBe(true);
  });

  it("does not let a clock that went back refill or break the bucket", async () => {
    const t0 = 4_000_000_000_000;
    for (let i = 0; i < 5; i++) await takeToken(env.DB, "merge:bucket-4", UID_RULES.merge, t0);
    expect((await takeToken(env.DB, "merge:bucket-4", UID_RULES.merge, t0 - HOUR)).allowed).toBe(false);
  });
});

describe("per-player limits on /v1", () => {
  it("accepts 15 queued sessions at once (a reconnecting player)", async () => {
    // The limit is checked before the body, so an empty body is a 400, never a 429.
    for (let i = 0; i < 15; i++) {
      expect((await player("burst-player", "/v1/sessions", { method: "POST", body: {} })).status).toBe(400);
    }
  });

  it("answers a loop of 100 session posts with 429 and Retry-After once the burst is spent", async () => {
    const statuses: number[] = [];
    let last: Response | undefined;
    for (let i = 0; i < 100; i++) {
      last = await player("loop-player", "/v1/sessions", { method: "POST", body: {} });
      statuses.push(last.status);
    }
    expect(statuses.filter((s) => s === 400)).toHaveLength(UID_RULES.sessions.burst);
    expect(statuses.filter((s) => s === 429)).toHaveLength(100 - UID_RULES.sessions.burst);
    expect(statuses.slice(0, UID_RULES.sessions.burst).every((s) => s === 400)).toBe(true);
    expect(last!.status).toBe(429);
    expect(Number(last!.headers.get("retry-after"))).toBeGreaterThan(0);
    expect(await last!.json()).toMatchObject({ error: { code: "rate_limited" } });
  });

  it("limits merge to 5, and one player's limit never touches another", async () => {
    const send = (uid: string) => player(uid, "/v1/me/merge", { method: "POST", body: {}, provider: "google.com" });
    for (let i = 0; i < 5; i++) expect((await send("merge-a")).status).not.toBe(429);
    const refused = await send("merge-a");
    expect(refused.status).toBe(429);
    expect(Number(refused.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await send("merge-b")).status).not.toBe(429);
  });

  it("limits PUT /v1/me to 30 but leaves GET /v1/me alone", async () => {
    for (let i = 0; i < 30; i++) expect((await player("me-a", "/v1/me", { body: {} })).status).toBe(200);
    expect((await player("me-a", "/v1/me", { body: {} })).status).toBe(429);
    expect((await player("me-a", "/v1/me")).status).toBe(200);
  });

  it("does not count a request with a bad token", async () => {
    const before = await env.DB.prepare("SELECT COUNT(*) AS n FROM rate_limits").first<{ n: number }>();
    const res = await exports.default.fetch(
      new Request("https://api.test/v1/sessions", { method: "POST", headers: { authorization: "Bearer nope" } }),
    );
    expect(res.status).toBe(401);
    const after = await env.DB.prepare("SELECT COUNT(*) AS n FROM rate_limits").first<{ n: number }>();
    expect(after!.n).toBe(before!.n);
  });
});

describe("per-IP limit (fake binding)", () => {
  function appWith(limiter: RateLimit | undefined) {
    const app = new Hono<AppEnv>();
    app.onError(onError);
    app.use("*", ipRateLimit());
    app.get("/x", (c) => c.json({ ok: true }));
    return (ip?: string) =>
      app.request("/x", { headers: ip ? { "cf-connecting-ip": ip } : {} }, { ...env, IP_LIMITER: limiter });
  }

  /** Lets `limit` calls per key through, like the real binding within one period. */
  function fakeLimiter(limit: number) {
    const seen = new Map<string, number>();
    const limiter: RateLimit = {
      limit: async ({ key }) => {
        const n = (seen.get(key) ?? 0) + 1;
        seen.set(key, n);
        return { success: n <= limit };
      },
    };
    return { limiter, seen };
  }

  it("answers 429 with Retry-After once an IP is over its limit", async () => {
    const { limiter } = fakeLimiter(3);
    const get = appWith(limiter);
    for (let i = 0; i < 3; i++) expect((await get("203.0.113.9")).status).toBe(200);
    const refused = await get("203.0.113.9");
    expect(refused.status).toBe(429);
    expect(refused.headers.get("retry-after")).toBe("60");
    expect(await refused.json()).toMatchObject({ error: { code: "rate_limited" } });
    expect((await get("203.0.113.10")).status).toBe(200);
  });

  it("keys the limit on the connecting IP", async () => {
    const { limiter, seen } = fakeLimiter(10);
    await appWith(limiter)("198.51.100.7");
    expect([...seen.keys()]).toEqual(["198.51.100.7"]);
  });

  it("is skipped without the binding or without an IP", async () => {
    expect((await appWith(undefined)("203.0.113.9")).status).toBe(200);
    const { limiter, seen } = fakeLimiter(0);
    expect((await appWith(limiter)()).status).toBe(200);
    expect(seen.size).toBe(0);
  });
});

describe("nightly prune", () => {
  it("drops buckets idle for a day and keeps recent ones", async () => {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO rate_limits (key, tokens, updated_at, allowed) VALUES ('me:old', 1, ?1, 1)").bind(now - 2 * 24 * HOUR),
      env.DB.prepare("INSERT INTO rate_limits (key, tokens, updated_at, allowed) VALUES ('me:new', 1, ?1, 1)").bind(now - HOUR),
    ]);
    await runScheduled(env, now);
    const { results } = await env.DB.prepare("SELECT key FROM rate_limits WHERE key IN ('me:old', 'me:new')").all<{ key: string }>();
    expect(results.map((r) => r.key)).toEqual(["me:new"]);
  });
});
