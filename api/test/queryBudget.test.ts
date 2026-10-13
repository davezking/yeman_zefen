// Cloudflare's Free plan allows 50 D1 queries per Worker invocation, and every statement in a
// batch() counts. These tests pin the ingest endpoints to a query count that does NOT grow with
// the number of records in the request.
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
