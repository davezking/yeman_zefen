import { env } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { gameSessions, leaderboardEntries, users } from "../src/db/schema";
import { countingDb, installFirebaseJwks, player, removeFirebaseJwks, signFirebaseToken } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);

// Tests share one D1 per file, so each test uses its own uids and these tables are wiped between tests.
beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM leaderboard_entries"),
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

const FIDEL_NAME = "ጥላሁን ገሠሠ";

async function putMe(uid: string, body?: unknown, opts: { provider?: string; cf?: { country: string } } = {}) {
  return player(uid, "/v1/me", { method: "PUT", body: body ?? {}, ...opts });
}

describe("PUT /v1/me", () => {
  it("creates the profile from the token", async () => {
    const res = await putMe("u-new", { displayName: "Dawit" });
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body).toMatchObject({ id: "u-new", displayName: "Dawit", isAnonymous: true, country: null });
    expect(typeof body.createdAt).toBe("number");
    expect(typeof body.lastSeenAt).toBe("number");
  });

  it("accepts an empty body and no body", async () => {
    expect((await putMe("u-empty")).status).toBe(200);
    const bare = await player("u-nobody", "/v1/me", { method: "PUT" });
    expect(bare.status).toBe(200);
  });

  it("saves a Fidel name and reads it back exactly", async () => {
    const put = await putMe("u-fidel", { displayName: FIDEL_NAME });
    expect(((await put.json()) as { displayName: string }).displayName).toBe(FIDEL_NAME);
    const get = await player("u-fidel", "/v1/me");
    expect(((await get.json()) as { displayName: string }).displayName).toBe(FIDEL_NAME);
  });

  it("takes the country from Cloudflare, never from the client", async () => {
    const res = await putMe("u-country", { displayName: "Sara", country: "US" }, { cf: { country: "ET" } });
    // `country` is not a field the client may send.
    expect(res.status).toBe(400);
    const ok = await putMe("u-country", { displayName: "Sara" }, { cf: { country: "ET" } });
    expect(((await ok.json()) as { country: string }).country).toBe("ET");
  });

  it("keeps the stored name and country when a later call omits them", async () => {
    await putMe("u-keep", { displayName: "Meron" }, { cf: { country: "ET" } });
    const again = await putMe("u-keep");
    expect(await again.json()).toMatchObject({ displayName: "Meron", country: "ET" });
  });

  it("changes the name and bumps last_seen_at", async () => {
    const first = (await (await putMe("u-rename", { displayName: "Old Name" })).json()) as { lastSeenAt: number; createdAt: number };
    await new Promise((r) => setTimeout(r, 5));
    const second = (await (await putMe("u-rename", { displayName: "New Name" })).json()) as {
      displayName: string; lastSeenAt: number; createdAt: number;
    };
    expect(second.displayName).toBe("New Name");
    expect(second.lastSeenAt).toBeGreaterThan(first.lastSeenAt);
    expect(second.createdAt).toBe(first.createdAt);
  });

  it("follows the token when a guest links an account (same uid, no longer anonymous)", async () => {
    await putMe("u-link", { displayName: "Guest" });
    const res = await putMe("u-link", undefined, { provider: "google.com" });
    expect(await res.json()).toMatchObject({ isAnonymous: false, displayName: "Guest" });
  });

  it("trims and collapses spaces", async () => {
    const res = await putMe("u-space", { displayName: "  Abebe   Bikila " });
    expect(((await res.json()) as { displayName: string }).displayName).toBe("Abebe Bikila");
  });

  it("requires a token", async () => {
    const res = await (await import("cloudflare:workers")).exports.default.fetch(
      new Request("https://api.test/v1/me", { method: "PUT", body: "{}" }),
    );
    expect(res.status).toBe(401);
  });

  it("rejects the reserved placeholder uid", async () => {
    expect((await putMe("deleted", { displayName: "Nope" })).status).toBe(401);
  });
});

describe("display name validation (400 validation_error)", () => {
  const bad: [string, unknown][] = [
    ["too short", "a"],
    ["blank", "   "],
    ["too long", "x".repeat(25)],
    ["punctuation", "Dawit!"],
    ["an emoji", "Dawit 🎵"],
    ["Ethiopic punctuation", "ዘፈን።"],
    ["a Cyrillic letter", "Дawit"],
    ["not a string", 42],
    ["a blocked word", "Admin"],
    ["a blocked word with spaces and case", "xx A d M i n"],
    ["a blocked word inside a longer name", "megafuckfan"],
    ["a blocked Fidel word", "የማን ዘፈን"],
  ];
  for (const [label, displayName] of bad) {
    it(`rejects ${label}`, async () => {
      const res = await putMe("u-bad", { displayName });
      expect(res.status).toBe(400);
      expect(((await res.json()) as { error: { code: string } }).error.code).toBe("validation_error");
    });
  }

  it("rejects unknown fields", async () => {
    expect((await putMe("u-bad", { displayName: "Dawit", isAnonymous: false })).status).toBe(400);
  });

  it("rejects invalid JSON", async () => {
    const res = await (await import("cloudflare:workers")).exports.default.fetch(
      new Request("https://api.test/v1/me", {
        method: "PUT",
        headers: { authorization: `Bearer ${await signFirebaseToken("u-bad")}`, "content-type": "application/json" },
        body: "{nope",
      }),
    );
    expect(res.status).toBe(400);
  });

  it("accepts the length limits, counted in characters (not bytes)", async () => {
    expect((await putMe("u-len", { displayName: "ዘፈ" })).status).toBe(200);
    expect((await putMe("u-len", { displayName: "ዘ".repeat(24) })).status).toBe(200);
    expect((await putMe("u-len", { displayName: "ዘ".repeat(25) })).status).toBe(400);
  });

  it("accepts digits and mixed scripts", async () => {
    expect((await putMe("u-mix", { displayName: "Dawit 2 ዳዊት" })).status).toBe(200);
  });
});

describe("GET /v1/me", () => {
  it("404 before the first PUT", async () => {
    const res = await player("u-none", "/v1/me");
    expect(res.status).toBe(404);
  });

  it("returns only the caller's profile", async () => {
    await putMe("u-a", { displayName: "Alem" });
    await putMe("u-b", { displayName: "Bezawit" });
    const res = await player("u-a", "/v1/me");
    expect(await res.json()).toMatchObject({ id: "u-a", displayName: "Alem" });
  });
});

let sessionN = 0;
async function addSession(userId: string, score = 100) {
  await db(env).insert(gameSessions).values({
    id: `s-${++sessionN}`, userId, mode: "classic", generationId: 1, receivedAt: Date.now(),
    rounds: 5, score, trackIdsJson: "[1,2,3]", eventsJson: "[]",
  });
}
const sessionsOf = (userId: string) => db(env).select().from(gameSessions).all().then((r) => r.filter((s) => s.userId === userId));
const leaderboardOf = (userId: string) => db(env).select().from(leaderboardEntries).all().then((r) => r.filter((e) => e.userId === userId));

describe("DELETE /v1/me", () => {
  async function seedPlayer(uid: string) {
    expect((await putMe(uid, { displayName: "Test Player" })).status).toBe(200);
    await addSession(uid, 120);
    await addSession(uid, 80);
    await db(env).insert(leaderboardEntries).values([
      { period: "all", generationId: 0, userId: uid, points: 200, updatedAt: Date.now() },
      { period: "2026-W42", generationId: 0, userId: uid, points: 200, updatedAt: Date.now() },
    ]);
  }

  it("removes the user and leaderboard rows, keeps sessions under the placeholder", async () => {
    await seedPlayer("u-del");
    await seedPlayer("u-keep");
    const before = await db(env).select().from(gameSessions).all();

    const res = await player("u-del", "/v1/me", { method: "DELETE" });
    expect(res.status).toBe(204);

    expect(await leaderboardOf("u-del")).toEqual([]);
    expect(await db(env).select().from(users).all().then((r) => r.some((u) => u.id === "u-del"))).toBe(false);
    expect((await sessionsOf("u-del")).length).toBe(0);
    expect((await sessionsOf("deleted")).length).toBe(2);

    // Royalty counts come from session rows: same rows, same tracks, same scores, only the owner changed.
    const after = await db(env).select().from(gameSessions).all();
    expect(after.length).toBe(before.length);
    expect(after.map((s) => [s.id, s.trackIdsJson, s.score]).sort()).toEqual(before.map((s) => [s.id, s.trackIdsJson, s.score]).sort());

    // The other player is untouched.
    expect((await sessionsOf("u-keep")).length).toBe(2);
    expect((await leaderboardOf("u-keep")).length).toBe(2);
    expect((await player("u-keep", "/v1/me")).status).toBe(200);
  });

  it("is gone afterwards and deleting again still succeeds", async () => {
    await seedPlayer("u-twice");
    expect((await player("u-twice", "/v1/me", { method: "DELETE" })).status).toBe(204);
    expect((await player("u-twice", "/v1/me")).status).toBe(404);
    expect((await player("u-twice", "/v1/me", { method: "DELETE" })).status).toBe(204);
  });

  it("works for a player who never called PUT", async () => {
    expect((await player("u-never", "/v1/me", { method: "DELETE" })).status).toBe(204);
  });

  it("never lists the placeholder as a player", async () => {
    const row = await db(env).select().from(users).all().then((r) => r.find((u) => u.id === "deleted"));
    expect(row).toMatchObject({ shadowBanned: true });
  });

  it("uses a fixed number of D1 queries however many sessions the player has", async () => {
    const { default: app } = await import("../src/index");
    const queriesFor = async (uid: string, sessions: number) => {
      await putMe(uid, { displayName: "Many" });
      for (let i = 0; i < sessions; i++) await addSession(uid);
      const { db: counted, counter } = countingDb(env.DB);
      const res = await app.fetch(
        new Request("https://api.test/v1/me", { method: "DELETE", headers: { authorization: `Bearer ${await signFirebaseToken(uid)}` } }),
        { ...env, DB: counted },
      );
      expect(res.status).toBe(204);
      return counter.queries;
    };
    expect(await queriesFor("u-few", 1)).toBe(await queriesFor("u-lots", 40));
  });
});
