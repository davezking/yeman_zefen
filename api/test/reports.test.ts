import { env, exports } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { MAX_REPORTERS, NAME_REPORT_MATCHES, REPORTS_PER_DAY } from "../src/routes/v1/reports";
import { countingDb, installFirebaseJwks, rawRequest, makeArtist, makeTrack, player, removeFirebaseJwks, resetCatalog, signFirebaseToken } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);
beforeEach(async () => {
  await resetCatalog();
  await env.DB.prepare("DELETE FROM clip_report_counts").run();
});

const report = (uid: string, body: unknown) => player(uid, "/v1/reports/clip", { method: "POST", body });

type Item = { entity_id: number; reason: string; status: string; details_json: string };
async function items(): Promise<Item[]> {
  const { results } = await env.DB.prepare(
    "SELECT entity_id, reason, status, details_json FROM review_items ORDER BY id",
  ).all<Item>();
  return results;
}

async function track(status: "approved" | "retired" | "rejected" = "approved") {
  const artist = await makeArtist(`አርቲስት ${crypto.randomUUID()}`);
  return makeTrack(artist.id, { status });
}

describe("POST /v1/reports/clip", () => {
  it("opens one missing_audio item for the track", async () => {
    const t = await track();
    const res = await report("u-1", { trackId: t.id, clipType: "intro", error: "decode_error" });
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ accepted: true });
    const [item, ...rest] = await items();
    expect(rest).toHaveLength(0);
    expect(item).toMatchObject({ entity_id: t.id, reason: "missing_audio", status: "open" });
    const details = JSON.parse(item!.details_json);
    expect(details).toMatchObject({
      source: "player",
      reports: 1,
      reporters: ["u-1"],
      clips: { intro: 1 },
      errors: { decode_error: 1 },
    });
    expect(details.firstReportedAt).toBe(details.lastReportedAt);
  });

  it("gathers later reports of the track in the same open item", async () => {
    const t = await track();
    await report("u-1", { trackId: t.id, clipType: "intro", error: "decode_error" });
    await report("u-2", { trackId: t.id, clipType: "middle", error: "too_short" });
    await report("u-2", { trackId: t.id, clipType: "intro", error: "decode_error" });
    const all = await items();
    expect(all).toHaveLength(1);
    const details = JSON.parse(all[0]!.details_json);
    expect(details).toMatchObject({
      reports: 3,
      clips: { intro: 2, middle: 1 },
      errors: { decode_error: 2, too_short: 1 },
    });
    // u-2 reported twice but is one player.
    expect(details.reporters).toEqual(["u-1", "u-2"]);
    expect(details.firstReportedAt).toBeLessThanOrEqual(details.lastReportedAt);
  });

  it("opens a new item once the old one is resolved, and leaves ingest's items alone", async () => {
    const t = await track();
    await env.DB.prepare(
      "INSERT INTO review_items (entity_type, entity_id, reason, details_json, status) VALUES ('track', ?1, 'missing_audio', '{\"cause\":\"no_source\"}', 'open')",
    ).bind(t.id).run();
    await report("u-1", { trackId: t.id, clipType: "intro", error: "file_missing" });
    await env.DB.prepare("UPDATE review_items SET status = 'resolved' WHERE json_extract(details_json, '$.source') = 'player'").run();
    await report("u-1", { trackId: t.id, clipType: "intro", error: "file_missing" });
    const all = await items();
    expect(all.map((i) => [i.status, JSON.parse(i.details_json).source ?? null, JSON.parse(i.details_json).reports ?? null])).toEqual([
      ["open", null, null],
      ["resolved", "player", 1],
      ["open", "player", 1],
    ]);
  });

  it("accepts a report on an unknown or retired track without opening an item", async () => {
    const retired = await track("retired");
    expect((await report("u-1", { trackId: retired.id, clipType: "intro", error: "decode_error" })).status).toBe(202);
    expect((await report("u-1", { trackId: 999_999, clipType: "intro", error: "decode_error" })).status).toBe(202);
    expect(await items()).toEqual([]);
  });

  it(`keeps at most ${MAX_REPORTERS} distinct reporters on an item`, async () => {
    const t = await track();
    const full = JSON.stringify({
      source: "player", reports: MAX_REPORTERS, reporters: Array.from({ length: MAX_REPORTERS }, (_, i) => `p-${i}`),
      clips: { intro: MAX_REPORTERS }, errors: { decode_error: MAX_REPORTERS }, firstReportedAt: 1, lastReportedAt: 1,
    });
    await env.DB.prepare(
      "INSERT INTO review_items (entity_type, entity_id, reason, details_json, status) VALUES ('track', ?1, 'missing_audio', ?2, 'open')",
    ).bind(t.id, full).run();
    await report("u-late", { trackId: t.id, clipType: "intro", error: "decode_error" });
    const details = JSON.parse((await items())[0]!.details_json);
    expect(details.reporters).toHaveLength(MAX_REPORTERS);
    expect(details.reports).toBe(MAX_REPORTERS + 1);
    expect(details.firstReportedAt).toBe(1);
  });

  it(`allows ${REPORTS_PER_DAY} reports per player per day`, async () => {
    const t = await track();
    for (let i = 0; i < REPORTS_PER_DAY; i++) {
      expect((await report("u-many", { trackId: t.id, clipType: "intro", error: "decode_error" })).status).toBe(202);
    }
    const over = await report("u-many", { trackId: t.id, clipType: "intro", error: "decode_error" });
    expect(over.status).toBe(429);
    expect(await over.json()).toMatchObject({ error: { code: "rate_limited" } });
    // Until the next UTC midnight.
    const retryAfter = Number(over.headers.get("retry-after"));
    expect(retryAfter).toBeGreaterThan(0);
    expect(retryAfter).toBeLessThanOrEqual(86_400);
    // The refused report changed nothing.
    expect(JSON.parse((await items())[0]!.details_json).reports).toBe(REPORTS_PER_DAY);
    // Another player is not limited by it.
    expect((await report("u-other", { trackId: t.id, clipType: "intro", error: "decode_error" })).status).toBe(202);
  });

  it("starts the count over on a new day", async () => {
    const t = await track();
    const yesterday = Math.floor(Date.now() / 86_400_000) - 1;
    await env.DB.prepare("INSERT INTO clip_report_counts (user_id, day, count) VALUES ('u-day', ?1, ?2)")
      .bind(yesterday, REPORTS_PER_DAY)
      .run();
    expect((await report("u-day", { trackId: t.id, clipType: "intro", error: "decode_error" })).status).toBe(202);
    const row = await env.DB.prepare("SELECT day, count FROM clip_report_counts WHERE user_id = 'u-day'").first();
    expect(row).toEqual({ day: yesterday + 1, count: 1 });
  });

  it("rejects a malformed body", async () => {
    for (const body of [
      {},
      { trackId: 1, clipType: "outro", error: "decode_error" },
      { trackId: 1, clipType: "intro", error: "something" },
      { trackId: 0, clipType: "intro", error: "decode_error" },
      { trackId: 1, clipType: "intro", error: "decode_error", extra: true },
    ]) {
      const res = await report("u-bad", body);
      expect(res.status).toBe(400);
      expect(await res.json()).toMatchObject({ error: { code: "validation_error" } });
    }
    // A refused body does not use up the player's reports.
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM clip_report_counts").first("n")).toBe(0);
  });

  it("needs a signed-in player", async () => {
    const res = await exports.default.fetch(
      new Request("https://api.test/v1/reports/clip", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ trackId: 1, clipType: "intro", error: "decode_error" }),
      }),
    );
    expect(res.status).toBe(401);
  });

  it("costs 3 queries", async () => {
    const t = await track();
    const { db, counter } = countingDb(env.DB);
    const token = await signFirebaseToken("u-count");
    const res = await app.fetch(
      new Request("https://api.test/v1/reports/clip", {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({ trackId: t.id, clipType: "middle", error: "file_missing" }),
      }),
      { ...env, DB: db },
    );
    expect(res.status).toBe(202);
    expect(counter.queries).toBe(3);
  });
});

describe("POST /v1/reports/name", () => {
  beforeEach(async () => {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
      env.DB.prepare("DELETE FROM rate_limits"),
    ]);
  });

  type Who = { name: string; anonymous?: boolean; banned?: boolean; deleted?: boolean };
  const user = (id: string, w: Who) =>
    env.DB.prepare(
      "INSERT INTO users (id, display_name, is_anonymous, country, created_at, shadow_banned, deleted_at) VALUES (?1, ?2, ?3, 'ET', 1, ?4, ?5)",
    )
      .bind(id, w.name, w.anonymous ? 1 : 0, w.banned ? 1 : 0, w.deleted ? 5 : null)
      .run();
  const reportName = (uid: string, body: unknown) => player(uid, "/v1/reports/name", { method: "POST", body });

  type NameItem = { entity_ref: string; status: string; details: { displayName: string; reports: number; reporters: string[] } };
  async function nameItems(): Promise<NameItem[]> {
    const { results } = await env.DB.prepare(
      "SELECT entity_ref, status, details_json FROM review_items WHERE reason = 'name_report' AND entity_type = 'user' ORDER BY id",
    ).all<{ entity_ref: string; status: string; details_json: string }>();
    return results.map((r) => ({ entity_ref: r.entity_ref, status: r.status, details: JSON.parse(r.details_json) }));
  }

  it("opens one item per visible player with that name, never the reporter, a guest, or a hidden or deleted player", async () => {
    await user("p1", { name: "Bad Name" });
    await user("p2", { name: "Bad Name" });
    await user("me", { name: "Bad Name" });
    await user("guest", { name: "Bad Name", anonymous: true });
    await user("banned", { name: "Bad Name", banned: true });
    await user("gone", { name: "Bad Name", deleted: true });
    await user("other", { name: "Fine Name" });

    const res = await reportName("me", { displayName: "  Bad   Name " });
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ accepted: true });
    const all = await nameItems();
    expect(all.map((i) => i.entity_ref).sort()).toEqual(["p1", "p2"]);
    expect(all[0]).toMatchObject({ status: "open", details: { displayName: "Bad Name", reports: 1, reporters: ["me"] } });
  });

  it("answers the same when no one has the name", async () => {
    const res = await reportName("me", { displayName: "Nobody" });
    expect(res.status).toBe(202);
    expect(await nameItems()).toEqual([]);
  });

  it("gathers later reports in the open item, counting each reporter once", async () => {
    await user("p1", { name: "Bad Name" });
    await reportName("r1", { displayName: "Bad Name" });
    await reportName("r2", { displayName: "Bad Name" });
    await reportName("r2", { displayName: "Bad Name" });
    const all = await nameItems();
    expect(all).toHaveLength(1);
    expect(all[0]!.details).toMatchObject({ reports: 3, reporters: ["r1", "r2"] });
  });

  it("opens a new item once the last one was closed", async () => {
    await user("p1", { name: "Bad Name" });
    await reportName("r1", { displayName: "Bad Name" });
    await env.DB.prepare("UPDATE review_items SET status = 'dismissed'").run();
    await reportName("r2", { displayName: "Bad Name" });
    expect((await nameItems()).map((i) => i.status)).toEqual(["dismissed", "open"]);
  });

  it(`reports at most ${NAME_REPORT_MATCHES} players at once`, async () => {
    for (let i = 0; i < NAME_REPORT_MATCHES + 2; i++) await user(`p${i}`, { name: "Common" });
    await reportName("r1", { displayName: "Common" });
    expect(await nameItems()).toHaveLength(NAME_REPORT_MATCHES);
  });

  it("rejects a bad body", async () => {
    for (const body of [{}, { displayName: "" }, { displayName: "   " }, { displayName: "x".repeat(25) }, { displayName: "Ok", extra: 1 }]) {
      expect((await reportName("r1", body)).status, JSON.stringify(body)).toBe(400);
    }
  });

  it("needs a signed-in player (a guest is fine)", async () => {
    expect((await rawRequest("/v1/reports/name", { method: "POST", body: JSON.stringify({ displayName: "x" }) })).status).toBe(401);
  });

  it("is rate limited per player", async () => {
    const codes: number[] = [];
    for (let i = 0; i < 6; i++) codes.push((await reportName("r1", { displayName: `Name ${i}` })).status);
    expect(codes).toEqual([202, 202, 202, 202, 202, 429]);
    expect((await reportName("r2", { displayName: "Name" })).status).toBe(202);
  });

  it("costs one statement after the rate limit, however many players match", async () => {
    for (let i = 0; i < NAME_REPORT_MATCHES; i++) await user(`p${i}`, { name: "Common" });
    const { db, counter } = countingDb(env.DB);
    const token = await signFirebaseToken("r1");
    const res = await app.fetch(
      new Request("https://api.test/v1/reports/name", {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({ displayName: "Common" }),
      }),
      { ...env, DB: db },
    );
    expect(res.status).toBe(202);
    // The rate-limit upsert, then the report.
    expect(counter.queries).toBe(2);
  });
});
