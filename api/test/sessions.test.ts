import { env, exports } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import payloadDoc from "../../docs/session-payload.md?raw";
import { isoWeek } from "../src/lib/period";
import { sessionPayloadSchema } from "../src/routes/v1/sessions";
import {
  countingDb,
  installFirebaseJwks,
  makeArtist,
  makeTrack,
  removeFirebaseJwks,
  resetCatalog,
  signFirebaseToken,
} from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);

// Era 3 from the seed (migrations/0001_seed.sql). Era 4 is another one.
const ERA = 3;
const OTHER_ERA = 4;

let artistIds: number[] = [];
/** trackIds[i] is by artistIds[i], in era ERA. */
let trackIds: number[] = [];
let otherEraTrack = 0;
let noEraTrack = 0;

beforeAll(async () => {
  await resetCatalog();
  const artists = await Promise.all(["ሀ", "ለ", "ሐ", "መ", "ሠ"].map((n) => makeArtist(`ድምፃዊ ${n}`)));
  artistIds = artists.map((a) => a.id);
  const tracks = await Promise.all(artistIds.map((id) => makeTrack(id, { generationId: ERA, status: "approved" })));
  trackIds = tracks.map((t) => t.id);
  otherEraTrack = (await makeTrack(artistIds[0]!, { generationId: OTHER_ERA, status: "approved" })).id;
  noEraTrack = (await makeTrack(artistIds[0]!, { generationId: null, status: "approved" })).id;
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM leaderboard_entries"),
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

type Round = {
  trackId: number;
  question: "song" | "artist" | "era";
  optionIds: number[];
  chosenId: number | null;
  responseMs: number;
  hintUsed: boolean;
};

const t = (i: number) => trackIds[i]!;
const a = (i: number) => artistIds[i]!;

/** A correct song round for track i at 2000 ms: 143 points on intro/easy (E1). */
const songRound = (i: number, over: Partial<Round> = {}): Round => ({
  trackId: t(i),
  question: "song",
  optionIds: [t(i), t((i + 1) % 5), t((i + 2) % 5), t((i + 3) % 5)],
  chosenId: t(i),
  responseMs: 2000,
  hintUsed: false,
  ...over,
});

/** A correct artist round for track i at 2000 ms: 143 points on intro/easy. */
const artistRound = (i: number, over: Partial<Round> = {}): Round => ({
  trackId: t(i),
  question: "artist",
  optionIds: [a((i + 1) % 5), a(i), a((i + 2) % 5), a((i + 3) % 5)],
  chosenId: a(i),
  responseMs: 2000,
  hintUsed: false,
  ...over,
});

/**
 * An honest intro/easy session: right song, right artist, a wrong song, a timeout.
 * 143 + 143 + 0 + 0 = 286, with 21 s of responses in a 60 s session.
 */
function honest(over: Record<string, unknown> = {}) {
  const now = Date.now();
  return {
    id: crypto.randomUUID(),
    mode: "intro",
    generationId: 0,
    difficulty: "easy",
    clientStartedAt: now - 60_000,
    clientEndedAt: now - 1000,
    offline: false,
    rounds: [
      songRound(0),
      artistRound(1),
      songRound(2, { chosenId: t(3) }),
      songRound(3, { chosenId: null, responseMs: 15000 }),
    ],
    ads: { interstitialShown: 0, rewardedCompleted: 0 },
    ...over,
  };
}
const HONEST_SCORE = 286;
const HONEST_ROUNDS = [
  { points: 143, correct: true },
  { points: 143, correct: true },
  { points: 0, correct: false },
  { points: 0, correct: false },
];

const REGISTERED = "google.com";

async function post(uid: string, body: unknown, opts: { provider?: string; db?: D1Database } = {}) {
  const token = await signFirebaseToken(uid, { provider: opts.provider });
  const req = new Request("https://api.test/v1/sessions", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  if (!opts.db) return exports.default.fetch(req);
  const { default: app } = await import("../src/index");
  return app.fetch(req, { ...env, DB: opts.db });
}

async function board(uid: string) {
  const { results } = await env.DB.prepare(
    "SELECT period, generation_id, points FROM leaderboard_entries WHERE user_id = ? ORDER BY period, generation_id",
  )
    .bind(uid)
    .all<{ period: string; generation_id: number; points: number }>();
  return results;
}

async function storedSession(id: string) {
  return env.DB.prepare("SELECT * FROM game_sessions WHERE id = ?").bind(id).first<Record<string, unknown>>();
}

async function errorCode(res: Response) {
  return ((await res.json()) as { error: { code: string } }).error.code;
}

describe("POST /v1/sessions: an honest session", () => {
  it("scores it on the server and stores one row", async () => {
    const body = honest();
    const res = await post("u-honest", body, { provider: REGISTERED });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ score: HONEST_SCORE, rounds: HONEST_ROUNDS, flagged: false });

    const row = await storedSession(body.id);
    expect(row).toMatchObject({
      user_id: "u-honest",
      mode: "intro",
      generation_id: 0,
      difficulty: "easy",
      client_started_at: body.clientStartedAt,
      rounds: 4,
      score: HONEST_SCORE,
      offline: 0,
      flagged: 0,
      flag_reason: null,
    });
    expect(JSON.parse(row!.track_ids_json as string)).toEqual([t(0), t(1), t(2), t(3)]);
    const events = JSON.parse(row!.events_json as string);
    expect(events.ads).toEqual({ interstitialShown: 0, rewardedCompleted: 0 });
    expect(events.rounds[1]).toMatchObject({ trackId: t(1), question: "artist", chosenId: a(1), points: 143, correct: true });
  });

  it("adds the score to the all-time and weekly boards for all eras", async () => {
    await post("u-board", honest(), { provider: REGISTERED });
    expect(await board("u-board")).toEqual(
      [
        { period: "all", generation_id: 0, points: HONEST_SCORE },
        { period: isoWeek(Date.now()), generation_id: 0, points: HONEST_SCORE },
      ].sort((x, y) => x.period.localeCompare(y.period)),
    );
  });

  it("also adds it to the session's era boards", async () => {
    await post("u-era", honest({ generationId: ERA }), { provider: REGISTERED });
    const rows = await board("u-era");
    expect(rows).toHaveLength(4);
    expect(rows.map((r) => [r.period, r.generation_id]).sort()).toEqual(
      [["all", 0], ["all", ERA], [isoWeek(Date.now()), 0], [isoWeek(Date.now()), ERA]].sort(),
    );
    expect(rows.every((r) => r.points === HONEST_SCORE)).toBe(true);
  });

  it("accumulates across sessions", async () => {
    await post("u-twice", honest(), { provider: REGISTERED });
    await post("u-twice", honest(), { provider: REGISTERED });
    expect((await board("u-twice")).map((r) => r.points)).toEqual([HONEST_SCORE * 2, HONEST_SCORE * 2]);
  });

  it("puts the session in the week it was received, whatever the device clock says", async () => {
    const now = Date.now();
    await post("u-week", honest({ clientStartedAt: now - 9 * 86_400_000, clientEndedAt: now - 9 * 86_400_000 + 60_000 }), {
      provider: REGISTERED,
    });
    expect((await board("u-week")).map((r) => r.period)).toContain(isoWeek(now));
  });

  it("creates the user row when the player has not called PUT /v1/me", async () => {
    await post("u-fresh", honest(), { provider: REGISTERED });
    const user = await env.DB.prepare("SELECT is_anonymous, last_seen_at FROM users WHERE id = ?").bind("u-fresh").first();
    expect(user).toMatchObject({ is_anonymous: 0 });
  });

  it("scores the middle mode and the hint like the app (E7, E17)", async () => {
    const body = honest({
      mode: "middle",
      difficulty: "hard",
      rounds: [songRound(0, { responseMs: 1000 }), songRound(1, { responseMs: 1000, hintUsed: true })],
    });
    const res = await post("u-middle", body, { provider: REGISTERED });
    expect(await res.json()).toMatchObject({ score: 359 + 180, rounds: [{ points: 359 }, { points: 180 }] });
  });

  it("scores era questions in generation mode against the track's era (E15)", async () => {
    const body = honest({
      mode: "generation",
      rounds: [
        { trackId: t(0), question: "era", optionIds: [1, 2, ERA, 5], chosenId: ERA, responseMs: 3000, hintUsed: false },
        { trackId: otherEraTrack, question: "era", optionIds: [1, 2, ERA, OTHER_ERA], chosenId: ERA, responseMs: 3000, hintUsed: false },
      ],
    });
    const res = await post("u-gen", body, { provider: REGISTERED });
    expect(await res.json()).toEqual({ score: 168, rounds: [{ points: 168, correct: true }, { points: 0, correct: false }], flagged: false });
  });

  it("requires a token", async () => {
    const res = await exports.default.fetch(
      new Request("https://api.test/v1/sessions", { method: "POST", body: JSON.stringify(honest()) }),
    );
    expect(res.status).toBe(401);
  });
});

describe("idempotency", () => {
  it("returns the stored result for a replayed id and never counts it twice", async () => {
    const body = honest();
    const first = await (await post("u-replay", body, { provider: REGISTERED })).json();
    const again = await post("u-replay", body, { provider: REGISTERED });
    expect(again.status).toBe(200);
    expect(await again.json()).toEqual(first);
    expect((await board("u-replay")).map((r) => r.points)).toEqual([HONEST_SCORE, HONEST_SCORE]);
    const { results } = await env.DB.prepare("SELECT id FROM game_sessions WHERE user_id = ?").bind("u-replay").all();
    expect(results).toHaveLength(1);
  });

  it("returns the stored result even when the replay's rounds differ", async () => {
    const body = honest();
    await post("u-replay2", body, { provider: REGISTERED });
    const forged = { ...body, rounds: [songRound(0), songRound(1), songRound(2), songRound(3)] };
    expect(await (await post("u-replay2", forged, { provider: REGISTERED })).json()).toMatchObject({ score: HONEST_SCORE });
    expect((await board("u-replay2")).map((r) => r.points)).toEqual([HONEST_SCORE, HONEST_SCORE]);
  });

  it("treats the id case-insensitively", async () => {
    const body = honest();
    await post("u-case", body, { provider: REGISTERED });
    await post("u-case", { ...body, id: body.id.toUpperCase() }, { provider: REGISTERED });
    expect((await board("u-case")).map((r) => r.points)).toEqual([HONEST_SCORE, HONEST_SCORE]);
  });

  it("does not double-count concurrent uploads of the same session", async () => {
    const body = honest();
    const results = await Promise.all([1, 2, 3].map(() => post("u-race", body, { provider: REGISTERED })));
    for (const res of results) {
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ score: HONEST_SCORE });
    }
    expect((await board("u-race")).map((r) => r.points)).toEqual([HONEST_SCORE, HONEST_SCORE]);
  });

  it("adds nothing when a replay slips past the read (a race with the first upload)", async () => {
    const body = honest();
    const first = await (await post("u-slip", body, { provider: REGISTERED })).json();
    // The first lookup of the stored session misses, as if the other upload committed just after it.
    let hidden = false;
    const racing = {
      prepare: (sql: string) => {
        if (!hidden && sql.includes("FROM game_sessions WHERE id = ?1")) {
          hidden = true;
          return env.DB.prepare(sql.replace("WHERE id = ?1", "WHERE id = ?1 AND 0"));
        }
        return env.DB.prepare(sql);
      },
      batch: (statements: D1PreparedStatement[]) => env.DB.batch(statements),
    } as unknown as D1Database;
    const res = await post("u-slip", body, { provider: REGISTERED, db: racing });
    expect(hidden).toBe(true);
    expect(await res.json()).toEqual(first);
    expect((await board("u-slip")).map((r) => r.points)).toEqual([HONEST_SCORE, HONEST_SCORE]);
  });

  it("returns the stored result to a deleted account retrying its own session", async () => {
    const body = honest();
    const first = await (await post("u-gone-retry", body, { provider: REGISTERED })).json();
    const del = await exports.default.fetch(
      new Request("https://api.test/v1/me", {
        method: "DELETE",
        headers: { authorization: `Bearer ${await signFirebaseToken("u-gone-retry", { provider: REGISTERED })}` },
      }),
    );
    expect(del.status).toBe(204);
    const again = await post("u-gone-retry", body, { provider: REGISTERED });
    expect(again.status).toBe(200);
    expect(await again.json()).toEqual(first);
    expect(await board("u-gone-retry")).toEqual([]);
    expect((await storedSession(body.id))!.user_id).toBe("deleted");
  });

  it("returns 409 for an id another player already used", async () => {
    const body = honest();
    await post("u-owner", body, { provider: REGISTERED });
    const res = await post("u-thief", body, { provider: REGISTERED });
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("session_conflict");
    expect(await board("u-thief")).toEqual([]);
    expect((await storedSession(body.id))!.user_id).toBe("u-owner");
  });
});

describe("forged rounds (422 invalid_session, nothing stored)", () => {
  const forged: [string, () => Round][] = [
    ["a song round whose options do not include the track", () => songRound(0, { optionIds: [t(1), t(2), t(3), t(4)], chosenId: t(1) })],
    ["an unknown track", () => songRound(0, { trackId: 999_999 })],
    ["an unknown track among the options", () => songRound(0, { optionIds: [t(0), t(1), t(2), 999_999] })],
    ["a chosen id that is not an option", () => songRound(0, { chosenId: t(4) })],
    ["an era question outside generation mode", () => ({ trackId: t(0), question: "era", optionIds: [1, 2, ERA, 5], chosenId: ERA, responseMs: 2000, hintUsed: false })],
  ];
  for (const [label, round] of forged) {
    it(`rejects ${label}`, async () => {
      const body = honest({ rounds: [songRound(1), round()] });
      const res = await post("u-forge", body, { provider: REGISTERED });
      expect(res.status).toBe(422);
      expect(await errorCode(res)).toBe("invalid_session");
      expect(await storedSession(body.id)).toBeNull();
      expect(await board("u-forge")).toEqual([]);
    });
  }

  it("rejects song questions in generation mode", async () => {
    const res = await post("u-forge", honest({ mode: "generation", rounds: [songRound(0)] }), { provider: REGISTERED });
    expect(res.status).toBe(422);
  });

  it("rejects an unknown session era", async () => {
    const res = await post("u-forge", honest({ generationId: 999 }), { provider: REGISTERED });
    expect(res.status).toBe(422);
  });
});

describe("payload validation (400 validation_error)", () => {
  it("accepts the example in docs/session-payload.md, which the app's recorder is tested against", () => {
    const blocks = [...payloadDoc.matchAll(/```json\n([\s\S]*?)\n```/g)].map((m) => JSON.parse(m[1]!));
    expect(blocks).toHaveLength(2);
    const parsed = sessionPayloadSchema.safeParse(blocks[1]);
    expect(parsed.error?.issues).toBeUndefined();
    expect(parsed.data!.rounds[1]!.chosenId).toBeNull();
  });

  const bad: [string, () => unknown][] = [
    ["no rounds", () => honest({ rounds: [] })],
    ["51 rounds", () => honest({ rounds: Array.from({ length: 51 }, (_, i) => songRound(i % 5)) })],
    ["3 options", () => honest({ rounds: [songRound(0, { optionIds: [t(0), t(1), t(2)] })] })],
    ["5 options", () => honest({ rounds: [songRound(0, { optionIds: [t(0), t(1), t(2), t(3), t(4)] })] })],
    ["repeated options", () => honest({ rounds: [songRound(0, { optionIds: [t(0), t(1), t(1), t(2)] })] })],
    ["an unknown mode", () => honest({ mode: "blitz" })],
    ["an unknown difficulty", () => honest({ difficulty: "insane" })],
    ["an unknown question kind", () => honest({ rounds: [{ ...songRound(0), question: "album" }] })],
    ["a negative response time", () => honest({ rounds: [songRound(0, { responseMs: -1 })] })],
    ["a fractional response time", () => honest({ rounds: [songRound(0, { responseMs: 1500.5 })] })],
    ["an id that is not a UUID", () => honest({ id: "session-1" })],
    ["a missing ads object", () => ({ ...honest(), ads: undefined })],
    ["a track id sent as a string", () => honest({ rounds: [{ ...songRound(0), trackId: "41" }] })],
  ];
  for (const [label, body] of bad) {
    it(`rejects ${label}`, async () => {
      const res = await post("u-val", body(), { provider: REGISTERED });
      expect(res.status).toBe(400);
      expect(await errorCode(res)).toBe("validation_error");
    });
  }

  it("ignores a score the client sends", async () => {
    const res = await post("u-val", honest({ score: 1_000_000 }), { provider: REGISTERED });
    expect(await res.json()).toMatchObject({ score: HONEST_SCORE });
  });

  it("rejects invalid JSON and an oversized body", async () => {
    expect((await post("u-val", "{nope", { provider: REGISTERED })).status).toBe(400);
    const huge = JSON.stringify({ ...honest(), padding: "x".repeat(40_000) });
    expect((await post("u-val", huge, { provider: REGISTERED })).status).toBe(413);
    // A declared length over the cap is refused before the body is read.
    const token = await signFirebaseToken("u-val", { provider: REGISTERED });
    const declared = await exports.default.fetch(
      new Request("https://api.test/v1/sessions", {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "content-length": "50000000" },
        body: JSON.stringify(honest()),
      }),
    );
    expect(declared.status).toBe(413);
  });
});

describe("sanity bounds (stored, flagged, kept off the leaderboard)", () => {
  async function expectFlagged(uid: string, body: ReturnType<typeof honest>, reason: string) {
    const res = await post(uid, body, { provider: REGISTERED });
    expect(res.status).toBe(200);
    const result = (await res.json()) as { flagged: boolean };
    expect(result.flagged).toBe(true);
    const row = await storedSession(body.id);
    expect(row).toMatchObject({ flagged: 1 });
    expect((row!.flag_reason as string).split(",")).toContain(reason);
    expect(await board(uid)).toEqual([]);
    return result;
  }

  it("flags inhuman response times and scores those rounds 0", async () => {
    const body = honest({ rounds: [songRound(0), songRound(1, { responseMs: 150 }), songRound(2, { responseMs: 199 })] });
    const result = await expectFlagged("u-bot", body, "fast_response");
    expect(result).toEqual({
      score: 143,
      rounds: [{ points: 143, correct: true }, { points: 0, correct: true }, { points: 0, correct: true }],
      flagged: true,
    });
  });

  it("accepts exactly 200 ms", async () => {
    const res = await post("u-fast", honest({ rounds: [songRound(0, { responseMs: 200 })] }), { provider: REGISTERED });
    expect(await res.json()).toEqual({ score: 149, rounds: [{ points: 149, correct: true }], flagged: false });
  });

  it("flags a session whose response times do not fit in its duration", async () => {
    const now = Date.now();
    // 21 s of responses in a 5 s session (more than the 10 s tolerance).
    await expectFlagged("u-time", honest({ clientStartedAt: now - 6000, clientEndedAt: now - 1000 }), "duration_mismatch");
  });

  it("allows 10 s of slack between response times and the duration", async () => {
    const now = Date.now();
    // 21 s of responses in an 11 s session: exactly at the tolerance.
    const res = await post("u-slack", honest({ clientStartedAt: now - 12_000, clientEndedAt: now - 1000 }), { provider: REGISTERED });
    expect(await res.json()).toMatchObject({ flagged: false });
  });

  it("flags a session that ends before it starts", async () => {
    const now = Date.now();
    await expectFlagged("u-backwards", honest({ clientStartedAt: now - 1000, clientEndedAt: now - 120_000 }), "duration_mismatch");
  });

  it("flags a session that started more than 14 days ago", async () => {
    const start = Date.now() - 15 * 86_400_000;
    await expectFlagged("u-old", honest({ clientStartedAt: start, clientEndedAt: start + 60_000 }), "clock_out_of_range");
  });

  it("flags a session from more than 5 minutes in the future", async () => {
    const start = Date.now() + 10 * 60_000;
    await expectFlagged("u-future", honest({ clientStartedAt: start, clientEndedAt: start + 60_000 }), "clock_out_of_range");
  });

  it("flags a correct answer that came after the window closed", async () => {
    // Easy: the window is 15 s; the app ends the round as a timeout, so a tap at 20 s is not from the app.
    await expectFlagged("u-late", honest({ rounds: [songRound(0, { responseMs: 20_000 })] }), "late_answer");
  });

  // Artists can be merged (deleted) and eras changed after a pack shipped, so these are flagged, not rejected.
  it("flags artist options that leave out the track's artist, and scores the round 0", async () => {
    const round = artistRound(0, { optionIds: [a(1), a(2), a(3), a(4)], chosenId: a(1) });
    const result = await expectFlagged("u-merged", honest({ rounds: [songRound(1), round] }), "catalog_mismatch");
    expect(result).toEqual({ score: 143, rounds: [{ points: 143, correct: true }, { points: 0, correct: false }], flagged: true });
  });

  it("flags artist options that are no longer artists", async () => {
    const round = artistRound(0, { optionIds: [a(0), 999_999, a(2), a(3)] });
    await expectFlagged("u-gone", honest({ rounds: [round] }), "catalog_mismatch");
  });

  it("flags an era question about a track that has lost its era", async () => {
    const round = { trackId: noEraTrack, question: "era", optionIds: [1, 2, ERA, 5], chosenId: ERA, responseMs: 2000, hintUsed: false };
    await expectFlagged("u-noera", honest({ mode: "generation", rounds: [round] }), "catalog_mismatch");
  });

  it("flags era options that are not eras", async () => {
    const round = { trackId: t(0), question: "era", optionIds: [1, 2, ERA, 999], chosenId: ERA, responseMs: 2000, hintUsed: false };
    await expectFlagged("u-badera", honest({ mode: "generation", rounds: [round] }), "catalog_mismatch");
  });

  it("flags an era session that plays a track from another era", async () => {
    const round = songRound(0, { trackId: otherEraTrack, optionIds: [otherEraTrack, t(1), t(2), t(3)], chosenId: otherEraTrack });
    await expectFlagged("u-mix", honest({ generationId: ERA, rounds: [round] }), "era_mismatch");
  });
});

describe("who reaches the leaderboard", () => {
  it("stores an anonymous player's session without a leaderboard write", async () => {
    const body = honest();
    const res = await post("u-guest", body); // anonymous by default
    expect(await res.json()).toEqual({ score: HONEST_SCORE, rounds: HONEST_ROUNDS, flagged: false });
    expect(await storedSession(body.id)).toMatchObject({ user_id: "u-guest", score: HONEST_SCORE, flagged: 0 });
    expect(await board("u-guest")).toEqual([]);
    const user = await env.DB.prepare("SELECT is_anonymous FROM users WHERE id = ?").bind("u-guest").first();
    expect(user).toMatchObject({ is_anonymous: 1 });
  });

  it("stores a shadow-banned player's session without a leaderboard write", async () => {
    const now = Date.now();
    await env.DB.prepare("INSERT INTO users (id, is_anonymous, created_at, shadow_banned) VALUES (?, 0, ?, 1)")
      .bind("u-banned", now)
      .run();
    const body = honest();
    const res = await post("u-banned", body, { provider: REGISTERED });
    // The player is not told.
    expect(await res.json()).toEqual({ score: HONEST_SCORE, rounds: HONEST_ROUNDS, flagged: false });
    expect(await storedSession(body.id)).toMatchObject({ score: HONEST_SCORE, flagged: 0 });
    expect(await board("u-banned")).toEqual([]);
  });

  it("does not add a 0-point session", async () => {
    const body = honest({ rounds: [songRound(0, { chosenId: t(1) })] });
    await post("u-zero", body, { provider: REGISTERED });
    expect(await storedSession(body.id)).toMatchObject({ score: 0 });
    expect(await board("u-zero")).toEqual([]);
  });
});

describe("D1 cost", () => {
  async function cost(uid: string, body: unknown) {
    const { db, counter } = countingDb(env.DB);
    const res = await post(uid, body, { provider: REGISTERED, db });
    expect(res.status).toBe(200);
    return counter;
  }

  it("a typical session costs 3 write statements", async () => {
    // 10 rounds in an era: the user touch, one leaderboard upsert (4 rows), the session row.
    const now = Date.now();
    const rounds = Array.from({ length: 10 }, (_, i) => (i % 2 ? artistRound(i % 5) : songRound(i % 5)));
    const counter = await cost("u-cost", honest({ generationId: ERA, rounds, clientStartedAt: now - 120_000 }));
    expect(counter.writes).toBe(3);
    expect(counter.queries).toBe(5); // plus the two reads
    expect(await board("u-cost")).toHaveLength(4);
  });

  it("does not grow with the number of rounds", async () => {
    const now = Date.now();
    const few = await cost("u-few", honest({ rounds: [songRound(0)] }));
    const many = await cost(
      "u-many",
      honest({ rounds: Array.from({ length: 50 }, (_, i) => songRound(i % 5)), clientStartedAt: now - 600_000 }),
    );
    expect(many.queries).toBe(few.queries);
    expect(many.writes).toBe(few.writes);
  });

  it("a replay costs only the reads", async () => {
    const body = honest();
    await post("u-cheap", body, { provider: REGISTERED });
    const counter = await cost("u-cheap", body);
    expect(counter.writes).toBe(0);
    expect(counter.queries).toBe(2);
  });
});
