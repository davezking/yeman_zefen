// Catalog admin API: tracks, artists (+ aliases, merge) and clips.
// Mounted on the human admin router, so requireAdmin() already guards every route here.
// Editors and admins can edit; only admins can merge artists.
import { and, count, desc, eq, exists, inArray, isNull, lt, notExists, or, sql, type SQL } from "drizzle-orm";
import { alias } from "drizzle-orm/sqlite-core";
import { Hono } from "hono";
import { z } from "zod";
import { db, type Db } from "../../db/client";
import {
  artistAliases,
  artists,
  CLIP_TYPES,
  clips,
  generations,
  genres,
  reviewItems,
  TRACK_STATUSES,
  trackGenres,
  tracks,
} from "../../db/schema";
import type { AppEnv } from "../../env";
import { requireRole } from "../../lib/accessAuth";
import { isUniqueViolation } from "../../lib/dbErrors";
import { cdnUrl } from "../../lib/cdn";
import { ApiError } from "../../lib/errors";
import { assignGeneration } from "../../lib/era";
import { isOutOfCatalog } from "../../lib/trackStatus";
import { createJob, jobOut } from "../../lib/jobs";
import { presignSourceUrl } from "../../lib/sourceUrl";
import { cleanText, normalizeAlias, normalizeFidel, normalizeLatin } from "../../lib/normalize";
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

/** Public URL of a clip's file. Only ready clips have one: a pending clip's file no longer matches its start. */
export function clipUrl(cdnBase: string, clip: { r2Key: string | null; status: string }): string | null {
  return clip.r2Key && clip.status === "ready" ? cdnUrl(cdnBase, clip.r2Key) : null;
}

async function loadTrackDetail(d: Db, cdnBase: string, id: number) {
  const track = await requireTrack(d, id);
  const [artist, aliases, trackClips, openReviewItems, genreRows] = await Promise.all([
    d.select().from(artists).where(eq(artists.id, track.artistId)).get(),
    d.select().from(artistAliases).where(eq(artistAliases.artistId, track.artistId)),
    d.select().from(clips).where(eq(clips.trackId, id)).orderBy(clips.type),
    d
      .select()
      .from(reviewItems)
      .where(and(eq(reviewItems.entityType, "track"), eq(reviewItems.entityId, id), eq(reviewItems.status, "open"))),
    d.select({ genreId: trackGenres.genreId }).from(trackGenres).where(eq(trackGenres.trackId, id)).orderBy(trackGenres.genreId),
  ]);
  return {
    track,
    artist,
    aliases,
    clips: trackClips.map((clip) => ({ ...clip, url: clipUrl(cdnBase, clip) })),
    openReviewItems,
    genreIds: genreRows.map((r) => r.genreId),
  };
}

// ----------------------------------------------------------------- tracks

const trackListQuerySchema = z.strictObject({
  status: z.enum(TRACK_STATUSES).optional(),
  generationId: z.coerce.number().int().positive().optional(),
  artistId: z.coerce.number().int().positive().optional(),
  genreId: z.coerce.number().int().positive().optional(),
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
  if (f.genreId) {
    where.push(sql`EXISTS (SELECT 1 FROM track_genres tg WHERE tg.track_id = tracks.id AND tg.genre_id = ${f.genreId})`);
  }
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
      // Correlated subqueries, so the list stays one statement however many rows it returns. A null clip
      // status means the clip row does not exist yet. Qualified by hand (see the artists list below).
      introStatus: sql<string | null>`(SELECT c.status FROM clips c WHERE c.track_id = tracks.id AND c.type = 'intro')`,
      middleStatus: sql<string | null>`(SELECT c.status FROM clips c WHERE c.track_id = tracks.id AND c.type = 'middle')`,
      openFlagCount: sql<number>`(SELECT COUNT(*) FROM review_items r WHERE r.entity_type = 'track' AND r.entity_id = tracks.id AND r.status = 'open')`,
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
  return c.json(await loadTrackDetail(db(c.env), c.env.CDN_BASE_URL, idParam(c)));
});

const trackPatchSchema = z
  .strictObject({
    titleAm: z.string().trim().min(1).max(300).nullable(),
    titleLatin: z.string().trim().min(1).max(300).nullable(),
    album: z.string().trim().min(1).max(300).nullable(),
    releaseYear: z.number().int().min(1900).max(2100).nullable(),
    generationId: z.number().int().positive().nullable(),
    artistId: z.number().int().positive(),
    /** Replaces the track's whole genre set. */
    genreIds: z.array(z.number().int().positive()).max(10),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, "at least one field is required");

// A short-lived signed URL for the track's private source audio, so the clip editor can draw its waveform.
catalog.get("/tracks/:id/source-url", async (c) => {
  const track = await requireTrack(db(c.env), idParam(c));
  if (!track.sourceAudioKey) throw new ApiError(404, "no_source_audio", `Track ${track.id} has no source audio`);
  return c.json(await presignSourceUrl(c.env, track.sourceAudioKey));
});

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
  // Remember which fields an admin touched so a re-scrape never overwrites them (generation is covered by
  // generation_overridden). Genres count as one field: ingest stops re-linking scraped genres.
  const touched = [
    ...(["titleAm", "titleLatin", "album", "releaseYear", "artistId"] as const).filter((f) => body[f] !== undefined),
    ...(body.genreIds !== undefined ? ["genres"] : []),
  ];
  if (touched.length > 0) {
    const edited = new Set<string>(JSON.parse(existing.adminEditedFields) as string[]);
    for (const f of touched) edited.add(f);
    set.adminEditedFields = JSON.stringify([...edited].sort());
  }

  // Era. A manual pick pins it against auto-assignment. Otherwise it follows the release year, the same rule ingest
  // uses: re-derive it when the admin clears the pick or changes the year, and flag a year that matches no era.
  const pinned = body.generationId !== undefined ? body.generationId !== null : existing.generationOverridden;
  if (body.generationId != null) {
    const gen = await d.select({ id: generations.id }).from(generations).where(eq(generations.id, body.generationId)).get();
    if (!gen) throw new ApiError(404, "not_found", `Generation ${body.generationId} not found`);
    set.generationId = body.generationId;
    set.generationOverridden = true;
  } else if (!pinned && (body.generationId === null || body.releaseYear !== undefined)) {
    const year = body.releaseYear !== undefined ? body.releaseYear : existing.releaseYear;
    const all = await d
      .select({ id: generations.id, yearFrom: generations.yearFrom, yearTo: generations.yearTo })
      .from(generations)
      .orderBy(generations.sort);
    set.generationId = assignGeneration(year, all)?.id ?? null;
    set.generationOverridden = false;
  }
  const eraTouched = body.generationId !== undefined || body.releaseYear !== undefined;
  const eraAfter = set.generationId !== undefined ? set.generationId : existing.generationId;
  const openEraItem = (and(
    eq(reviewItems.entityType, "track"),
    eq(reviewItems.entityId, id),
    eq(reviewItems.reason, "era_unknown"),
    eq(reviewItems.status, "open"),
  )) as SQL;
  const eraStatements = [];
  if (eraTouched && eraAfter !== null) {
    // The era is known now, so an open "era unknown" item is settled by this edit.
    const who = c.get("admin")?.email ?? null;
    eraStatements.push(d.update(reviewItems).set({ status: "resolved", resolvedBy: who, resolvedAt: Date.now() }).where(openEraItem));
  } else if (eraTouched && !pinned && !isOutOfCatalog(existing.status)) {
    // The duplicate check runs inside the batch, so two quick saves cannot each open an item.
    eraStatements.push(
      d.insert(reviewItems).select(
        d
          // Drizzle's insert-from-select wants every column, in table order.
          .select({
            id: sql<number>`NULL`.as("id"),
            entityType: sql<string>`'track'`.as("entity_type"),
            entityId: tracks.id,
            reason: sql<"era_unknown">`'era_unknown'`.as("reason"),
            detailsJson: sql<string | null>`NULL`.as("details_json"),
            status: sql<"open">`'open'`.as("status"),
            resolvedBy: sql<string | null>`NULL`.as("resolved_by"),
            resolvedAt: sql<number | null>`NULL`.as("resolved_at"),
          })
          .from(tracks)
          .where(and(eq(tracks.id, id), notExists(d.select({ one: sql`1` }).from(reviewItems).where(openEraItem)))),
      ),
      // As in ingest: a clean track that is flagged needs a human look.
      d.update(tracks).set({ status: "needs_review" }).where(and(eq(tracks.id, id), eq(tracks.status, "ingested"))),
    );
  }

  const genreIds = body.genreIds && [...new Set(body.genreIds)];
  if (genreIds && genreIds.length > 0) {
    const found = await d.select({ id: genres.id }).from(genres).where(inArray(genres.id, genreIds));
    const missing = genreIds.filter((g) => !found.some((f) => f.id === g));
    if (missing.length > 0) throw new ApiError(404, "not_found", `Genre ${missing[0]} not found`);
  }
  // One atomic batch (a handful of statements, however many genres): everything in the edit lands together.
  await d.batch([
    d.update(tracks).set(set).where(eq(tracks.id, id)),
    ...(genreIds ? [d.delete(trackGenres).where(eq(trackGenres.trackId, id))] : []),
    ...(genreIds?.length ? [d.insert(trackGenres).values(genreIds.map((genreId) => ({ trackId: id, genreId })))] : []),
    ...eraStatements,
  ]);
  return c.json(await loadTrackDetail(d, c.env.CDN_BASE_URL, id));
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

/**
 * Take a track out of the catalog (reject or retire). In one batch with the status change, its open review items are
 * dismissed: nothing about it is left to review. A track that others are marked as duplicates of cannot be rejected,
 * or every copy of the song would be out; retiring an approved one is allowed, since that takes the song out on purpose.
 */
async function takeOut(d: Db, id: number, to: "rejected" | "retired", who: string | null) {
  const action = to === "rejected" ? "reject" : "retire";
  const from: (typeof TRACK_STATUSES)[number][] = to === "rejected" ? ["ingested", "needs_review"] : ["approved"];
  const other = alias(tracks, "other");
  const noDuplicates = notExists(d.select({ one: sql`1` }).from(other).where(eq(other.canonicalTrackId, id)));
  const now = Date.now();
  const [updated] = await d.batch([
    d
      .update(tracks)
      .set({ status: to, updatedAt: now })
      .where(and(eq(tracks.id, id), inArray(tracks.status, from), to === "rejected" ? noDuplicates : undefined))
      .returning({ id: tracks.id }),
    // Only if the update above took effect: the track now has the new status, stamped by this request.
    d
      .update(reviewItems)
      .set({ status: "dismissed", resolvedBy: who, resolvedAt: now })
      .where(
        and(
          openItemsOf(id),
          exists(d.select({ one: sql`1` }).from(tracks).where(and(eq(tracks.id, id), eq(tracks.status, to), eq(tracks.updatedAt, now)))),
        ),
      ),
  ]);
  if (updated.length === 0) {
    const current = await requireTrack(d, id);
    if (to === "rejected" && from.includes(current.status)) {
      const dup = await d.select({ id: tracks.id }).from(tracks).where(eq(tracks.canonicalTrackId, id)).get();
      if (dup) {
        throw new ApiError(409, "has_duplicates", `Track ${dup.id} is marked as a duplicate of this track; rejecting this one would leave no copy of the song`);
      }
    }
    throw new ApiError(409, "invalid_transition", `Cannot ${action} a track that is ${current.status}`);
  }
}

/** Every open review item of a track. */
function openItemsOf(trackId: number): SQL {
  return and(eq(reviewItems.entityType, "track"), eq(reviewItems.entityId, trackId), eq(reviewItems.status, "open")) as SQL;
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
  return c.json(await loadTrackDetail(d, c.env.CDN_BASE_URL, id));
});

catalog.post("/tracks/:id/reject", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  await takeOut(d, id, "rejected", c.get("admin")?.email ?? null);
  return c.json(await loadTrackDetail(d, c.env.CDN_BASE_URL, id));
});

const markDuplicateSchema = z.strictObject({ canonicalTrackId: z.number().int().positive() });

/**
 * "This track is the same song as `canonicalTrackId`": reject it and link it to that track. Nothing is deleted, the
 * clips and the track stay as they are, and its open possible_duplicate items are settled in the same batch.
 */
catalog.post("/tracks/:id/mark-duplicate", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const { canonicalTrackId } = parse(markDuplicateSchema, await readJson(c));
  if (canonicalTrackId === id) throw new ApiError(400, "validation_error", "canonicalTrackId: a track cannot be a duplicate of itself");
  const track = await requireTrack(d, id);
  const canonical = await requireTrack(d, canonicalTrackId);
  // These checks give the precise reason. The same rules are repeated as guards in the update below, so two
  // admins acting at once cannot get past them between the check and the write.
  const blocker = await duplicateBlocker(d, track, canonical);
  if (blocker) throw blocker;

  const now = Date.now();
  const who = c.get("admin")?.email ?? null;
  const other = alias(tracks, "other");
  const linked = and(eq(tracks.id, id), eq(tracks.canonicalTrackId, canonicalTrackId)) as SQL;
  const nowLinked = exists(d.select({ one: sql`1` }).from(tracks).where(linked));
  await d.batch([
    d
      .update(tracks)
      .set({ canonicalTrackId, status: "rejected", updatedAt: now })
      .where(
        and(
          eq(tracks.id, id),
          inArray(tracks.status, ["ingested", "needs_review"]),
          // Nothing is a duplicate of this track...
          notExists(d.select({ one: sql`1` }).from(other).where(eq(other.canonicalTrackId, id))),
          // ...and the canonical track is a usable track that is not itself a duplicate.
          exists(
            d
              .select({ one: sql`1` })
              .from(other)
              .where(and(eq(other.id, canonicalTrackId), isNull(other.canonicalTrackId), inArray(other.status, CANONICAL_STATUSES))),
          ),
        ),
      ),
    // Only if the update above took effect: the duplicate flags are settled by this decision, and the track's other
    // open items no longer matter (it is out of the catalog).
    d
      .update(reviewItems)
      .set({ status: "resolved", resolvedBy: who, resolvedAt: now })
      .where(
        and(
          openItemsOf(id),
          eq(reviewItems.reason, "possible_duplicate"),
          // The song-duplicate flag is what this decides. An artist-duplicate flag was not looked at, so it is
          // dismissed with the rest below rather than recorded as resolved.
          sql`json_extract(${reviewItems.detailsJson}, '$.field') = 'track'`,
          nowLinked,
        ),
      ),
    d
      .update(reviewItems)
      .set({ status: "dismissed", resolvedBy: who, resolvedAt: now })
      .where(and(openItemsOf(id), nowLinked)),
  ]);
  const after = await requireTrack(d, id);
  if (after.canonicalTrackId !== canonicalTrackId) {
    // Something changed between the checks and the update (another admin). Report what is in the way now.
    const err = await duplicateBlocker(d, after, await requireTrack(d, canonicalTrackId));
    throw err ?? new ApiError(409, "conflict", "The tracks changed while this was being saved; try again");
  }
  return c.json(await loadTrackDetail(d, c.env.CDN_BASE_URL, id));
});

/** Statuses a canonical track may have: one that is (or may become) part of the catalog. */
const CANONICAL_STATUSES: (typeof TRACK_STATUSES)[number][] = ["ingested", "needs_review", "approved"];

/**
 * Why `track` cannot be marked as a duplicate of `canonical`, or null if it can. Links stay one level deep: a
 * duplicate points at a track that is not itself a duplicate, and a track that others point at cannot become one.
 * Chains and cycles would make "the canonical track" ambiguous.
 */
async function duplicateBlocker(d: Db, track: typeof tracks.$inferSelect, canonical: typeof tracks.$inferSelect) {
  if (!["ingested", "needs_review"].includes(track.status)) {
    return new ApiError(409, "invalid_transition", `Cannot mark a track that is ${track.status} as a duplicate`);
  }
  // Checked first: a duplicate is always rejected too, and "use that one" is the more useful answer.
  if (canonical.canonicalTrackId !== null) {
    return new ApiError(409, "canonical_is_duplicate", `Track ${canonical.id} is itself a duplicate of track ${canonical.canonicalTrackId}; use that one`);
  }
  if (!CANONICAL_STATUSES.includes(canonical.status)) {
    return new ApiError(409, "canonical_not_usable", `Track ${canonical.id} is ${canonical.status}, so it cannot be the original; pick a track that is in the catalog`);
  }
  const pointedAt = await d.select({ id: tracks.id }).from(tracks).where(eq(tracks.canonicalTrackId, track.id)).get();
  if (pointedAt) {
    return new ApiError(409, "has_duplicates", `Track ${pointedAt.id} is marked as a duplicate of this track, so this one cannot be a duplicate`);
  }
  return null;
}

catalog.post("/tracks/:id/retire", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  await takeOut(d, id, "retired", c.get("admin")?.email ?? null);
  return c.json(await loadTrackDetail(d, c.env.CDN_BASE_URL, id));
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

const artistCreateSchema = z.strictObject({
  nameAm: z.string().trim().min(1).max(200),
  nameLatin: z.string().trim().min(1).max(200).nullish(),
});

catalog.post("/artists", async (c) => {
  const d = db(c.env);
  const body = parse(artistCreateSchema, await readJson(c));
  const nameAm = cleanText(body.nameAm);
  const nameLatin = body.nameLatin ? cleanText(body.nameLatin) : null;
  const key = normalizeFidel(nameAm);
  const now = Date.now();
  // One batch, so the duplicate check and both inserts are atomic: of two editors creating homophone spellings at
  // once, the second sees the first one's alias. A spelling that folds to a known name or alias is that artist.
  let results: D1Result[];
  try {
    results = await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO artists (name_am, name_latin, created_at, updated_at)
         SELECT ?1, ?2, ?3, ?3 WHERE ?4 = '' OR NOT EXISTS (SELECT 1 FROM artist_aliases WHERE alias_norm = ?4)`,
      ).bind(nameAm, nameLatin, now, key),
      // The canonical name is also an alias, as in ingest: its folded key is how later spellings are matched.
      c.env.DB.prepare(
        `INSERT INTO artist_aliases (artist_id, alias, alias_norm, source)
         SELECT id, name_am, ?2, 'canonical' FROM artists
         WHERE name_am = ?1 AND ?2 <> '' AND NOT EXISTS (SELECT 1 FROM artist_aliases WHERE alias_norm = ?2)`,
      ).bind(nameAm, key),
    ]);
  } catch (err) {
    if (isUniqueViolation(err)) throw new ApiError(409, "name_taken", "An artist with that Amharic name already exists");
    throw err;
  }
  if (results[0]!.meta.changes === 0) {
    const known = await d.select().from(artistAliases).where(eq(artistAliases.aliasNorm, key)).get();
    const owner = known ? await d.select().from(artists).where(eq(artists.id, known.artistId)).get() : undefined;
    throw new ApiError(
      409,
      "artist_exists",
      owner ? `That name matches the existing artist ${owner.nameAm} (id ${owner.id})` : "That name matches an existing artist",
    );
  }
  const artist = await d.select().from(artists).where(eq(artists.nameAm, nameAm)).get();
  return c.json({ artist }, 201);
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

  // The existing file no longer matches the start, so the clip is pending until it is recut.
  const [updated] = await d.update(clips).set({ startMs, status: "pending" }).where(eq(clips.id, id)).returning();

  // Ask for that recut now. The edit is already saved, so a job that cannot be started (GitHub down, no
  // token) must not fail the request: it is recorded as failed, and the clip stays pending for the next cut.
  let job: ReturnType<typeof jobOut> | null = null;
  try {
    job = jobOut((await createJob(c.env, { kind: "recut", params: { trackId: clip.trackId, type: clip.type, startMs } })).job);
  } catch (err) {
    console.error("could not create the recut job", err instanceof Error ? err.message : String(err));
  }
  return c.json({ needsRecut: true, clip: updated, job });
});
