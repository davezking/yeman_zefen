import { env, exports } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { REPORTS_PER_DAY } from "../src/routes/v1/reports";
import { countingDb, installFirebaseJwks, makeArtist, makeTrack, player, removeFirebaseJwks, resetCatalog, signFirebaseToken } from "./helpers";

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
    expect(JSON.parse(item!.details_json)).toMatchObject({
      source: "player",
      reports: 1,
      clips: { intro: 1 },
      errors: { decode_error: 1 },
    });
  });

  it("gathers later reports of the track in the same open item", async () => {
    const t = await track();
    await report("u-1", { trackId: t.id, clipType: "intro", error: "decode_error" });
    await report("u-2", { trackId: t.id, clipType: "middle", error: "too_short" });
    await report("u-2", { trackId: t.id, clipType: "intro", error: "decode_error" });
    const all = await items();
    expect(all).toHaveLength(1);
    expect(JSON.parse(all[0]!.details_json)).toMatchObject({
      reports: 3,
      clips: { intro: 2, middle: 1 },
      errors: { decode_error: 2, too_short: 1 },
    });
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

  it(`allows ${REPORTS_PER_DAY} reports per player per day`, async () => {
    const t = await track();
    for (let i = 0; i < REPORTS_PER_DAY; i++) {
      expect((await report("u-many", { trackId: t.id, clipType: "intro", error: "decode_error" })).status).toBe(202);
    }
    const over = await report("u-many", { trackId: t.id, clipType: "intro", error: "decode_error" });
    expect(over.status).toBe(429);
    expect(await over.json()).toMatchObject({ error: { code: "rate_limited" } });
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
