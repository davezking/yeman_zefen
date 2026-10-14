// The review queue API: listing and counting items, and marking a track as a duplicate of another.
import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { clips, reviewItems, tracks } from "../src/db/schema";
import { reviewListQuery } from "../src/routes/admin/reviewItems";
import { api, installTestJwks, makeArtist, makeClip, makeTrack, rawRequest, removeTestJwks, resetCatalog, seedAdmins } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(resetCatalog);
afterAll(() => removeTestJwks());

const json = async (res: Response) => (await res.json()) as any; // test-only: response shapes are asserted below

type Reason = "translit_uncertain" | "possible_duplicate" | "missing_audio" | "short_audio" | "era_unknown";
async function addItem(
  trackId: number,
  reason: Reason,
  extra: { status?: "open" | "resolved" | "dismissed"; details?: string | null; entityType?: string } = {},
) {
  const [row] = await db(env)
    .insert(reviewItems)
    .values({
      entityType: extra.entityType ?? "track",
      entityId: trackId,
      reason,
      status: extra.status ?? "open",
      detailsJson: extra.details === undefined ? null : extra.details,
    })
    .returning();
  return row!;
}

describe("GET /admin/review-items", () => {
  it("lists open track items oldest first, with the track and parsed details", async () => {
    const artist = await makeArtist("ጥላሁን ገሠሠ", "Tilahun Gessesse");
    const t = await makeTrack(artist.id, { titleAm: "ዘፈን", titleLatin: "Song", releaseYear: 1975, durationMs: 200000, sourceUrl: "https://z.test/1" });
    const first = await addItem(t.id, "translit_uncertain", { details: '{"field":"title","source":"Zefen","generated":"ዘፈን","confidence":0.4}' });
    const second = await addItem(t.id, "era_unknown", { details: null });
    await addItem(t.id, "short_audio", { details: "not json at all" });

    const body = await json(await api("/admin/review-items"));
    expect(body.items.map((i: any) => i.id)).toEqual([first.id, second.id, first.id + 2]);
    expect(body.items[0]).toMatchObject({
      reason: "translit_uncertain",
      status: "open",
      details: { field: "title", source: "Zefen", generated: "ዘፈን", confidence: 0.4 },
      track: {
        id: t.id,
        titleAm: "ዘፈን",
        titleLatin: "Song",
        releaseYear: 1975,
        durationMs: 200000,
        sourceUrl: "https://z.test/1",
        status: "ingested",
        artistId: artist.id,
        artistNameAm: "ጥላሁን ገሠሠ",
        artistNameLatin: "Tilahun Gessesse",
      },
    });
    expect(body.items[1].details).toBeNull();
    expect(body.items[2].details).toBeNull(); // not JSON: handed on as null, not a 500
    expect(body.items[0]).not.toHaveProperty("detailsJson");
    expect(body.nextCursor).toBeNull();
  });

  it("filters by reason and status, and leaves out items that are not about tracks", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    await addItem(t.id, "era_unknown");
    await addItem(t.id, "missing_audio");
    await addItem(t.id, "missing_audio", { status: "resolved" });
    await addItem(t.id, "missing_audio", { status: "dismissed" });
    await addItem(artist.id, "possible_duplicate", { entityType: "artist" });

    const reasons = async (q: string) => (await json(await api(`/admin/review-items${q}`))).items.map((i: any) => i.reason);
    expect(await reasons("")).toEqual(["era_unknown", "missing_audio"]); // open only, by default
    expect(await reasons("?reason=missing_audio")).toEqual(["missing_audio"]);
    expect(await reasons("?reason=missing_audio&status=resolved")).toEqual(["missing_audio"]);
    expect(await reasons("?status=dismissed")).toEqual(["missing_audio"]);
    expect(await reasons("?reason=possible_duplicate")).toEqual([]);
  });

  it("pages 50 at a time with a cursor, oldest first", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    const ids: number[] = [];
    for (let i = 0; i < 55; i++) ids.push((await addItem(t.id, "era_unknown")).id);

    const page1 = await json(await api("/admin/review-items?reason=era_unknown"));
    expect(page1.items).toHaveLength(50);
    expect(page1.items.map((i: any) => i.id)).toEqual(ids.slice(0, 50));
    expect(page1.nextCursor).toBe(String(ids[49]));
    const page2 = await json(await api(`/admin/review-items?reason=era_unknown&cursor=${page1.nextCursor}`));
    expect(page2.items.map((i: any) => i.id)).toEqual(ids.slice(50));
    expect(page2.nextCursor).toBeNull();
  });

  it("uses the (status, reason) index without a sort when filtered by reason", async () => {
    const { sql: text, params } = reviewListQuery(db(env), { reason: "era_unknown", status: "open" }).toSQL();
    const plan = (await env.DB.prepare(`EXPLAIN QUERY PLAN ${text}`).bind(...params).all<{ detail: string }>()).results
      .map((r) => r.detail)
      .join("\n");
    expect(plan).toMatch(/review_items_status_reason_idx/);
    expect(plan).not.toMatch(/USE TEMP B-TREE FOR ORDER BY/);
  });

  it("rejects bad filters with 400 and needs an admin", async () => {
    expect((await api("/admin/review-items?reason=nope")).status).toBe(400);
    expect((await api("/admin/review-items?status=nope")).status).toBe(400);
    expect((await api("/admin/review-items?cursor=0")).status).toBe(400);
    expect((await api("/admin/review-items?extra=1")).status).toBe(400);
    expect((await rawRequest("/admin/review-items")).status).toBe(401);
    expect((await rawRequest("/admin/review-items/counts")).status).toBe(401);
  });
});

describe("GET /admin/review-items/counts", () => {
  it("counts open track items per reason, with zeros for the rest", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    await addItem(t.id, "era_unknown");
    await addItem(t.id, "era_unknown");
    await addItem(t.id, "short_audio");
    await addItem(t.id, "short_audio", { status: "resolved" });
    await addItem(artist.id, "possible_duplicate", { entityType: "artist" });

    expect((await json(await api("/admin/review-items/counts"))).counts).toEqual({
      translit_uncertain: 0,
      possible_duplicate: 0,
      missing_audio: 0,
      short_audio: 1,
      era_unknown: 2,
    });
  });

  it("counts only items the list can show (an item whose track is gone is not counted)", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    await addItem(t.id, "era_unknown");
    await addItem(999_999, "era_unknown"); // no such track
    expect((await json(await api("/admin/review-items/counts"))).counts.era_unknown).toBe(1);
    expect((await json(await api("/admin/review-items?reason=era_unknown"))).items).toHaveLength(1);
  });

  it("drops an item from the count once it is closed", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id);
    const item = await addItem(t.id, "missing_audio");
    await api(`/admin/review-items/${item.id}/resolve`, { method: "POST" });
    expect((await json(await api("/admin/review-items/counts"))).counts.missing_audio).toBe(0);
  });
});

describe("taking a track out closes its review items", () => {
  it("rejecting dismisses every open item of the track, and only of that track", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { status: "needs_review" });
    const other = await makeTrack(artist.id, { status: "needs_review" });
    await addItem(t.id, "era_unknown");
    await addItem(t.id, "missing_audio");
    await addItem(t.id, "short_audio", { status: "resolved" });
    const keep = await addItem(other.id, "era_unknown");

    expect((await api(`/admin/tracks/${t.id}/reject`, { method: "POST", as: "editor" })).status).toBe(200);
    const items = await db(env).select().from(reviewItems).where(eq(reviewItems.entityId, t.id));
    expect(items.map((i) => i.status).sort()).toEqual(["dismissed", "dismissed", "resolved"]);
    expect(items.filter((i) => i.status === "dismissed").every((i) => i.resolvedBy === "editor@yz.test")).toBe(true);
    expect((await db(env).select().from(reviewItems).where(eq(reviewItems.id, keep.id)).get())!.status).toBe("open");
    expect((await json(await api("/admin/review-items/counts"))).counts.era_unknown).toBe(1);
  });

  it("refuses to reject a track that others are duplicates of, but allows retiring one", async () => {
    const artist = await makeArtist("አርቲስት");
    const original = await makeTrack(artist.id, { status: "needs_review" });
    const dup = await makeTrack(artist.id, { status: "needs_review" });
    expect((await api(`/admin/tracks/${dup.id}/mark-duplicate`, { body: { canonicalTrackId: original.id } })).status).toBe(200);
    const item = await addItem(original.id, "era_unknown");

    const res = await api(`/admin/tracks/${original.id}/reject`, { method: "POST" });
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("has_duplicates");
    expect((await db(env).select().from(tracks).where(eq(tracks.id, original.id)).get())!.status).toBe("needs_review");
    expect((await db(env).select().from(reviewItems).where(eq(reviewItems.id, item.id)).get())!.status).toBe("open");

    await db(env).update(tracks).set({ status: "approved" }).where(eq(tracks.id, original.id));
    expect((await api(`/admin/tracks/${original.id}/retire`, { method: "POST" })).status).toBe(200);
  });

  it("an era edit on a rejected track opens no era_unknown item", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { status: "rejected", releaseYear: 1985, generationId: 2 });
    expect((await api(`/admin/tracks/${t.id}`, { method: "PATCH", body: { releaseYear: null } })).status).toBe(200);
    expect(await db(env).select().from(reviewItems).where(eq(reviewItems.entityId, t.id))).toEqual([]);
  });

  it("the queue and its counts leave out tracks that are out of the catalog", async () => {
    const artist = await makeArtist("አርቲስት");
    const live = await makeTrack(artist.id, { status: "needs_review" });
    const out = await makeTrack(artist.id, { status: "rejected" });
    await addItem(live.id, "era_unknown");
    await addItem(out.id, "era_unknown"); // e.g. left open before items were closed on rejection
    expect((await json(await api("/admin/review-items?reason=era_unknown"))).items.map((i: any) => i.track.id)).toEqual([live.id]);
    expect((await json(await api("/admin/review-items/counts"))).counts.era_unknown).toBe(1);
  });

  it("retiring does the same; approving leaves items alone; a refused move changes nothing", async () => {
    const artist = await makeArtist("አርቲስት");
    const t = await makeTrack(artist.id, { status: "approved" });
    const item = await addItem(t.id, "missing_audio");
    expect((await api(`/admin/tracks/${t.id}/reject`, { method: "POST" })).status).toBe(409); // approved: not rejectable
    expect((await db(env).select().from(reviewItems).where(eq(reviewItems.id, item.id)).get())!.status).toBe("open");
    expect((await api(`/admin/tracks/${t.id}/retire`, { method: "POST" })).status).toBe(200);
    expect((await db(env).select().from(reviewItems).where(eq(reviewItems.id, item.id)).get())!.status).toBe("dismissed");
  });
});

describe("POST /admin/tracks/:id/mark-duplicate", () => {
  const mark = (id: number, canonicalTrackId: unknown, as: "admin" | "editor" = "admin") =>
    api(`/admin/tracks/${id}/mark-duplicate`, { as, body: { canonicalTrackId } });

  async function pair() {
    const artist = await makeArtist("አርቲስት");
    const original = await makeTrack(artist.id, { titleAm: "ዘፈን", status: "approved" });
    const dup = await makeTrack(artist.id, { titleAm: "ዘፈን (ድጋሚ)", status: "needs_review" });
    return { artist, original, dup };
  }

  it("rejects the track and links it to the canonical one, deleting nothing", async () => {
    const { artist, original, dup } = await pair();
    await makeClip(dup.id, "intro");
    await makeClip(dup.id, "middle");
    const dupItem = await addItem(dup.id, "possible_duplicate", { details: '{"field":"track","candidates":[{"id":1,"score":0.9}]}' });
    const artistItem = await addItem(dup.id, "possible_duplicate", { details: '{"field":"artist","candidates":[{"id":1,"score":0.9}]}' });
    const otherItem = await addItem(dup.id, "era_unknown");

    const res = await mark(dup.id, original.id, "editor");
    expect(res.status).toBe(200);
    const body = await json(res);
    expect(body.track).toMatchObject({ id: dup.id, status: "rejected", canonicalTrackId: original.id });

    // The duplicate item is settled by this decision; the track's other items no longer matter (it is out).
    const items = await db(env).select().from(reviewItems).where(eq(reviewItems.entityId, dup.id));
    expect(items.find((i) => i.id === dupItem.id)).toMatchObject({ status: "resolved", resolvedBy: "editor@yz.test" });
    expect(items.find((i) => i.id === otherItem.id)).toMatchObject({ status: "dismissed", resolvedBy: "editor@yz.test" });
    // The artist question was not looked at, so it is dismissed, not recorded as resolved.
    expect(items.find((i) => i.id === artistItem.id)?.status).toBe("dismissed");

    // Nothing is deleted: both tracks, the artist and the duplicate's clips are all still there.
    expect(await db(env).select().from(tracks)).toHaveLength(2);
    expect(await db(env).select().from(clips).where(eq(clips.trackId, dup.id))).toHaveLength(2);
    expect((await json(await api(`/admin/artists/${artist.id}`))).trackCount).toBe(2);
    expect((await db(env).select().from(tracks).where(eq(tracks.id, original.id)).get())!.status).toBe("approved");
  });

  it("works from ingested as well as needs_review", async () => {
    const { original, dup } = await pair();
    await db(env).update(tracks).set({ status: "ingested" }).where(eq(tracks.id, dup.id));
    expect((await mark(dup.id, original.id)).status).toBe(200);
  });

  it("validates the request and the tracks", async () => {
    const { original, dup } = await pair();
    expect((await mark(dup.id, dup.id)).status).toBe(400); // itself
    expect((await mark(dup.id, "x")).status).toBe(400);
    expect((await mark(dup.id, undefined)).status).toBe(400);
    expect((await mark(dup.id, 999999)).status).toBe(404); // no such canonical track
    expect((await mark(999999, original.id)).status).toBe(404); // no such track
    expect((await api(`/admin/tracks/abc/mark-duplicate`, { body: { canonicalTrackId: 1 } })).status).toBe(400);
    expect((await api(`/admin/tracks/${dup.id}/mark-duplicate`, { body: { canonicalTrackId: original.id, extra: 1 } })).status).toBe(400);
    expect((await rawRequest(`/admin/tracks/${dup.id}/mark-duplicate`, { method: "POST" })).status).toBe(401);
    // None of the failures changed anything.
    expect((await db(env).select().from(tracks).where(eq(tracks.id, dup.id)).get())).toMatchObject({ status: "needs_review", canonicalTrackId: null });
  });

  it("409s unless the track is ingested or needs_review", async () => {
    const { original, dup } = await pair();
    for (const status of ["approved", "rejected", "retired"] as const) {
      await db(env).update(tracks).set({ status }).where(eq(tracks.id, dup.id));
      const res = await mark(dup.id, original.id);
      expect(res.status, status).toBe(409);
      expect((await json(res)).error.code).toBe("invalid_transition");
    }
  });

  it("409s when the original is rejected or retired", async () => {
    const { original, dup } = await pair();
    for (const status of ["rejected", "retired"] as const) {
      await db(env).update(tracks).set({ status }).where(eq(tracks.id, original.id));
      const res = await mark(dup.id, original.id);
      expect(res.status, status).toBe(409);
      expect((await json(res)).error.code).toBe("canonical_not_usable");
    }
    // An original that is not reviewed yet is fine: both may be new.
    await db(env).update(tracks).set({ status: "ingested" }).where(eq(tracks.id, original.id));
    expect((await mark(dup.id, original.id)).status).toBe(200);
  });

  it("two admins at once cannot make a chain or a cycle", async () => {
    const artist = await makeArtist("አርቲስት");
    const [x, y, z] = await Promise.all([1, 2, 3].map(() => makeTrack(artist.id, { status: "needs_review" })));
    // X→Y and Y→Z at the same moment: one of them must lose, or X→Y→Z would be a chain.
    const chain = await Promise.all([mark(x!.id, y!.id), mark(y!.id, z!.id)]);
    expect(chain.map((r) => r.status).sort()).toEqual([200, 409]);

    const [p, q] = await Promise.all([1, 2].map(() => makeTrack(artist.id, { status: "needs_review" })));
    const cycle = await Promise.all([mark(p!.id, q!.id), mark(q!.id, p!.id)]);
    expect(cycle.map((r) => r.status).sort()).toEqual([200, 409]);

    // Whatever the order, every link points at a track that is not itself a duplicate.
    const all = await db(env).select().from(tracks);
    for (const t of all.filter((t) => t.canonicalTrackId !== null)) {
      expect(all.find((o) => o.id === t.canonicalTrackId)!.canonicalTrackId, `track ${t.id}`).toBeNull();
    }
  });

  it("looks up 'is anything a duplicate of this track' with an index", async () => {
    const plan = (await env.DB.prepare("EXPLAIN QUERY PLAN SELECT id FROM tracks WHERE canonical_track_id = ?").bind(1).all<{ detail: string }>())
      .results.map((r) => r.detail)
      .join("\n");
    expect(plan).toMatch(/tracks_canonical_track_id_idx/);
  });

  it("keeps links one level deep: no chains, no cycles", async () => {
    const { artist, original, dup } = await pair();
    expect((await mark(dup.id, original.id)).status).toBe(200);

    // A duplicate cannot be the canonical track of another.
    const third = await makeTrack(artist.id, { status: "needs_review" });
    const toDup = await mark(third.id, dup.id);
    expect(toDup.status).toBe(409);
    expect((await json(toDup)).error.code).toBe("canonical_is_duplicate");

    // A track that others point at cannot become a duplicate itself.
    await db(env).update(tracks).set({ status: "needs_review" }).where(eq(tracks.id, original.id));
    const cycle = await mark(original.id, third.id);
    expect(cycle.status).toBe(409);
    expect((await json(cycle)).error.code).toBe("has_duplicates");
  });
});
