import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { artistAliases, artists, clips, ingestJobs, reviewItems, trackGenres, tracks } from "../src/db/schema";
import {
  api,
  installTestJwks,
  makeArtist,
  makeClip,
  makeJob,
  makeTrack,
  rawRequest,
  removeTestJwks,
  resetCatalog,
  seedAdmins,
  signAccessJwt,
  svc,
} from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(resetCatalog);
afterAll(() => removeTestJwks());

const json = async (res: Response) => (await res.json()) as any; // test-only: shapes are asserted below

const scraped = (n: number, extra: Record<string, unknown> = {}) => ({
  sourceUrl: `https://ethiozeima.com/2014/11/02/song-${n}/`,
  titleAm: `ዘፈን ${n}`,
  titleLatin: `Song ${n}`,
  artistAm: "ጥላሁን ገሠሠ",
  artistLatin: "Tilahun Gessesse",
  artistAliases: ["Tilahun G.", "ጥላሁን ገሰሰ"],
  album: "Greatest Hits",
  releaseYear: 1975,
  genres: ["tizita"],
  durationMs: 200_000,
  sourceAudioKey: `source/song-${n}.mp3`,
  flags: [],
  ...extra,
});

const count = async (table: string) =>
  (await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first<{ n: number }>())!.n;

describe("auth", () => {
  const routes = [
    ["POST", "/admin/ingest/tracks"],
    ["POST", "/admin/ingest/clips"],
    ["POST", "/admin/ingest/jobs/1/status"],
    ["GET", "/admin/ingest/catalog-snapshot"],
  ] as const;

  it("401 without a token, 403 for a human admin token", async () => {
    for (const [method, path] of routes) {
      expect((await rawRequest(path, { method })).status, `${method} ${path} no token`).toBe(401);
      const human = await signAccessJwt({ email: "admin@yz.test" });
      expect((await rawRequest(path, { method, jwt: human })).status, `${method} ${path} human`).toBe(403);
    }
  });
});

describe("POST /admin/ingest/tracks", () => {
  it("creates artists, aliases, tracks, genres and review items", async () => {
    const job = await makeJob("scrape");
    const res = await svc("/admin/ingest/tracks", {
      body: {
        jobId: job.id,
        tracks: [
          scraped(1),
          scraped(2, { genres: ["tizita", "pop", "not-a-genre"], flags: [{ reason: "era_unknown", details: { year: null } }] }),
        ],
      },
    });
    expect(res.status).toBe(200);
    const body = await json(res);
    expect(body.counts).toEqual({ created: 2, updated: 0, skipped: 0 });
    expect(body.results.map((r: any) => r.result)).toEqual(["created", "created"]);
    expect(body.results[0].trackId).toBeGreaterThan(0);
    expect(body.results[1].unknownGenres).toEqual(["not-a-genre"]);

    expect(await count("artists")).toBe(1); // one artist shared by both records
    const [artist] = await db(env).select().from(artists);
    expect(artist).toMatchObject({ nameAm: "ጥላሁን ገሠሠ", nameLatin: "Tilahun Gessesse" });

    const aliasNorms = (await db(env).select().from(artistAliases)).map((a) => a.aliasNorm).sort();
    expect(aliasNorms).toEqual(["tilahun g.", "tilahun gessesse", "ጥላሁን ገሠሠ", "ጥላሁን ገሰሰ"].sort());

    const rows = await db(env).select().from(tracks).orderBy(tracks.id);
    expect(rows.map((t) => t.status)).toEqual(["ingested", "needs_review"]); // flags -> needs_review
    expect(rows[0]).toMatchObject({ titleLatin: "Song 1", releaseYear: 1975, durationMs: 200_000, album: "Greatest Hits" });

    expect(await count("track_genres")).toBe(3); // tizita; tizita + pop
    const items = await db(env).select().from(reviewItems);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ entityType: "track", entityId: rows[1]!.id, reason: "era_unknown", status: "open" });
  });

  it("is idempotent: re-sending a batch creates no duplicates", async () => {
    const job = await makeJob("scrape");
    const payload = {
      jobId: job.id,
      tracks: [scraped(1), scraped(2, { flags: [{ reason: "missing_audio", details: { a: 1, b: 2 } }] })],
    };
    await svc("/admin/ingest/tracks", { body: payload });
    const before = { tracks: await count("tracks"), aliases: await count("artist_aliases"), reviews: await count("review_items"), links: await count("track_genres"), artists: await count("artists") };

    const again = await json(await svc("/admin/ingest/tracks", { body: payload }));
    expect(again.counts).toEqual({ created: 0, updated: 0, skipped: 2 });
    expect(again.results.every((r: any) => r.trackId > 0)).toBe(true);
    expect({ tracks: await count("tracks"), aliases: await count("artist_aliases"), reviews: await count("review_items"), links: await count("track_genres"), artists: await count("artists") }).toEqual(before);

    // Same details with keys in a different order are still "identical".
    const reordered = { ...payload, tracks: [scraped(2, { flags: [{ reason: "missing_audio", details: { b: 2, a: 1 } }] })] };
    await svc("/admin/ingest/tracks", { body: reordered });
    expect(await count("review_items")).toBe(before.reviews);
  });

  it("keeps an admin's edit to title_latin across a re-scrape, but still refreshes other fields", async () => {
    const job = await makeJob("scrape");
    const first = await json(await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1)] } }));
    const trackId = first.results[0].trackId;

    const edit = await api(`/admin/tracks/${trackId}`, { method: "PATCH", body: { titleLatin: "Tizita (Admin Fixed)" } });
    expect(edit.status).toBe(200);

    const rescrape = await json(
      await svc("/admin/ingest/tracks", {
        body: { jobId: job.id, tracks: [scraped(1, { titleLatin: "Song 1 (re-scraped)", album: "Remastered", durationMs: 201_000 })] },
      }),
    );
    expect(rescrape.results[0].result).toBe("updated");
    const [row] = await db(env).select().from(tracks).where(eq(tracks.id, trackId));
    expect(row).toMatchObject({ titleLatin: "Tizita (Admin Fixed)", album: "Remastered", durationMs: 201_000 });
    expect(JSON.parse(row!.adminEditedFields)).toEqual(["titleLatin"]);
  });

  it("never nulls out an existing value with a missing one", async () => {
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1)] } });
    const res = await json(
      await svc("/admin/ingest/tracks", {
        body: { jobId: job.id, tracks: [scraped(1, { titleLatin: "", album: null, releaseYear: null, durationMs: null })] },
      }),
    );
    expect(res.results[0].result).toBe("skipped");
    const [row] = await db(env).select().from(tracks);
    expect(row).toMatchObject({ titleLatin: "Song 1", album: "Greatest Hits", releaseYear: 1975, durationMs: 200_000 });
  });

  it("matches an existing artist by alias instead of creating a duplicate", async () => {
    const artist = await makeArtist("ጥላሁን ገሠሠ");
    await db(env).insert(artistAliases).values({ artistId: artist.id, alias: "ጥላሁን ገሰሰ", aliasNorm: "ጥላሁን ገሰሰ" });
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { artistAm: "ጥላሁን ገሰሰ" })] } });
    expect(await count("artists")).toBe(1);
    const [row] = await db(env).select().from(tracks);
    expect(row!.artistId).toBe(artist.id);
    // Latin name was missing on the existing artist, so it is filled in.
    const [a] = await db(env).select().from(artists);
    expect(a!.nameLatin).toBe("Tilahun Gessesse");
  });

  it("adds new flags to an existing track without duplicating open ones, and bumps ingested -> needs_review", async () => {
    const job = await makeJob("scrape");
    const first = await json(await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1)] } }));
    const trackId = first.results[0].trackId;
    expect((await db(env).select().from(tracks))[0]!.status).toBe("ingested");

    const flagged = { jobId: job.id, tracks: [scraped(1, { flags: [{ reason: "short_audio", details: { ms: 4000 } }] })] };
    expect((await json(await svc("/admin/ingest/tracks", { body: flagged }))).results[0].result).toBe("updated");
    expect((await json(await svc("/admin/ingest/tracks", { body: flagged }))).results[0].result).toBe("skipped");
    expect(await count("review_items")).toBe(1);
    expect((await db(env).select().from(tracks).where(eq(tracks.id, trackId)))[0]!.status).toBe("needs_review");

    // A resolved item doesn't block a new identical one (the problem came back).
    await db(env).update(reviewItems).set({ status: "resolved" });
    await svc("/admin/ingest/tracks", { body: flagged });
    expect(await count("review_items")).toBe(2);
  });

  it("handles a full batch of 100 tracks with several flags and genres each", async () => {
    const job = await makeJob("scrape");
    const batch = Array.from({ length: 100 }, (_, i) =>
      scraped(i, {
        artistAm: `አርቲስት ${i % 10}`,
        artistLatin: `Artist ${i % 10}`,
        artistAliases: [`Alias ${i % 10} a`, `Alias ${i % 10} b`],
        genres: ["tizita", "pop", "hip-hop"],
        flags: [
          { reason: "translit_uncertain", details: { i } },
          { reason: "era_unknown", details: null },
          { reason: "missing_audio", details: { i } },
        ],
      }),
    );
    const res = await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: batch } });
    expect(res.status).toBe(200);
    expect((await json(res)).counts).toEqual({ created: 100, updated: 0, skipped: 0 });
    expect(await count("tracks")).toBe(100);
    expect(await count("artists")).toBe(10);
    expect(await count("track_genres")).toBe(300);
    expect(await count("review_items")).toBe(300);

    const again = await json(await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: batch } }));
    expect(again.counts).toEqual({ created: 0, updated: 0, skipped: 100 });
    expect(await count("review_items")).toBe(300);
  });

  it("rejects bad requests without writing anything", async () => {
    const job = await makeJob("scrape");
    const post = (body: unknown) => svc("/admin/ingest/tracks", { body });
    expect((await post({ jobId: job.id, tracks: [] })).status).toBe(400);
    expect((await post({ jobId: job.id, tracks: Array.from({ length: 101 }, (_, i) => scraped(i)) })).status).toBe(400);
    expect((await post({ jobId: job.id, tracks: [scraped(1), scraped(1)] })).status).toBe(400); // duplicate url
    expect((await post({ jobId: job.id, tracks: [scraped(1, { flags: [{ reason: "bogus" }] })] })).status).toBe(400);
    expect((await post({ jobId: job.id, tracks: [scraped(1, { sourceUrl: "not a url" })] })).status).toBe(400);
    expect((await post({ jobId: job.id, tracks: [scraped(1, { surprise: true })] })).status).toBe(400);
    expect((await post({ jobId: 999_999, tracks: [scraped(1)] })).status).toBe(404);
    expect((await post({ jobId: (await makeJob("cut")).id, tracks: [scraped(1)] })).status).toBe(409);
    expect((await post({ jobId: (await makeJob("scrape", "succeeded")).id, tracks: [scraped(1)] })).status).toBe(409);
    expect(await count("tracks")).toBe(0);
    expect(await count("artists")).toBe(0);
  });
});

describe("POST /admin/ingest/clips", () => {
  const sha = (c: string) => c.repeat(64);
  const clipBody = (jobId: number, trackId: number, overrides: Record<string, unknown> = {}) => ({
    jobId,
    clips: [
      { trackId, type: "intro", startMs: 0, lengthMs: 10_000, r2Key: `clips/${trackId}-intro-v1.mp3`, sha256: sha("a"), bytes: 160_000, ...overrides },
      { trackId, type: "middle", startMs: 90_000, lengthMs: 10_000, r2Key: `clips/${trackId}-middle-v1.mp3`, sha256: sha("b"), bytes: 161_000 },
    ],
  });

  it("creates ready clips at version 1, is idempotent, and bumps the version only on change", async () => {
    const track = await makeTrack((await makeArtist("አርቲስት")).id, { status: "needs_review", durationMs: 200_000 });
    const job = await makeJob("cut");

    const first = await json(await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id) }));
    expect(first.counts).toEqual({ created: 2, updated: 0, skipped: 0 });
    expect(first.results.map((r: any) => r.version)).toEqual([1, 1]);
    const rows = await db(env).select().from(clips).where(eq(clips.trackId, track.id));
    expect(rows.map((r) => [r.type, r.status, r.version])).toEqual([["intro", "ready", 1], ["middle", "ready", 1]]);

    const again = await json(await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id) }));
    expect(again.counts).toEqual({ created: 0, updated: 0, skipped: 2 });
    expect(again.results.map((r: any) => r.version)).toEqual([1, 1]);

    const changed = await json(await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id, { startMs: 5000, sha256: sha("c"), r2Key: `clips/${track.id}-intro-v2.mp3` }) }));
    expect(changed.counts).toEqual({ created: 0, updated: 1, skipped: 1 });
    expect(changed.results.map((r: any) => r.version)).toEqual([2, 1]);
    expect(await count("clips")).toBe(2);
  });

  it("re-activates a clip an admin moved (pending) and lets the track be approved", async () => {
    const track = await makeTrack((await makeArtist("አርቲስት")).id, { status: "needs_review", durationMs: 200_000 });
    const job = await makeJob("recut");
    await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id) });
    const intro = (await db(env).select().from(clips).where(eq(clips.trackId, track.id))).find((c) => c.type === "intro")!;

    expect((await api(`/admin/clips/${intro.id}`, { method: "PATCH", body: { start_ms: 12_000 } })).status).toBe(200);
    expect((await api(`/admin/tracks/${track.id}/approve`, { method: "POST" })).status).toBe(409);

    const recut = await json(await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id, { startMs: 12_000, sha256: sha("d") }) }));
    expect(recut.results[0]).toMatchObject({ result: "updated", version: 2 });
    expect((await api(`/admin/tracks/${track.id}/approve`, { method: "POST" })).status).toBe(200);
  });

  it("rejects unknown tracks, duplicates and malformed hashes without writing", async () => {
    const track = await makeTrack((await makeArtist("አርቲስት")).id);
    const job = await makeJob("cut");
    const missing = await svc("/admin/ingest/clips", { body: clipBody(job.id, 999_999) });
    expect(missing.status).toBe(404);
    expect((await json(missing)).error.message).toContain("999999");

    const dup = clipBody(job.id, track.id);
    dup.clips.push(dup.clips[0]!);
    expect((await svc("/admin/ingest/clips", { body: dup })).status).toBe(400);
    expect((await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id, { sha256: "xyz" }) })).status).toBe(400);
    expect((await svc("/admin/ingest/clips", { body: clipBody(job.id, track.id, { type: "outro" }) })).status).toBe(400);
    expect((await svc("/admin/ingest/clips", { body: clipBody((await makeJob("scrape")).id, track.id) })).status).toBe(409);
    expect(await count("clips")).toBe(0);
  });
});

describe("POST /admin/ingest/jobs/:id/status", () => {
  const post = (id: number, body: unknown) => svc(`/admin/ingest/jobs/${id}/status`, { body });

  it("sets started_at on running and finished_at on a terminal status", async () => {
    const job = await makeJob("scrape", "queued");
    expect(job.startedAt).toBeNull();

    const running = (await json(await post(job.id, { status: "running", ghRunUrl: "https://github.com/o/r/actions/runs/1" }))).job;
    expect(running).toMatchObject({ status: "running", ghRunUrl: "https://github.com/o/r/actions/runs/1", finishedAt: null });
    expect(running.startedAt).toBeGreaterThan(0);

    const done = (await json(await post(job.id, { status: "succeeded", summary: { tracks: 12, flagged: 3 } }))).job;
    expect(done.status).toBe("succeeded");
    expect(done.finishedAt).toBeGreaterThanOrEqual(done.startedAt);
    expect(JSON.parse(done.summaryJson)).toEqual({ tracks: 12, flagged: 3 });
    expect(done.startedAt).toBe(running.startedAt); // not overwritten
  });

  it("a job that fails straight from queued still gets both timestamps", async () => {
    const job = await makeJob("scrape", "queued");
    const failed = (await json(await post(job.id, { status: "failed", summary: { error: "boom" } }))).job;
    expect(failed.startedAt).toBeGreaterThan(0);
    expect(failed.finishedAt).toBeGreaterThan(0);
  });

  it("tolerates a retried final report but refuses to move backwards or re-open", async () => {
    const job = await makeJob("scrape", "running");
    expect((await post(job.id, { status: "queued" })).status).toBe(409);
    expect((await post(job.id, { status: "succeeded" })).status).toBe(200);
    expect((await post(job.id, { status: "succeeded" })).status).toBe(200); // retry
    expect((await post(job.id, { status: "failed" })).status).toBe(409);
    expect((await post(job.id, { status: "running" })).status).toBe(409);
  });

  it("validates input and 404s for unknown jobs", async () => {
    const job = await makeJob("scrape");
    expect((await post(job.id, { status: "done" })).status).toBe(400);
    expect((await post(job.id, { status: "running", ghRunUrl: "nope" })).status).toBe(400);
    expect((await post(job.id, { status: "running", extra: 1 })).status).toBe(400);
    expect((await post(999_999, { status: "running" })).status).toBe(404);
    expect((await db(env).select().from(ingestJobs).where(eq(ingestJobs.id, job.id)))[0]!.status).toBe("running");
  });
});

describe("GET /admin/ingest/catalog-snapshot", () => {
  it("returns compact artists (with alias norms) and tracks", async () => {
    const artist = await makeArtist("ጥላሁን ገሠሠ", "Tilahun Gessesse");
    await db(env).insert(artistAliases).values([
      { artistId: artist.id, alias: "Tilahun G", aliasNorm: "tilahun g" },
      { artistId: artist.id, alias: "T. G.", aliasNorm: "t. g." },
    ]);
    const track = await makeTrack(artist.id, { titleAm: "ትዝታ", titleLatin: "Tizita", durationMs: 180_000 });

    const res = await svc("/admin/ingest/catalog-snapshot");
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    const snap = await json(res);
    expect(snap.columns.artists).toEqual(["id", "name_am", "alias_norms"]);
    expect(snap.artists).toEqual([[artist.id, "ጥላሁን ገሠሠ", ["tilahun g", "t. g."]]]);
    expect(snap.tracks).toEqual([[track.id, artist.id, "ትዝታ", "Tizita", 180_000]]);
  });

  it("stays under ~1 MB for 2,000 tracks", async () => {
    await env.DB.batch([
      env.DB.prepare(
        `WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 400)
         INSERT INTO artists (name_am, name_latin, created_at, updated_at)
         SELECT 'አርቲስት ሙሉ ስም ' || i, 'Artist Full Name ' || i, 1, 1 FROM n`,
      ),
      env.DB.prepare(
        `INSERT INTO artist_aliases (artist_id, alias, alias_norm, source)
         SELECT id, 'Artist Full Name ' || id || ' alt', 'artist full name ' || id || ' alt', 'scraper' FROM artists`,
      ),
      env.DB.prepare(
        `WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 2000)
         INSERT INTO tracks (artist_id, title_am, title_latin, duration_ms, status, created_at, updated_at)
         SELECT (SELECT MIN(id) FROM artists) + (i % 400),
                'የዘፈን ርዕስ ረጅም ምሳሌ ' || i, 'A Fairly Long Song Title Example ' || i, 215000, 'approved', 1, 1 FROM n`,
      ),
    ]);
    expect(await count("tracks")).toBe(2000);

    const text = await (await svc("/admin/ingest/catalog-snapshot")).text();
    const bytes = new TextEncoder().encode(text).length;
    expect(JSON.parse(text).tracks).toHaveLength(2000);
    expect(bytes).toBeLessThan(1_000_000);
    console.log(`snapshot for 2000 tracks / 400 artists: ${bytes} bytes`);
  });
});

describe("shared helpers sanity", () => {
  it("makeClip/makeTrack still work with the new unique source_url index", async () => {
    const a = await makeArtist("አርቲስት");
    const t1 = await makeTrack(a.id); // two hand-made tracks, both with NULL source_url
    const t2 = await makeTrack(a.id);
    await makeClip(t1.id, "intro");
    expect(t1.id).not.toBe(t2.id);
    expect(await db(env).select().from(trackGenres)).toHaveLength(0);
  });
});

describe("era assignment on ingest", () => {
  const GOLDEN = 1, EIGHTIES = 2, NINETIES = 3, TWO_THOUSANDS = 4, MODERN = 5;

  const trackByUrl = async (n: number) =>
    (await db(env).select().from(tracks).where(eq(tracks.sourceUrl, scraped(n).sourceUrl)))[0]!;

  it("puts each boundary year in the right generation", async () => {
    const cases: [number, number][] = [
      [1979, GOLDEN], [1980, EIGHTIES], [1989, EIGHTIES], [1990, NINETIES],
      [2009, TWO_THOUSANDS], [2010, MODERN],
    ];
    const job = await makeJob("scrape");
    const res = await json(
      await svc("/admin/ingest/tracks", {
        body: { jobId: job.id, tracks: cases.map(([year], i) => scraped(i + 1, { releaseYear: year })) },
      }),
    );
    expect(res.counts).toEqual({ created: 6, updated: 0, skipped: 0 });
    for (const [i, [, generation]] of cases.entries()) {
      expect((await trackByUrl(i + 1)).generationId, `year ${cases[i]![0]}`).toBe(generation);
    }
    expect(await count("review_items")).toBe(0);
  });

  it("leaves era null, flags era_unknown and sets needs_review when the year is missing", async () => {
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: null })] } });
    const row = await trackByUrl(1);
    expect(row.generationId).toBeNull();
    expect(row.status).toBe("needs_review");
    const items = await db(env).select().from(reviewItems);
    expect(items).toMatchObject([{ entityType: "track", entityId: row.id, reason: "era_unknown", status: "open" }]);
  });

  it("does not add a second era_unknown item when re-sent", async () => {
    const job = await makeJob("scrape");
    const body = { jobId: job.id, tracks: [scraped(1, { releaseYear: null })] };
    await svc("/admin/ingest/tracks", { body });
    const again = await json(await svc("/admin/ingest/tracks", { body }));
    expect(again.results[0].result).toBe("skipped");
    expect(await count("review_items")).toBe(1);
  });

  it("reassigns the era when the year changes on a track that is not overridden", async () => {
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1975 })] } });
    expect((await trackByUrl(1)).generationId).toBe(GOLDEN);
    const res = await json(
      await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1995 })] } }),
    );
    expect(res.results[0].result).toBe("updated");
    expect((await trackByUrl(1)).generationId).toBe(NINETIES);
  });

  it("never reassigns an admin-overridden track", async () => {
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1975 })] } });
    const before = await trackByUrl(1);
    await db(env)
      .update(tracks)
      .set({ generationId: MODERN, generationOverridden: true })
      .where(eq(tracks.id, before.id));

    const res = await json(
      await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1975 })] } }),
    );
    expect(res.results[0].result).toBe("skipped");
    expect((await trackByUrl(1)).generationId).toBe(MODERN);

    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1995 })] } });
    const row = await trackByUrl(1);
    expect(row.generationId).toBe(MODERN);
    expect(row.generationOverridden).toBe(true);
    expect(await count("review_items")).toBe(0);
  });

  it("keeps the stored era when a re-scrape has no year", async () => {
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 2015 })] } });
    const res = await json(
      await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: null })] } }),
    );
    expect(res.results[0].result).toBe("skipped");
    expect((await trackByUrl(1)).generationId).toBe(MODERN);
    expect(await count("review_items")).toBe(0);
  });

  it("derives the era from an admin-edited year, not the rejected scraped one", async () => {
    const job = await makeJob("scrape");
    await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1975 })] } });
    const before = await trackByUrl(1);
    // Admin corrects the year to 1985; the re-scrape's year must no longer touch the era.
    await db(env)
      .update(tracks)
      .set({ releaseYear: 1985, generationId: EIGHTIES, adminEditedFields: JSON.stringify(["releaseYear"]) })
      .where(eq(tracks.id, before.id));

    const res = await json(
      await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [scraped(1, { releaseYear: 1975 })] } }),
    );
    expect(res.results[0].result).toBe("skipped");
    const row = await trackByUrl(1);
    expect(row.releaseYear).toBe(1985);
    expect(row.generationId).toBe(EIGHTIES);
  });
});
