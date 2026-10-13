// Catalog admin API: tracks, artists (+ aliases, merge) and clips.
// Mounted on the human admin router, so requireAdmin() already guards every route here.
// Editors and admins can edit; only admins can merge artists.
import { and, count, desc, eq, inArray, lt, or, sql, type SQL } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db, type Db } from "../../db/client";
import {
  artistAliases,
  artists,
  CLIP_TYPES,
  clips,
  generations,
  reviewItems,
  TRACK_STATUSES,
  tracks,
} from "../../db/schema";
import type { AppEnv } from "../../env";
import { requireRole } from "../../lib/accessAuth";
import { isUniqueViolation } from "../../lib/dbErrors";
import { ApiError } from "../../lib/errors";
import { normalizeAlias, normalizeFidel, normalizeLatin } from "../../lib/normalize";
import { idParam, parse, readJson } from "../../lib/validate";

export const PAGE_SIZE = 50;

export const catalog = new Hono<AppEnv>();

// ---------------------------------------------------------------- helpers

const likeEscape = (s: string) => s.replace(/[\\%_]/g, (m) => `\\${m}`);
const containsLike = (col: SQL | unknown, q: string) => sql`${col} LIKE ${`%${likeEscape(q)}%`} ESCAPE '\\'`;

async function requireTrack(d: Db, id: number) {
  const row = await d.select().from(tracks).where(eq(tracks.id, id)).get();
  if (!row) throw new ApiError(404, "not_found", `Track ${id} not found`);
  return row;
}

async function requireArtist(d: Db, id: number) {
  const row = await d.select().from(artists).where(eq(artists.id, id)).get();
  if (!row) throw new ApiError(404, "not_found", `Artist ${id} not found`);
  return row;
}

async function loadTrackDetail(d: Db, id: number) {
  const track = await requireTrack(d, id);
  const [artist, aliases, trackClips, openReviewItems] = await Promise.all([
    d.select().from(artists).where(eq(artists.id, track.artistId)).get(),
    d.select().from(artistAliases).where(eq(artistAliases.artistId, track.artistId)),
    d.select().from(clips).where(eq(clips.trackId, id)).orderBy(clips.type),
    d
      .select()
      .from(reviewItems)
      .where(and(eq(reviewItems.entityType, "track"), eq(reviewItems.entityId, id), eq(reviewItems.status, "open"))),
  ]);
  return { track, artist, aliases, clips: trackClips, openReviewItems };
}

// ----------------------------------------------------------------- tracks

const trackListQuerySchema = z.strictObject({
  status: z.enum(TRACK_STATUSES).optional(),
  generationId: z.coerce.number().int().positive().optional(),
  artistId: z.coerce.number().int().positive().optional(),
  q: z.string().trim().min(1).max(200).optional(),
  cursor: z.coerce.number().int().positive().optional(),
});
export type TrackListFilters = z.infer<typeof trackListQuerySchema>;

/** Newest first, keyset-paginated on id. Exported so tests can EXPLAIN the exact SQL. */
export function trackListQuery(d: Db, f: TrackListFilters) {
  const where: (SQL | undefined)[] = [];
  if (f.status) where.push(eq(tracks.status, f.status));
  if (f.generationId) where.push(eq(tracks.generationId, f.generationId));
  if (f.artistId) where.push(eq(tracks.artistId, f.artistId));
  if (f.q) where.push(or(containsLike(tracks.titleAm, f.q), containsLike(tracks.titleLatin, f.q)));
  if (f.cursor) where.push(lt(tracks.id, f.cursor));
  return d
    .select({
      id: tracks.id,
      titleAm: tracks.titleAm,
      titleLatin: tracks.titleLatin,
      album: tracks.album,
      releaseYear: tracks.releaseYear,
      generationId: tracks.generationId,
      generationOverridden: tracks.generationOverridden,
      status: tracks.status,
      artistId: tracks.artistId,
      artistNameAm: artists.nameAm,
      artistNameLatin: artists.nameLatin,
      updatedAt: tracks.updatedAt,
    })
    .from(tracks)
    .innerJoin(artists, eq(artists.id, tracks.artistId))
    .where(and(...where))
    .orderBy(desc(tracks.id))
    .limit(PAGE_SIZE + 1);
}

catalog.get("/tracks", async (c) => {
  const filters = parse(trackListQuerySchema, c.req.query(), "query");
  const rows = await trackListQuery(db(c.env), filters);
  const items = rows.slice(0, PAGE_SIZE);
  const nextCursor = rows.length > PAGE_SIZE ? String(items[items.length - 1]!.id) : null;
  return c.json({ items, nextCursor });
});

catalog.get("/tracks/:id", async (c) => {
  return c.json(await loadTrackDetail(db(c.env), idParam(c)));
});

const trackPatchSchema = z
  .strictObject({
    titleAm: z.string().trim().min(1).max(300).nullable(),
    titleLatin: z.string().trim().min(1).max(300).nullable(),
    album: z.string().trim().min(1).max(300).nullable(),
    releaseYear: z.number().int().min(1900).max(2100).nullable(),
    generationId: z.number().int().positive().nullable(),
    artistId: z.number().int().positive(),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, "at least one field is required");

catalog.patch("/tracks/:id", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const body = parse(trackPatchSchema, await readJson(c));
  const existing = await requireTrack(d, id);

  const set: Partial<typeof tracks.$inferInsert> = { updatedAt: Date.now() };
  if (body.titleAm !== undefined) set.titleAm = body.titleAm;
  if (body.titleLatin !== undefined) set.titleLatin = body.titleLatin;
  if (body.album !== undefined) set.album = body.album;
  if (body.releaseYear !== undefined) set.releaseYear = body.releaseYear;
  if (body.artistId !== undefined) {
    await requireArtist(d, body.artistId);
    set.artistId = body.artistId;
  }
  // Remember which scraped fields an admin touched so a re-scrape never overwrites them
  // (generation is covered by generation_overridden).
  const touched = (["titleAm", "titleLatin", "album", "releaseYear", "artistId"] as const).filter(
    (f) => body[f] !== undefined,
  );
  if (touched.length > 0) {
    const edited = new Set<string>(JSON.parse(existing.adminEditedFields) as string[]);
    for (const f of touched) edited.add(f);
    set.adminEditedFields = JSON.stringify([...edited].sort());
  }
  if (body.generationId !== undefined) {
    if (body.generationId !== null) {
      const gen = await d.select({ id: generations.id }).from(generations).where(eq(generations.id, body.generationId)).get();
      if (!gen) throw new ApiError(404, "not_found", `Generation ${body.generationId} not found`);
    }
    set.generationId = body.generationId;
    // A manual pick pins the generation against auto-assignment; clearing it hands control back.
    set.generationOverridden = body.generationId !== null;
  }

  await d.update(tracks).set(set).where(eq(tracks.id, id));
  return c.json(await loadTrackDetail(d, id));
});

/** Status machine: ingested → needs_review → approved | rejected, approved → retired. */
async function transition(
  d: Db,
  id: number,
  action: string,
  from: readonly (typeof TRACK_STATUSES)[number][],
  to: (typeof TRACK_STATUSES)[number],
) {
  const updated = await d
    .update(tracks)
    .set({ status: to, updatedAt: Date.now() })
    .where(and(eq(tracks.id, id), inArray(tracks.status, [...from])))
    .returning({ id: tracks.id });
  if (updated.length === 0) {
    const current = await requireTrack(d, id);
    throw new ApiError(409, "invalid_transition", `Cannot ${action} a track that is ${current.status}`);
  }
}

catalog.post("/tracks/:id/approve", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const track = await requireTrack(d, id);
  if (!["ingested", "needs_review"].includes(track.status)) {
    throw new ApiError(409, "invalid_transition", `Cannot approve a track that is ${track.status}`);
  }

  const trackClips = await d.select().from(clips).where(eq(clips.trackId, id));
  const problems = CLIP_TYPES.flatMap((type) => {
    const clip = trackClips.find((cl) => cl.type === type);
    if (!clip) return [`${type} clip is missing`];
    return clip.status === "ready" ? [] : [`${type} clip is ${clip.status}`];
  });
  if (problems.length > 0) {
    throw new ApiError(409, "clips_not_ready", `Cannot approve: ${problems.join(", ")}`);
  }

  await transition(d, id, "approve", ["ingested", "needs_review"], "approved");
  return c.json(await loadTrackDetail(d, id));
});

catalog.post("/tracks/:id/reject", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  await transition(d, id, "reject", ["ingested", "needs_review"], "rejected");
  return c.json(await loadTrackDetail(d, id));
});

catalog.post("/tracks/:id/retire", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  await transition(d, id, "retire", ["approved"], "retired");
  return c.json(await loadTrackDetail(d, id));
});

// ---------------------------------------------------------------- artists

const artistListQuerySchema = z.strictObject({
  q: z.string().trim().min(1).max(200).optional(),
  cursor: z.coerce.number().int().positive().optional(),
});

catalog.get("/artists", async (c) => {
  const f = parse(artistListQuerySchema, c.req.query(), "query");
  const d = db(c.env);
  const where: (SQL | undefined)[] = [];
  if (f.q) where.push(or(containsLike(artists.nameAm, f.q), containsLike(artists.nameLatin, f.q)));
  if (f.cursor) where.push(lt(artists.id, f.cursor));
  const rows = await d
    .select({
      id: artists.id,
      nameAm: artists.nameAm,
      nameLatin: artists.nameLatin,
      updatedAt: artists.updatedAt,
      // Qualified by hand: Drizzle prints single-table columns unqualified, which inside this
      // subquery would resolve to tracks.id.
      trackCount: sql<number>`(SELECT COUNT(*) FROM tracks WHERE tracks.artist_id = artists.id)`,
    })
    .from(artists)
    .where(and(...where))
    .orderBy(desc(artists.id))
    .limit(PAGE_SIZE + 1);
  const items = rows.slice(0, PAGE_SIZE);
  const nextCursor = rows.length > PAGE_SIZE ? String(items[items.length - 1]!.id) : null;
  return c.json({ items, nextCursor });
});

catalog.get("/artists/:id", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const artist = await requireArtist(d, id);
  const [aliases, [{ n: trackCount } = { n: 0 }]] = await Promise.all([
    d.select().from(artistAliases).where(eq(artistAliases.artistId, id)),
    d.select({ n: count() }).from(tracks).where(eq(tracks.artistId, id)),
  ]);
  return c.json({ artist, aliases, trackCount });
});

const artistPatchSchema = z
  .strictObject({
    nameAm: z.string().trim().min(1).max(200),
    nameLatin: z.string().trim().min(1).max(200).nullable(),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, "at least one field is required");

catalog.patch("/artists/:id", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const body = parse(artistPatchSchema, await readJson(c));
  await requireArtist(d, id);
  try {
    await d
      .update(artists)
      .set({ ...body, nameAm: body.nameAm?.normalize("NFC"), updatedAt: Date.now() })
      .where(eq(artists.id, id));
  } catch (err) {
    if (isUniqueViolation(err)) {
      throw new ApiError(409, "name_taken", "Another artist already has that Amharic name; merge them instead");
    }
    throw err;
  }
  return c.json({ artist: await requireArtist(d, id) });
});

const aliasSchema = z.strictObject({
  alias: z.string().trim().min(1).max(200),
  source: z.string().trim().min(1).max(100).optional(),
});

catalog.post("/artists/:id/aliases", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const body = parse(aliasSchema, await readJson(c));
  await requireArtist(d, id);
  const aliasNorm = normalizeAlias(body.alias);
  if (!aliasNorm) throw new ApiError(400, "validation_error", "alias: nothing left after normalization");
  try {
    const [row] = await d
      .insert(artistAliases)
      .values({ artistId: id, alias: body.alias, aliasNorm, source: body.source ?? "admin" })
      .returning();
    return c.json({ alias: row }, 201);
  } catch (err) {
    if (isUniqueViolation(err)) {
      const owner = await d.select().from(artistAliases).where(eq(artistAliases.aliasNorm, aliasNorm)).get();
      throw new ApiError(409, "alias_exists", `That alias already belongs to artist ${owner?.artistId ?? "?"}`);
    }
    throw err;
  }
});

catalog.delete("/artists/:id/aliases/:aliasId", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const aliasId = idParam(c, "aliasId");
  const removed = await d
    .delete(artistAliases)
    .where(and(eq(artistAliases.id, aliasId), eq(artistAliases.artistId, id)))
    .returning({ id: artistAliases.id });
  if (removed.length === 0) throw new ApiError(404, "not_found", `Alias ${aliasId} not found on artist ${id}`);
  return c.body(null, 204);
});

const mergeSchema = z.strictObject({ intoArtistId: z.number().int().positive() });

/** Merge artist :id INTO `intoArtistId`. Admin only. */
catalog.post("/artists/:id/merge", requireRole("admin"), async (c) => {
  const d = db(c.env);
  const fromId = idParam(c);
  const { intoArtistId } = parse(mergeSchema, await readJson(c));
  if (fromId === intoArtistId) throw new ApiError(400, "validation_error", "intoArtistId: cannot merge an artist into itself");
  const from = await requireArtist(d, fromId);
  await requireArtist(d, intoArtistId);

  const [[{ n: tracksMoved } = { n: 0 }], [{ n: aliasesMoved } = { n: 0 }]] = await Promise.all([
    d.select({ n: count() }).from(tracks).where(eq(tracks.artistId, fromId)),
    d.select({ n: count() }).from(artistAliases).where(eq(artistAliases.artistId, fromId)),
  ]);

  // One atomic D1 batch: either everything moves and the old artist is gone, or nothing changes.
  // The old names become aliases of the survivor; ON CONFLICT DO NOTHING keeps the merge from
  // failing when that spelling is already an alias somewhere.
  const now = Date.now();
  const nameAliases = [{ alias: from.nameAm, norm: normalizeFidel(from.nameAm) }];
  if (from.nameLatin) nameAliases.push({ alias: from.nameLatin, norm: normalizeLatin(from.nameLatin) });
  await d.batch([
    d.update(tracks).set({ artistId: intoArtistId, updatedAt: now }).where(eq(tracks.artistId, fromId)),
    d.update(artistAliases).set({ artistId: intoArtistId }).where(eq(artistAliases.artistId, fromId)),
    ...nameAliases
      .filter((a) => a.norm)
      .map((a) =>
        d
          .insert(artistAliases)
          .values({ artistId: intoArtistId, alias: a.alias, aliasNorm: a.norm, source: "merge" })
          .onConflictDoNothing({ target: artistAliases.aliasNorm }),
      ),
    d.update(artists).set({ updatedAt: now }).where(eq(artists.id, intoArtistId)),
    d.delete(artists).where(eq(artists.id, fromId)),
  ]);

  return c.json({ merged: { fromArtistId: fromId, intoArtistId, tracksMoved, aliasesMoved } });
});

// ------------------------------------------------------------------ clips

const clipPatchSchema = z.strictObject({ start_ms: z.number().int().min(0) });

catalog.patch("/clips/:id", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const { start_ms: startMs } = parse(clipPatchSchema, await readJson(c));
  const clip = await d.select().from(clips).where(eq(clips.id, id)).get();
  if (!clip) throw new ApiError(404, "not_found", `Clip ${id} not found`);
  const track = await requireTrack(d, clip.trackId);

  if (track.durationMs == null) {
    throw new ApiError(409, "duration_unknown", "Track duration is unknown, so the start time cannot be validated");
  }
  const maxStart = track.durationMs - clip.lengthMs;
  if (maxStart < 0) {
    throw new ApiError(409, "track_too_short", `Track is shorter (${track.durationMs} ms) than the clip length (${clip.lengthMs} ms)`);
  }
  if (startMs > maxStart) {
    throw new ApiError(400, "validation_error", `start_ms: must be between 0 and ${maxStart} for this track`);
  }

  // The existing file no longer matches; Sprint 2's job trigger will recut it.
  const [updated] = await d.update(clips).set({ startMs, status: "pending" }).where(eq(clips.id, id)).returning();
  return c.json({ needsRecut: true, clip: updated });
});
