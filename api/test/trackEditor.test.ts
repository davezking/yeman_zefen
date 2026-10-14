// The API the admin track table and editor depend on: list extras, genres, artist creation,
// closing review items, the era/genre lookups and the dev-only CDN stand-in.
import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { artistAliases, artists, reviewItems, trackGenres, tracks } from "../src/db/schema";
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

const json = async (res: Response) => (await res.json()) as any; // test-only: response shapes are asserted below

async function genreIdsBySlug(): Promise<Record<string, number>> {
  const rows = (await env.DB.prepare("SELECT id, slug FROM genres").all<{ id: number; slug: string }>()).results;
  return Object.fromEntries(rows.map((r) => [r.slug, r.id]));
}

describe("lookups", () => {
  it("lists eras in order and genres by name", async () => {
    const gens = (await json(await api("/admin/generations"))).items;
    expect(gens.length).toBeGreaterThan(1);
    expect(gens.map((g: any) => g.sort)).toEqual([...gens.map((g: any) => g.sort)].sort((a: number, b: number) => a - b));
    expect(gens[0]).toHaveProperty("nameAm");
    const genres = (await json(await api("/admin/genres"))).items;
    expect(genres.map((g: any) => g.slug)).toContain("tizita");
  });
});

describe("GET /admin/tracks extras", () => {
  it("reports each clip's status, the open flag count, and filters by genre", async () => {
    const artist = await makeArtist("አርቲስት");
    const ids = await genreIdsBySlug();
    const a = await makeTrack(artist.id, { titleAm: "አንድ" });
    const b = await makeTrack(artist.id, { titleAm: "ሁለት" });
    await makeClip(a.id, "intro", "ready");
    await makeClip(a.id, "middle", "pending");
    await db(env).insert(reviewItems).values([
      { entityType: "track", entityId: a.id, reason: "era_unknown", status: "open" },
      { entityType: "track", entityId: a.id, reason: "short_audio", status: "open" },
      { entityType: "track", entityId: a.id, reason: "missing_audio", status: "resolved" },
      { entityType: "artist", entityId: a.id, reason: "possible_duplicate", status: "open" },
    ]);
    await db(env).insert(trackGenres).values({ trackId: a.id, genreId: ids.tizita! });

    const { items } = await json(await api("/admin/tracks"));
    const rowA = items.find((r: any) => r.id === a.id);
    const rowB = items.find((r: any) => r.id === b.id);
    expect(rowA).toMatchObject({ introStatus: "ready", middleStatus: "pending", openFlagCount: 2 });
    expect(rowB).toMatchObject({ introStatus: null, middleStatus: null, openFlagCount: 0 });

    const byGenre = await json(await api(`/admin/tracks?genreId=${ids.tizita}`));
    expect(byGenre.items.map((r: any) => r.id)).toEqual([a.id]);
    expect((await api("/admin/tracks?genreId=abc")).status).toBe(400);
  });
});

describe("track detail and genre edits", () => {
  it("returns genre ids and a URL only for ready clips", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    await makeClip(t.id, "intro", "ready");
    await makeClip(t.id, "middle", "pending");
    const body = await json(await api(`/admin/tracks/${t.id}`));
    expect(body.genreIds).toEqual([]);
    expect(body.clips[0].url).toBe(`${env.CDN_BASE_URL}/clips/${t.id}-intro.mp3`);
    expect(body.clips[1].url).toBeNull();
  });

  it("replaces the genre set, ignores duplicates, and can clear it", async () => {
    const ids = await genreIdsBySlug();
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);

    let res = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { genreIds: [ids.tizita, ids.pop, ids.tizita] } });
    expect(res.status).toBe(200);
    expect((await json(res)).genreIds).toEqual([ids.tizita, ids.pop].sort((x, y) => x! - y!));

    res = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { genreIds: [ids.pop] } });
    expect((await json(res)).genreIds).toEqual([ids.pop]);

    res = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { genreIds: [] } });
    expect((await json(res)).genreIds).toEqual([]);
    const row = (await db(env).select().from(tracks).where(eq(tracks.id, t.id)).get())!;
    expect(JSON.parse(row.adminEditedFields)).toContain("genres");
  });

  it("rejects an unknown genre without changing anything, and too many genres", async () => {
    const ids = await genreIdsBySlug();
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { titleAm: "ቀድሞ" });
    await db(env).insert(trackGenres).values({ trackId: t.id, genreId: ids.tizita! });

    const res = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { titleAm: "አዲስ", genreIds: [ids.pop, 99999] } });
    expect(res.status).toBe(404);
    const after = await json(await api(`/admin/tracks/${t.id}`));
    expect(after.track.titleAm).toBe("ቀድሞ");
    expect(after.genreIds).toEqual([ids.tizita]);

    const many = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { genreIds: Array.from({ length: 11 }, (_, i) => i + 1) } });
    expect(many.status).toBe(400);
  });

  it("stores a Fidel title exactly as typed", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    // Homophones (ሀ/ሐ/ኀ, ሰ/ሠ) must survive: normalization is for matching only, never for display text.
    const title = "ሐሰት ሠላም ኅብረት";
    const res = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { titleAm: title } });
    expect((await json(res)).track.titleAm).toBe(title);
    expect((await json(await api(`/admin/tracks/${t.id}`))).track.titleAm).toBe(title);
  });

  it("a re-scrape does not bring back a genre an admin removed", async () => {
    const ids = await genreIdsBySlug();
    const record = {
      sourceUrl: "https://ethiozeima.com/2014/11/02/song-1/",
      titleAm: "ዘፈን",
      titleLatin: "Song",
      artistAm: "ጥላሁን ገሠሠ",
      artistLatin: "Tilahun Gessesse",
      artistAliases: [],
      album: "Hits",
      releaseYear: 1975,
      genres: ["tizita", "pop"],
      durationMs: 200_000,
      sourceAudioKey: "source/song-1.mp3",
      flags: [],
    };
    const job = await makeJob("scrape");
    expect((await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [record] } })).status).toBe(200);
    const track = (await db(env).select().from(tracks).get())!;
    expect((await json(await api(`/admin/tracks/${track.id}`))).genreIds.sort()).toEqual([ids.tizita, ids.pop].sort());

    await api(`/admin/tracks/${track.id}`, { method: "PATCH", body: { genreIds: [ids.pop] } });
    // The same record again: the removed genre stays removed, and the run reports nothing changed.
    const again = await json(await svc("/admin/ingest/tracks", { body: { jobId: job.id, tracks: [record] } }));
    expect(again.results[0].result).toBe("skipped");
    expect((await json(await api(`/admin/tracks/${track.id}`))).genreIds).toEqual([ids.pop]);
  });
});

describe("era follows the release year unless pinned", () => {
  const openEraItems = async (trackId: number) =>
    (await json(await api(`/admin/tracks/${trackId}`))).openReviewItems.filter((r: any) => r.reason === "era_unknown");

  it("clearing a pinned era re-derives it from the year", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { releaseYear: 1985, generationId: 4, generationOverridden: true });
    const body = await json(await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { generationId: null } }));
    expect(body.track).toMatchObject({ generationId: 2, generationOverridden: false }); // 1985 is the 1980s
  });

  it("changing the year moves an unpinned era, but not a pinned one", async () => {
    const artist = await makeArtist("አርቲስት");
    const free = await makeTrack(artist.id, { releaseYear: 1985, generationId: 2 });
    const pinned = await makeTrack(artist.id, { releaseYear: 1985, generationId: 2, generationOverridden: true });
    expect((await json(await api(`/admin/tracks/${free.id}`, { method: "PATCH", body: { releaseYear: 1995 } }))).track.generationId).toBe(3);
    expect((await json(await api(`/admin/tracks/${pinned.id}`, { method: "PATCH", body: { releaseYear: 1995 } }))).track).toMatchObject({
      generationId: 2,
      generationOverridden: true,
    });
  });

  it("no year means no era: flags era_unknown once and sends a clean track to review", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { releaseYear: 1985, generationId: 2, status: "ingested" });
    const body = await json(await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { releaseYear: null } }));
    expect(body.track).toMatchObject({ generationId: null, status: "needs_review" });
    expect(await openEraItems(t.id)).toHaveLength(1);
    await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { generationId: null } });
    expect(await openEraItems(t.id)).toHaveLength(1); // not duplicated
  });

  it("an edit that makes the era known resolves the open era_unknown item", async () => {
    const artist = await makeArtist("አርቲስት");
    const byYear = await makeTrack(artist.id, { status: "needs_review" });
    const byPick = await makeTrack(artist.id, { status: "needs_review" });
    await db(env).insert(reviewItems).values([
      { entityType: "track", entityId: byYear.id, reason: "era_unknown", status: "open" },
      { entityType: "track", entityId: byPick.id, reason: "era_unknown", status: "open" },
    ]);
    await api(`/admin/tracks/${byYear.id}`, { method: "PATCH", body: { releaseYear: 2003 }, as: "editor" });
    await api(`/admin/tracks/${byPick.id}`, { method: "PATCH", body: { generationId: 1 } });
    expect(await openEraItems(byYear.id)).toEqual([]);
    expect(await openEraItems(byPick.id)).toEqual([]);
    const closed = await db(env).select().from(reviewItems).where(eq(reviewItems.entityId, byYear.id)).get();
    expect(closed).toMatchObject({ status: "resolved", resolvedBy: "editor@yz.test" });
  });

  it("other edits leave the era and its review items alone", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { status: "needs_review" });
    await db(env).insert(reviewItems).values({ entityType: "track", entityId: t.id, reason: "era_unknown", status: "open" });
    await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { titleAm: "አዲስ" } });
    expect(await openEraItems(t.id)).toHaveLength(1);
  });
});

describe("POST /admin/artists", () => {
  it("creates an artist with a canonical alias", async () => {
    const res = await api("/admin/artists", { body: { nameAm: "  ጥላሁን   ገሠሠ ", nameLatin: "Tilahun Gessesse" } });
    expect(res.status).toBe(201);
    const { artist } = await json(res);
    expect(artist).toMatchObject({ nameAm: "ጥላሁን ገሠሠ", nameLatin: "Tilahun Gessesse" });
    const aliases = await db(env).select().from(artistAliases).where(eq(artistAliases.artistId, artist.id));
    expect(aliases.map((a) => a.source)).toEqual(["canonical"]);
  });

  it("points at the existing artist when a spelling folds to a known name", async () => {
    const first = await json(await api("/admin/artists", { body: { nameAm: "ጥላሁን ገሠሠ" } }));
    const dup = await api("/admin/artists", { body: { nameAm: "ጥላሁን ገሰሰ" } }); // ሠ and ሰ are homophones
    expect(dup.status).toBe(409);
    const err = (await json(dup)).error;
    expect(err.code).toBe("artist_exists");
    expect(err.message).toContain(`id ${first.artist.id}`);
    expect(await db(env).select().from(artists)).toHaveLength(1);
  });

  it("409s name_taken for an exact name that has no alias row, and validates input", async () => {
    await makeArtist("ድምጻዊ"); // no canonical alias, as for rows created before aliases existed
    const res = await api("/admin/artists", { body: { nameAm: "ድምጻዊ" } });
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("name_taken");
    expect((await api("/admin/artists", { body: { nameAm: "   " } })).status).toBe(400);
    expect((await api("/admin/artists", { body: { nameAm: "ሀ", extra: 1 } })).status).toBe(400);
  });

  it("of two homophone spellings created at the same moment, exactly one wins", async () => {
    const [a, b] = await Promise.all([
      api("/admin/artists", { body: { nameAm: "ጥላሁን ገሠሠ" } }),
      api("/admin/artists", { body: { nameAm: "ጥላሁን ገሰሰ" } }),
    ]);
    expect([a.status, b.status].sort()).toEqual([201, 409]);
    const rows = await db(env).select().from(artists);
    expect(rows).toHaveLength(1);
    const aliases = await db(env).select().from(artistAliases).where(eq(artistAliases.artistId, rows[0]!.id));
    expect(aliases.map((x) => x.source)).toEqual(["canonical"]);
  });

  it("is open to editors", async () => {
    expect((await api("/admin/artists", { as: "editor", body: { nameAm: "አዲስ ድምጻዊ" } })).status).toBe(201);
  });
});

describe("review items: resolve and dismiss", () => {
  async function openItem() {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    const [item] = await db(env).insert(reviewItems).values({ entityType: "track", entityId: t.id, reason: "era_unknown", status: "open" }).returning();
    return { track: t, item: item! };
  }

  it("resolves an item, recording who and when, and removes it from the track's open items", async () => {
    const { track, item } = await openItem();
    const res = await api(`/admin/review-items/${item.id}/resolve`, { method: "POST", as: "editor" });
    expect(res.status).toBe(200);
    const body = await json(res);
    expect(body.item).toMatchObject({ id: item.id, status: "resolved", resolvedBy: "editor@yz.test" });
    expect(body.item.resolvedAt).toBeGreaterThan(0);
    expect((await json(await api(`/admin/tracks/${track.id}`))).openReviewItems).toEqual([]);
  });

  it("dismisses an item", async () => {
    const { item } = await openItem();
    const body = await json(await api(`/admin/review-items/${item.id}/dismiss`, { method: "POST" }));
    expect(body.item).toMatchObject({ status: "dismissed", resolvedBy: "admin@yz.test" });
  });

  it("409s when an item is already closed, 404s for a missing one, 400s for a bad id", async () => {
    const { item } = await openItem();
    await api(`/admin/review-items/${item.id}/resolve`, { method: "POST" });
    const again = await api(`/admin/review-items/${item.id}/dismiss`, { method: "POST" });
    expect(again.status).toBe(409);
    expect((await json(again)).error.code).toBe("already_closed");
    // The first close stands.
    expect((await db(env).select().from(reviewItems).where(eq(reviewItems.id, item.id)).get())!.status).toBe("resolved");
    expect((await api("/admin/review-items/999999/resolve", { method: "POST" })).status).toBe(404);
    expect((await api("/admin/review-items/abc/resolve", { method: "POST" })).status).toBe(400);
  });
});

describe("auth", () => {
  it("the new routes require an admin", async () => {
    for (const [method, path] of [
      ["GET", "/admin/generations"],
      ["GET", "/admin/genres"],
      ["POST", "/admin/artists"],
      ["POST", "/admin/review-items/1/resolve"],
      ["POST", "/admin/review-items/1/dismiss"],
    ] as const) {
      expect((await rawRequest(path, { method })).status, `${method} ${path}`).toBe(401);
    }
    // A service token is not a human admin.
    const jwt = await signAccessJwt({ common_name: "test-service.client" });
    expect((await rawRequest("/admin/genres", { jwt })).status).toBe(403);
  });
});

describe("dev CDN stand-in", () => {
  const key = "clips/7/intro-v1.mp3";
  beforeEach(async () => {
    await env.CLIPS.put(key, new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]), { httpMetadata: { contentType: "audio/mpeg" } });
  });

  it("serves a clip whole, and a byte range as 206", async () => {
    const whole = await rawRequest(`/cdn/${key}`);
    expect(whole.status).toBe(200);
    expect(whole.headers.get("content-type")).toBe("audio/mpeg");
    expect(whole.headers.get("accept-ranges")).toBe("bytes");
    expect(new Uint8Array(await whole.arrayBuffer())).toHaveLength(10);

    const part = await rawRequest(`/cdn/${key}`, { headers: { range: "bytes=2-5" } });
    expect(part.status).toBe(206);
    expect(part.headers.get("content-range")).toBe("bytes 2-5/10");
    expect([...new Uint8Array(await part.arrayBuffer())]).toEqual([2, 3, 4, 5]);

    const tail = await rawRequest(`/cdn/${key}`, { headers: { range: "bytes=-3" } });
    expect(tail.headers.get("content-range")).toBe("bytes 7-9/10");
  });

  it("416s a range past the end of the file", async () => {
    const res = await rawRequest(`/cdn/${key}`, { headers: { range: "bytes=50-60" } });
    expect(res.status).toBe(416);
    expect(res.headers.get("content-range")).toBe("bytes */10");
  });

  it("404s for other buckets' keys, bad paths, missing clips, and outside dev", async () => {
    expect((await rawRequest("/cdn/source/secret.mp3")).status).toBe(404);
    expect((await rawRequest("/cdn/clips/%E0.mp3")).status).toBe(404); // malformed escape: not a 500
    expect((await rawRequest("/cdn/clips/%2E%2E/source/x.mp3")).status).toBe(404);
    expect((await rawRequest("/cdn/clips/404/none.mp3")).status).toBe(404);
    const { default: app } = await import("../src/index");
    const prod = await app.fetch(new Request(`https://api.test/cdn/${key}`), { ...env, ENV: "prod" });
    expect(prod.status).toBe(404);
  });
});
