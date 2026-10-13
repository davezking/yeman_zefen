import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { artistAliases, artists, clips, reviewItems, tracks } from "../src/db/schema";
import { trackListQuery } from "../src/routes/admin/catalog";
import { api, installTestJwks, makeArtist, makeClip, makeTrack, removeTestJwks, resetCatalog, seedAdmins } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(resetCatalog);
afterAll(() => removeTestJwks());

const json = async (res: Response) => (await res.json()) as any; // test-only: response shapes are asserted below

describe("GET /admin/tracks", () => {
  it("paginates 50 per page with a cursor", async () => {
    const artist = await makeArtist("አርቲስት");
    for (let i = 0; i < 55; i++) await makeTrack(artist.id, { titleLatin: `song ${i}` });

    const page1 = await json(await api("/admin/tracks"));
    expect(page1.items).toHaveLength(50);
    expect(page1.nextCursor).toBeTruthy();
    // newest first
    expect(page1.items[0].id).toBeGreaterThan(page1.items[49].id);

    const page2 = await json(await api(`/admin/tracks?cursor=${page1.nextCursor}`));
    expect(page2.items).toHaveLength(5);
    expect(page2.nextCursor).toBeNull();
    const ids = new Set([...page1.items, ...page2.items].map((t: { id: number }) => t.id));
    expect(ids.size).toBe(55);
  });

  it("filters by status, artist and generation", async () => {
    const a = await makeArtist("አንደኛ");
    const b = await makeArtist("ሁለተኛ");
    const t1 = await makeTrack(a.id, { status: "needs_review", generationId: 1 });
    await makeTrack(a.id, { status: "approved", generationId: 2 });
    await makeTrack(b.id, { status: "needs_review", generationId: 1 });

    const byStatus = await json(await api("/admin/tracks?status=needs_review"));
    expect(byStatus.items).toHaveLength(2);
    const byArtist = await json(await api(`/admin/tracks?artistId=${a.id}`));
    expect(byArtist.items).toHaveLength(2);
    const combined = await json(await api(`/admin/tracks?artistId=${a.id}&status=needs_review&generationId=1`));
    expect(combined.items.map((t: { id: number }) => t.id)).toEqual([t1.id]);
  });

  it("searches both titles, treating % and _ literally", async () => {
    const a = await makeArtist("ፈላጊ");
    const am = await makeTrack(a.id, { titleAm: "ትዝታ ዘፈን" });
    const lat = await makeTrack(a.id, { titleLatin: "Ambassel Medley" });
    await makeTrack(a.id, { titleLatin: "100% Gold" });

    expect((await json(await api(`/admin/tracks?q=${encodeURIComponent("ትዝታ")}`))).items.map((t: any) => t.id)).toEqual([am.id]);
    expect((await json(await api("/admin/tracks?q=ambassel"))).items.map((t: any) => t.id)).toEqual([lat.id]);
    expect((await json(await api("/admin/tracks?q=" + encodeURIComponent("%")))).items).toHaveLength(1);
    expect((await json(await api("/admin/tracks?q=" + encodeURIComponent("_")))).items).toHaveLength(0);
  });

  it("rejects bad filters with 400", async () => {
    expect((await api("/admin/tracks?status=bogus")).status).toBe(400);
    expect((await api("/admin/tracks?cursor=abc")).status).toBe(400);
    expect((await api("/admin/tracks?nope=1")).status).toBe(400);
  });

  it("uses indexes for the main filters", async () => {
    const plan = async (filters: Parameters<typeof trackListQuery>[1]) => {
      const { sql: text, params } = trackListQuery(db(env), filters).toSQL();
      const rows = await env.DB.prepare(`EXPLAIN QUERY PLAN ${text}`)
        .bind(...params)
        .all<{ detail: string }>();
      return rows.results.map((r) => r.detail).join("\n");
    };
    expect(await plan({ status: "needs_review" })).toMatch(/tracks_status_idx/);
    expect(await plan({ artistId: 1 })).toMatch(/tracks_artist_id_idx/);
    expect(await plan({ generationId: 1 })).toMatch(/tracks_generation_id_idx/);
    // No filter: walks the primary key newest-first, no full-table sort.
    const unfiltered = await plan({});
    expect(unfiltered).not.toMatch(/USE TEMP B-TREE FOR ORDER BY/);
  });
});

describe("GET /admin/tracks/:id", () => {
  it("returns the track with artist, aliases, clips and only open review items", async () => {
    const artist = await makeArtist("ጥላሁን", "Tilahun");
    await db(env).insert(artistAliases).values({ artistId: artist.id, alias: "Tilahun G", aliasNorm: "tilahun g" });
    const track = await makeTrack(artist.id);
    await makeClip(track.id, "intro");
    await makeClip(track.id, "middle", "pending");
    await db(env).insert(reviewItems).values([
      { entityType: "track", entityId: track.id, reason: "era_unknown", status: "open" },
      { entityType: "track", entityId: track.id, reason: "short_audio", status: "resolved" },
      { entityType: "artist", entityId: track.id, reason: "possible_duplicate", status: "open" },
    ]);

    const body = await json(await api(`/admin/tracks/${track.id}`));
    expect(body.track.id).toBe(track.id);
    expect(body.artist.nameAm).toBe("ጥላሁን");
    expect(body.aliases.map((a: any) => a.alias)).toEqual(["Tilahun G"]);
    expect(body.clips.map((c: any) => [c.type, c.status])).toEqual([["intro", "ready"], ["middle", "pending"]]);
    expect(body.openReviewItems.map((r: any) => r.reason)).toEqual(["era_unknown"]);
  });

  it("404s for a missing track and 400s for a bad id", async () => {
    expect((await api("/admin/tracks/999999")).status).toBe(404);
    expect((await api("/admin/tracks/abc")).status).toBe(400);
  });
});

describe("PATCH /admin/tracks/:id", () => {
  it("edits fields, and setting generationId sets generation_overridden", async () => {
    const a = await makeArtist("አርቲስት");
    const t = await makeTrack(a.id, { releaseYear: 1975, generationId: 1 });
    expect(t.generationOverridden).toBe(false);

    const res = await api(`/admin/tracks/${t.id}`, {
      method: "PATCH",
      as: "editor",
      body: { titleLatin: "New Title", releaseYear: 1985, generationId: 2 },
    });
    expect(res.status).toBe(200);
    const { track } = await json(res);
    expect(track).toMatchObject({ titleLatin: "New Title", releaseYear: 1985, generationId: 2, generationOverridden: true });
    expect(track.updatedAt).toBeGreaterThan(t.updatedAt);
  });

  it("clearing generationId hands control back to auto-assignment", async () => {
    const a = await makeArtist("አርቲስት");
    const t = await makeTrack(a.id, { generationId: 2, generationOverridden: true });
    const { track } = await json(await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { generationId: null } }));
    expect(track).toMatchObject({ generationId: null, generationOverridden: false });
  });

  it("validates input", async () => {
    const a = await makeArtist("አርቲስት");
    const t = await makeTrack(a.id);
    const patch = (body: unknown) => api(`/admin/tracks/${t.id}`, { method: "PATCH", body });
    expect((await patch({})).status).toBe(400);
    expect((await patch({ status: "approved" })).status).toBe(400); // status is not editable here
    expect((await patch({ releaseYear: "1975" })).status).toBe(400);
    expect((await patch({ generationId: 999 })).status).toBe(404);
    expect((await patch({ artistId: 999999 })).status).toBe(404);
    const bad = await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: undefined });
    expect(bad.status).toBe(400); // GET-less PATCH with no body -> invalid_json
  });
});

describe("approve / reject / retire", () => {
  it("409s with a clear reason when clips are missing or not ready", async () => {
    const a = await makeArtist("አርቲስት");
    const noClips = await makeTrack(a.id, { status: "needs_review" });
    let res = await api(`/admin/tracks/${noClips.id}/approve`, { method: "POST" });
    expect(res.status).toBe(409);
    let body = await json(res);
    expect(body.error.code).toBe("clips_not_ready");
    expect(body.error.message).toContain("intro clip is missing");
    expect(body.error.message).toContain("middle clip is missing");

    const half = await makeTrack(a.id, { status: "needs_review" });
    await makeClip(half.id, "intro");
    await makeClip(half.id, "middle", "pending");
    res = await api(`/admin/tracks/${half.id}/approve`, { method: "POST" });
    expect(res.status).toBe(409);
    body = await json(res);
    expect(body.error.message).toBe("Cannot approve: middle clip is pending");

    const [row] = await db(env).select().from(tracks).where(eq(tracks.id, half.id));
    expect(row!.status).toBe("needs_review"); // untouched
  });

  it("approves once both clips are ready, then retires; invalid transitions are 409", async () => {
    const a = await makeArtist("አርቲስት");
    const t = await makeTrack(a.id, { status: "needs_review" });
    await makeClip(t.id, "intro");
    await makeClip(t.id, "middle");

    const approved = await api(`/admin/tracks/${t.id}/approve`, { method: "POST", as: "editor" });
    expect(approved.status).toBe(200);
    expect((await json(approved)).track.status).toBe("approved");

    expect((await api(`/admin/tracks/${t.id}/approve`, { method: "POST" })).status).toBe(409); // already approved
    expect((await api(`/admin/tracks/${t.id}/reject`, { method: "POST" })).status).toBe(409); // approved can't be rejected

    const retired = await api(`/admin/tracks/${t.id}/retire`, { method: "POST" });
    expect((await json(retired)).track.status).toBe("retired");
    expect((await api(`/admin/tracks/${t.id}/retire`, { method: "POST" })).status).toBe(409);
  });

  it("rejects an ingested or needs_review track, but not twice", async () => {
    const a = await makeArtist("አርቲስት");
    const t = await makeTrack(a.id, { status: "ingested" });
    const res = await api(`/admin/tracks/${t.id}/reject`, { method: "POST" });
    expect((await json(res)).track.status).toBe("rejected");
    expect((await api(`/admin/tracks/${t.id}/reject`, { method: "POST" })).status).toBe(409);
    expect((await api("/admin/tracks/999999/reject", { method: "POST" })).status).toBe(404);
  });
});

describe("artists", () => {
  it("lists with track counts, gets one, and patches", async () => {
    const a = await makeArtist("አስቴር", "Aster");
    await makeTrack(a.id);
    await makeTrack(a.id);

    const list = await json(await api("/admin/artists?q=aster"));
    expect(list.items).toHaveLength(1);
    expect(list.items[0].trackCount).toBe(2);

    const one = await json(await api(`/admin/artists/${a.id}`));
    expect(one.artist.nameAm).toBe("አስቴር");
    expect(one.trackCount).toBe(2);

    const patched = await api(`/admin/artists/${a.id}`, { method: "PATCH", as: "editor", body: { nameLatin: "Aster Aweke" } });
    expect((await json(patched)).artist.nameLatin).toBe("Aster Aweke");
  });

  it("409s when renaming onto an existing name_am", async () => {
    await makeArtist("አንደኛ");
    const b = await makeArtist("ሁለተኛ");
    const res = await api(`/admin/artists/${b.id}`, { method: "PATCH", body: { nameAm: "አንደኛ" } });
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("name_taken");
  });

  it("adds aliases with a normalized key, rejects duplicates, and removes them", async () => {
    const a = await makeArtist("አስቴር");
    const b = await makeArtist("መሐሙድ");

    const add = await api(`/admin/artists/${a.id}/aliases`, { body: { alias: "Äster  O'Aweke" } });
    expect(add.status).toBe(201);
    const { alias } = await json(add);
    expect(alias.aliasNorm).toBe("aster oaweke");

    const dup = await api(`/admin/artists/${b.id}/aliases`, { body: { alias: "ASTER OAWEKE" } });
    expect(dup.status).toBe(409);
    expect((await json(dup)).error.message).toContain(String(a.id));

    expect((await api(`/admin/artists/${a.id}/aliases`, { body: { alias: "'''" } })).status).toBe(400);

    // wrong artist -> 404, right artist -> 204
    expect((await api(`/admin/artists/${b.id}/aliases/${alias.id}`, { method: "DELETE" })).status).toBe(404);
    expect((await api(`/admin/artists/${a.id}/aliases/${alias.id}`, { method: "DELETE" })).status).toBe(204);
  });

  it("merges artists atomically with no orphans, and only admins may merge", async () => {
    const from = await makeArtist("ጥላሁን ገሠሠ", "Tilahun Gessesse");
    const into = await makeArtist("ጥላሁን ገሰሰ");
    const t1 = await makeTrack(from.id);
    const t2 = await makeTrack(from.id);
    const keep = await makeTrack(into.id);
    await db(env).insert(artistAliases).values([
      { artistId: from.id, alias: "T. Gessesse", aliasNorm: "t. gessesse" },
      { artistId: into.id, alias: "Tilahun G", aliasNorm: "tilahun g" },
    ]);

    // editors are refused and nothing changes
    const denied = await api(`/admin/artists/${from.id}/merge`, { body: { intoArtistId: into.id }, as: "editor" });
    expect(denied.status).toBe(403);
    expect(await db(env).select().from(artists).where(eq(artists.id, from.id))).toHaveLength(1);

    const res = await api(`/admin/artists/${from.id}/merge`, { body: { intoArtistId: into.id }, as: "admin" });
    expect(res.status).toBe(200);
    expect((await json(res)).merged).toEqual({ fromArtistId: from.id, intoArtistId: into.id, tracksMoved: 2, aliasesMoved: 1 });

    // source artist is gone; every track and alias points at the survivor
    expect(await db(env).select().from(artists).where(eq(artists.id, from.id))).toHaveLength(0);
    const survivorTracks = await db(env).select().from(tracks).where(eq(tracks.artistId, into.id));
    expect(survivorTracks.map((t) => t.id).sort()).toEqual([t1.id, t2.id, keep.id].sort());
    const aliases = await db(env).select().from(artistAliases).where(eq(artistAliases.artistId, into.id));
    expect(aliases.map((a) => a.aliasNorm).sort()).toEqual(
      ["t. gessesse", "tilahun g", "ጥላሁን ገሰሰ", "tilahun gessesse"].sort(), // alias keys are folded
    );

    // nothing orphaned anywhere
    const orphanTracks = await env.DB.prepare("SELECT COUNT(*) AS n FROM tracks WHERE artist_id NOT IN (SELECT id FROM artists)").first<{ n: number }>();
    const orphanAliases = await env.DB.prepare("SELECT COUNT(*) AS n FROM artist_aliases WHERE artist_id NOT IN (SELECT id FROM artists)").first<{ n: number }>();
    expect(orphanTracks!.n).toBe(0);
    expect(orphanAliases!.n).toBe(0);
    const fkViolations = await env.DB.prepare("PRAGMA foreign_key_check").all();
    expect(fkViolations.results).toHaveLength(0);
  });

  it("merge tolerates a name that is already an alias elsewhere, and rejects bad targets", async () => {
    const from = await makeArtist("አንደኛ");
    const into = await makeArtist("ሁለተኛ");
    await db(env).insert(artistAliases).values({ artistId: into.id, alias: "አንደኛ", aliasNorm: "አንደኛ" });
    expect((await api(`/admin/artists/${from.id}/merge`, { body: { intoArtistId: into.id } })).status).toBe(200);

    const solo = await makeArtist("ብቸኛ");
    expect((await api(`/admin/artists/${solo.id}/merge`, { body: { intoArtistId: solo.id } })).status).toBe(400);
    expect((await api(`/admin/artists/${solo.id}/merge`, { body: { intoArtistId: 999999 } })).status).toBe(404);
    expect((await api(`/admin/artists/${solo.id}/merge`, { body: {} })).status).toBe(400);
    expect(await db(env).select().from(artists).where(eq(artists.id, solo.id))).toHaveLength(1);
  });
});

describe("PATCH /admin/clips/:id", () => {
  let n = 0;
  async function setup(durationMs: number | null = 200_000) {
    const a = await makeArtist(`አርቲስት ${++n}`);
    const t = await makeTrack(a.id, { durationMs });
    const clip = await makeClip(t.id, "intro", "ready");
    return clip;
  }

  it("sets start_ms, marks the clip pending, and reports needsRecut", async () => {
    const clip = await setup();
    const res = await api(`/admin/clips/${clip.id}`, { method: "PATCH", as: "editor", body: { start_ms: 42_000 } });
    expect(res.status).toBe(200);
    const body = await json(res);
    expect(body.needsRecut).toBe(true);
    expect(body.clip).toMatchObject({ startMs: 42_000, status: "pending" });
    const [row] = await db(env).select().from(clips).where(eq(clips.id, clip.id));
    expect(row).toMatchObject({ startMs: 42_000, status: "pending" });
  });

  it("enforces 0 <= start_ms <= duration_ms - length_ms", async () => {
    const clip = await setup(200_000); // length 10_000 -> max start 190_000
    const patch = (start_ms: number) => api(`/admin/clips/${clip.id}`, { method: "PATCH", body: { start_ms } });
    expect((await patch(190_000)).status).toBe(200);
    expect((await patch(190_001)).status).toBe(400);
    expect((await patch(-1)).status).toBe(400);
    expect((await api(`/admin/clips/${clip.id}`, { method: "PATCH", body: { start_ms: 1.5 } })).status).toBe(400);
  });

  it("409s when the duration is unknown or the track is shorter than the clip", async () => {
    const unknown = await setup(null);
    const res = await api(`/admin/clips/${unknown.id}`, { method: "PATCH", body: { start_ms: 0 } });
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("duration_unknown");

    const tiny = await setup(5_000);
    const short = await api(`/admin/clips/${tiny.id}`, { method: "PATCH", body: { start_ms: 0 } });
    expect(short.status).toBe(409);
    expect((await json(short)).error.code).toBe("track_too_short");
  });

  it("404s for a missing clip", async () => {
    expect((await api("/admin/clips/999999", { method: "PATCH", body: { start_ms: 0 } })).status).toBe(404);
  });
});

describe("auth and errors", () => {
  it("every catalog route requires an admin", async () => {
    const { rawRequest } = await import("./helpers");
    for (const [method, path] of [
      ["GET", "/admin/tracks"],
      ["GET", "/admin/tracks/1"],
      ["PATCH", "/admin/tracks/1"],
      ["POST", "/admin/tracks/1/approve"],
      ["GET", "/admin/artists"],
      ["POST", "/admin/artists/1/merge"],
      ["PATCH", "/admin/clips/1"],
    ] as const) {
      expect((await rawRequest(path, { method })).status, `${method} ${path}`).toBe(401);
    }
  });

  it("malformed JSON is 400, not 500", async () => {
    const a = await makeArtist("አርቲስት");
    const { rawRequest, signAccessJwt } = await import("./helpers");
    const res = await rawRequest(`/admin/artists/${a.id}`, {
      method: "PATCH",
      jwt: await signAccessJwt({ email: "admin@yz.test" }),
      headers: { "content-type": "application/json" },
      body: "{not json",
    });
    expect(res.status).toBe(400);
    expect((await json(res)).error.code).toBe("invalid_json");
  });
});
