// Cloudflare's Free plan allows 50 D1 queries per Worker invocation, and every statement in a
// batch() counts. These tests pin the ingest endpoints to a query count that does NOT grow with
// the number of records in the request.
import { env } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { makeArtist, makeJob, makeTrack, installTestJwks, removeTestJwks, resetCatalog, seedAdmins, svcWithQueryCount } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(resetCatalog);
afterAll(() => removeTestJwks());

const FREE_PLAN_LIMIT = 50;
const BUDGET = 30; // leaves headroom under the Free limit

/** Worst case per record: its own new artist, aliases, 3 genres, 3 flags. */
const record = (n: number, extra: Record<string, unknown> = {}) => ({
  sourceUrl: `https://ethiozeima.com/2014/11/02/song-${n}/`,
  titleAm: `ዘፈን ${n}`,
  titleLatin: `Song ${n}`,
  artistAm: `አርቲስት ${n}`,
  artistLatin: `Artist ${n}`,
  artistAliases: [`Alias ${n} a`, `Alias ${n} b`, `Alias ${n} c`],
  album: "Album",
  releaseYear: 1975,
  genres: ["tizita", "pop", "hip-hop"],
  durationMs: 200_000,
  sourceAudioKey: `source/${n}.mp3`,
  flags: [
    { reason: "translit_uncertain", details: { n } },
    { reason: "era_unknown", details: null },
    { reason: "missing_audio", details: { n } },
  ],
  ...extra,
});

const batch = (size: number, start = 0, extra: Record<string, unknown> = {}) =>
  Array.from({ length: size }, (_, i) => record(start + i, extra));

describe("POST /admin/ingest/tracks stays within the Free plan's query cap", () => {
  it("uses a constant number of queries for 10 or 100 brand-new records", async () => {
    const job = await makeJob("scrape");
    const small = await svcWithQueryCount("/admin/ingest/tracks", { jobId: job.id, tracks: batch(10, 0) });
    expect(small.response.status).toBe(200);
    const large = await svcWithQueryCount("/admin/ingest/tracks", { jobId: job.id, tracks: batch(100, 1000) });
    expect(large.response.status).toBe(200);

    expect(large.queries).toBeLessThanOrEqual(BUDGET);
    expect(large.queries).toBeLessThan(FREE_PLAN_LIMIT);
    expect(large.queries - small.queries).toBeLessThanOrEqual(2); // constant, not proportional
  });

  it("stays constant when re-sending (all skipped) and when re-scraping with changes (all updated)", async () => {
    const job = await makeJob("scrape");
    await svcWithQueryCount("/admin/ingest/tracks", { jobId: job.id, tracks: batch(100) });

    const same = await svcWithQueryCount("/admin/ingest/tracks", { jobId: job.id, tracks: batch(100) });
    expect(same.response.status).toBe(200);
    expect((await same.response.json() as any).counts).toEqual({ created: 0, updated: 0, skipped: 100 });
    expect(same.queries).toBeLessThanOrEqual(BUDGET);

    const changed = await svcWithQueryCount("/admin/ingest/tracks", { jobId: job.id, tracks: batch(100, 0, { album: "Remastered" }) });
    expect((await changed.response.json() as any).counts).toEqual({ created: 0, updated: 100, skipped: 0 });
    expect(changed.queries).toBeLessThanOrEqual(BUDGET);
  });

  it("handles a mix of existing and new artists without extra queries", async () => {
    for (let i = 0; i < 50; i++) await makeArtist(`አርቲስት ${i}`);
    const job = await makeJob("scrape");
    const { response, queries } = await svcWithQueryCount("/admin/ingest/tracks", { jobId: job.id, tracks: batch(100) });
    expect(response.status).toBe(200);
    expect(queries).toBeLessThanOrEqual(BUDGET);
  });
});

describe("POST /admin/ingest/clips stays within the cap", () => {
  it("uses a constant number of queries for 100 clips", async () => {
    const artist = await makeArtist("አርቲስት");
    const trackIds: number[] = [];
    for (let i = 0; i < 50; i++) trackIds.push((await makeTrack(artist.id)).id);
    const clips = trackIds.flatMap((trackId) =>
      (["intro", "middle"] as const).map((type, k) => ({
        trackId, type, startMs: k * 60_000, lengthMs: 10_000, r2Key: `clips/${trackId}-${type}.mp3`, sha256: "a".repeat(64), bytes: 160_000,
      })),
    );
    const job = await makeJob("cut");
    const first = await svcWithQueryCount("/admin/ingest/clips", { jobId: job.id, clips });
    expect(first.response.status).toBe(200);
    expect((await first.response.json() as any).counts).toEqual({ created: 100, updated: 0, skipped: 0 });
    expect(first.queries).toBeLessThanOrEqual(12);

    const again = await svcWithQueryCount("/admin/ingest/clips", { jobId: job.id, clips });
    expect((await again.response.json() as any).counts).toEqual({ created: 0, updated: 0, skipped: 100 });
    expect(again.queries).toBeLessThanOrEqual(12);
  });
});

describe("clip flags and GET /admin/ingest/clip-targets stay within the cap", () => {
  const seedTracks = async (n: number) => {
    const artist = await makeArtist("አርቲስት");
    const ids: number[] = [];
    for (let i = 0; i < n; i++) ids.push((await makeTrack(artist.id, { sourceAudioKey: `source/${i}.mp3`, status: "needs_review" })).id);
    return ids;
  };

  it("100 flags on 100 tracks cost the same as a handful", async () => {
    const ids = await seedTracks(100);
    const job = await makeJob("cut");
    const flags = (n: number, reason: string) => ids.slice(0, n).map((trackId) => ({ trackId, reason, details: { trackId } }));

    const few = await svcWithQueryCount("/admin/ingest/clips", { jobId: job.id, flags: flags(3, "short_audio") });
    const many = await svcWithQueryCount("/admin/ingest/clips", { jobId: job.id, flags: flags(100, "missing_audio") });
    expect(few.response.status).toBe(200);
    expect(many.response.status).toBe(200);
    expect(many.queries).toBe(few.queries);
    expect(many.queries).toBeLessThanOrEqual(12);

    const again = await svcWithQueryCount("/admin/ingest/clips", { jobId: job.id, flags: flags(100, "missing_audio") }); // all skipped
    expect(again.queries).toBeLessThanOrEqual(many.queries);
  });

  it("100 clips and 100 flags in one request stay constant too", async () => {
    const ids = await seedTracks(100);
    const job = await makeJob("cut");
    const clips = ids.map((trackId) => ({ trackId, type: "intro", startMs: 0, lengthMs: 10_000, r2Key: `clips/${trackId}/intro-v1.mp3`, sha256: "a".repeat(64), bytes: 160_000 }));
    const flags = ids.map((trackId) => ({ trackId, reason: "short_audio", details: { trackId } }));
    const res = await svcWithQueryCount("/admin/ingest/clips", { jobId: job.id, clips, flags });
    expect(res.response.status).toBe(200);
    expect(res.queries).toBe(8);
  });

  it("listing 10 or 100 tracks (with clips) takes the same two queries", async () => {
    const ids = await seedTracks(100);
    const small = await svcWithQueryCount(`/admin/ingest/clip-targets?trackIds=${ids.slice(0, 10).join(",")}`);
    const large = await svcWithQueryCount(`/admin/ingest/clip-targets?trackIds=${ids.join(",")}`);
    const missing = await svcWithQueryCount("/admin/ingest/clip-targets?missing=1&limit=100");
    for (const r of [small, large, missing]) expect(r.response.status).toBe(200);
    expect((await large.response.json() as any).tracks).toHaveLength(100);
    expect(small.queries).toBe(2);
    expect(large.queries).toBe(2);
    expect(missing.queries).toBe(2);
  });
});

// Rows read also count against the daily quota, so per-entity lookups must use an index instead of
// scanning every open review item.
describe("review item lookups use the entity index", () => {
  const plan = async (sql: string) =>
    (await env.DB.prepare(`EXPLAIN QUERY PLAN ${sql}`).all<{ detail: string }>()).results.map((r) => r.detail).join(" | ");

  it("de-duplication check and a track's open items", async () => {
    const dedupe = await plan(
      `SELECT 1 FROM review_items r WHERE r.entity_type = 'track' AND r.entity_id = 5 AND r.status = 'open' AND r.reason = 'era_unknown' AND r.details_json IS NULL`,
    );
    expect(dedupe).toMatch(/review_items_entity_idx/);
    const forTrack = await plan(`SELECT * FROM review_items WHERE entity_type = 'track' AND entity_id = 5 AND status = 'open'`);
    expect(forTrack).toMatch(/review_items_entity_idx/);
  });
});
