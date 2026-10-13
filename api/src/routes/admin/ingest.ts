// Ingest API for GitHub Actions (service-token auth, mounted under /admin/ingest).
// Spec: docs/phase-1-sprint-1-prompts.md "Ingest API" and docs/architecture.md §3, §5.
//
// Design notes
// - Reads happen in ONE d.batch up front; every write is a prepared statement run through
//   env.DB.batch in chunks, so a 100-record request costs a handful of D1 round trips.
// - Re-sending the same request is a no-op: tracks upsert on source_url, aliases and genre
//   links are INSERT-OR-IGNORE, review items are skipped when an identical open one exists,
//   and clips are only rewritten (and version-bumped) when something actually changed.
// - D1 allows 100 bound parameters per statement, so multi-row inserts are chunked.
import { and, eq, inArray, sql } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db, type Db } from "../../db/client";
import {
  artistAliases,
  artists,
  CLIP_TYPES,
  clips,
  genres,
  INGEST_KINDS,
  INGEST_STATUSES,
  ingestJobs,
  REVIEW_REASONS,
  reviewItems,
  trackGenres,
  tracks,
} from "../../db/schema";
import type { AppEnv, Bindings } from "../../env";
import { ApiError } from "../../lib/errors";
import { normalizeAlias, normalizeFidel } from "../../lib/normalize";
import { parse, readJson, idParam } from "../../lib/validate";

export const MAX_BATCH = 100;
const STATEMENTS_PER_CALL = 100;
const ALIAS_ROWS_PER_INSERT = 20; // 4 bound params per row, well under D1's 100

export const ingestRoutes = new Hono<AppEnv>();

// ---------------------------------------------------------------- helpers

type Prepared = D1PreparedStatement;

function fromQuery(env: Bindings, query: { toSQL(): { sql: string; params: unknown[] } }): Prepared {
  const { sql: text, params } = query.toSQL();
  return env.DB.prepare(text).bind(...params);
}

/** Run statements in order, in chunks that each commit atomically. */
async function runBatched(env: Bindings, statements: Prepared[]): Promise<void> {
  for (let i = 0; i < statements.length; i += STATEMENTS_PER_CALL) {
    await env.DB.batch(statements.slice(i, i + STATEMENTS_PER_CALL));
  }
}

/** JSON with sorted keys, so "identical details" compares equal regardless of key order. */
function stableJson(value: unknown): string {
  return JSON.stringify(value, (_k, v: unknown) =>
    v && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)))
      : v,
  );
}

async function requireOpenJob(d: Db, id: number, kinds: readonly (typeof INGEST_KINDS)[number][]) {
  const job = await d.select().from(ingestJobs).where(eq(ingestJobs.id, id)).get();
  if (!job) throw new ApiError(404, "job_not_found", `Ingest job ${id} not found`);
  if (!kinds.includes(job.kind)) {
    throw new ApiError(409, "job_kind_mismatch", `Job ${id} is a '${job.kind}' job; this endpoint takes ${kinds.join(" or ")} jobs`);
  }
  if (job.status === "succeeded" || job.status === "failed") {
    throw new ApiError(409, "job_finished", `Job ${id} already ${job.status}`);
  }
  return job;
}

// ----------------------------------------------------------------- tracks

/** Empty strings from the scraper mean "no value". */
const optText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullish()
    .transform((v) => (v ? v : null));

const trackInput = z.strictObject({
  sourceUrl: z.url().max(2000),
  titleAm: optText(300),
  titleLatin: optText(300),
  artistAm: z.string().trim().min(1).max(200),
  artistLatin: optText(200),
  artistAliases: z.array(z.string().trim().min(1).max(200)).max(20).default([]),
  album: optText(300),
  releaseYear: z.number().int().min(1800).max(2100).nullish().transform((v) => v ?? null),
  genres: z.array(z.string().trim().min(1).max(50)).max(10).default([]),
  durationMs: z.number().int().min(0).nullish().transform((v) => v ?? null),
  sourceAudioKey: optText(500),
  flags: z
    .array(
      z.strictObject({
        reason: z.enum(REVIEW_REASONS),
        details: z.record(z.string(), z.unknown()).nullish(),
      }),
    )
    .max(10)
    .default([]),
});

const tracksBody = z
  .strictObject({
    jobId: z.number().int().positive(),
    tracks: z.array(trackInput).min(1).max(MAX_BATCH),
  })
  .superRefine((b, ctx) => {
    const seen = new Set<string>();
    b.tracks.forEach((t, i) => {
      if (seen.has(t.sourceUrl)) {
        ctx.addIssue({ code: "custom", path: ["tracks", i, "sourceUrl"], message: "duplicate sourceUrl in this batch" });
      }
      seen.add(t.sourceUrl);
    });
  });

const SCRAPED_FIELDS = ["titleAm", "titleLatin", "album", "releaseYear", "artistId", "durationMs", "sourceAudioKey"] as const;

ingestRoutes.post("/tracks", async (c) => {
  const env = c.env;
  const d = db(env);
  const body = parse(tracksBody, await readJson(c));
  await requireOpenJob(d, body.jobId, ["scrape"]);
  const now = Date.now();

  const recs = body.tracks.map((t) => ({ ...t, artistKey: normalizeFidel(t.artistAm) }));
  const urls = recs.map((r) => r.sourceUrl);
  const keys = [...new Set(recs.map((r) => r.artistKey))];

  // One round trip for every read this request needs (each statement stays <= 100 params).
  const [aliasRows, artistRows, trackRows, genreRows, linkRows, openRows] = await d.batch([
    d.select().from(artistAliases).where(inArray(artistAliases.aliasNorm, keys)),
    d.select().from(artists).where(inArray(artists.nameAm, keys)),
    d.select().from(tracks).where(inArray(tracks.sourceUrl, urls)),
    d.select().from(genres),
    d
      .select({ trackId: trackGenres.trackId, genreId: trackGenres.genreId })
      .from(trackGenres)
      .innerJoin(tracks, eq(tracks.id, trackGenres.trackId))
      .where(inArray(tracks.sourceUrl, urls)),
    d
      .select({ entityId: reviewItems.entityId, reason: reviewItems.reason, detailsJson: reviewItems.detailsJson })
      .from(reviewItems)
      .innerJoin(tracks, eq(tracks.id, reviewItems.entityId))
      .where(and(sql`${reviewItems.entityType} = 'track'`, sql`${reviewItems.status} = 'open'`, inArray(tracks.sourceUrl, urls))),
  ]);

  // ---- artists: match by normalized name_am (via the canonical alias row, then name_am itself).
  const artistIdByKey = new Map<string, number>();
  for (const a of aliasRows) artistIdByKey.set(a.aliasNorm, a.artistId);
  for (const a of artistRows) if (!artistIdByKey.has(a.nameAm)) artistIdByKey.set(a.nameAm, a.id);

  const groups = new Map<string, typeof recs>();
  for (const r of recs) groups.set(r.artistKey, [...(groups.get(r.artistKey) ?? []), r]);
  const firstLatin = (key: string) => groups.get(key)!.find((r) => r.artistLatin)?.artistLatin ?? null;

  const newKeys = keys.filter((k) => !artistIdByKey.has(k));
  if (newKeys.length > 0) {
    const creates: Prepared[] = [];
    for (const key of newKeys) {
      creates.push(
        fromQuery(
          env,
          d
            .insert(artists)
            .values({ nameAm: key, nameLatin: firstLatin(key), createdAt: now, updatedAt: now })
            .onConflictDoNothing({ target: artists.nameAm }),
        ),
        // The canonical name is also an alias, so future folding of name_am keeps matching.
        env.DB.prepare(
          "INSERT INTO artist_aliases (artist_id, alias, alias_norm, source) SELECT id, ?, ?, 'canonical' FROM artists WHERE name_am = ? ON CONFLICT(alias_norm) DO NOTHING",
        ).bind(key, key, key),
      );
    }
    await runBatched(env, creates);
    const created = await d.select({ id: artists.id, nameAm: artists.nameAm }).from(artists).where(inArray(artists.nameAm, newKeys));
    for (const a of created) artistIdByKey.set(a.nameAm, a.id);
  }

  const statements: Prepared[] = [];

  // Aliases (never steal one that already belongs to another artist) and a missing Latin name.
  for (const key of keys) {
    const artistId = artistIdByKey.get(key);
    if (artistId === undefined) throw new ApiError(500, "internal", `Could not resolve artist for '${key}'`);
    const byNorm = new Map<string, string>();
    for (const r of groups.get(key)!) {
      for (const alias of [...r.artistAliases, ...(r.artistLatin ? [r.artistLatin] : [])]) {
        const norm = normalizeAlias(alias);
        if (norm) byNorm.set(norm, alias);
      }
    }
    const rows = [...byNorm].map(([aliasNorm, alias]) => ({ artistId, alias, aliasNorm, source: "scraper" }));
    for (let i = 0; i < rows.length; i += ALIAS_ROWS_PER_INSERT) {
      statements.push(
        fromQuery(env, d.insert(artistAliases).values(rows.slice(i, i + ALIAS_ROWS_PER_INSERT)).onConflictDoNothing({ target: artistAliases.aliasNorm })),
      );
    }
    const latin = firstLatin(key);
    if (latin && !newKeys.includes(key)) {
      statements.push(
        env.DB.prepare("UPDATE artists SET name_latin = ?, updated_at = ? WHERE id = ? AND name_latin IS NULL").bind(latin, now, artistId),
      );
    }
  }

  // ---- tracks
  const existingByUrl = new Map(trackRows.map((t) => [t.sourceUrl!, t]));
  const genreIdBySlug = new Map(genreRows.map((g) => [g.slug, g.id]));
  const linksByTrack = new Map<number, Set<number>>();
  for (const l of linkRows) linksByTrack.set(l.trackId, (linksByTrack.get(l.trackId) ?? new Set()).add(l.genreId));
  const openByTrack = new Map<number, Set<string>>();
  for (const o of openRows) {
    openByTrack.set(o.entityId, (openByTrack.get(o.entityId) ?? new Set()).add(`${o.reason}|${o.detailsJson ?? ""}`));
  }

  type Result = { sourceUrl: string; trackId: number | null; result: "created" | "updated" | "skipped"; unknownGenres?: string[] };
  const results: Result[] = [];

  for (const rec of recs) {
    const artistId = artistIdByKey.get(rec.artistKey)!;
    const knownGenres = [...new Set(rec.genres)].filter((g) => genreIdBySlug.has(g));
    const unknownGenres = [...new Set(rec.genres)].filter((g) => !genreIdBySlug.has(g));
    const flagItems = new Map<string, { reason: (typeof REVIEW_REASONS)[number]; detailsJson: string | null }>();
    for (const f of rec.flags) {
      const detailsJson = f.details ? stableJson(f.details) : null;
      flagItems.set(`${f.reason}|${detailsJson ?? ""}`, { reason: f.reason, detailsJson });
    }
    const existing = existingByUrl.get(rec.sourceUrl);

    const genreStatement = (slug: string) =>
      env.DB.prepare("INSERT OR IGNORE INTO track_genres (track_id, genre_id) SELECT id, ? FROM tracks WHERE source_url = ?").bind(
        genreIdBySlug.get(slug),
        rec.sourceUrl,
      );
    const reviewStatement = (item: { reason: string; detailsJson: string | null }) =>
      env.DB.prepare(
        `INSERT INTO review_items (entity_type, entity_id, reason, details_json, status)
         SELECT 'track', t.id, ?1, ?2, 'open' FROM tracks t
         WHERE t.source_url = ?3 AND NOT EXISTS (
           SELECT 1 FROM review_items r
           WHERE r.entity_type = 'track' AND r.entity_id = t.id AND r.reason = ?1 AND r.status = 'open' AND r.details_json IS ?2)`,
      ).bind(item.reason, item.detailsJson, rec.sourceUrl);

    let outcome: Result["result"];
    if (!existing) {
      outcome = "created";
      statements.push(
        fromQuery(
          env,
          d
            .insert(tracks)
            .values({
              artistId,
              titleAm: rec.titleAm,
              titleLatin: rec.titleLatin,
              album: rec.album,
              releaseYear: rec.releaseYear,
              sourceUrl: rec.sourceUrl,
              sourceAudioKey: rec.sourceAudioKey,
              durationMs: rec.durationMs,
              status: flagItems.size > 0 ? "needs_review" : "ingested",
              createdAt: now,
              updatedAt: now,
            })
            .onConflictDoNothing({ target: tracks.sourceUrl }),
        ),
        ...knownGenres.map(genreStatement),
        ...[...flagItems.values()].map(reviewStatement),
      );
    } else {
      // Fill/refresh scraped fields, but never null out a value and never touch what an admin edited.
      const edited = new Set<string>(JSON.parse(existing.adminEditedFields) as string[]);
      const incoming = { titleAm: rec.titleAm, titleLatin: rec.titleLatin, album: rec.album, releaseYear: rec.releaseYear, artistId, durationMs: rec.durationMs, sourceAudioKey: rec.sourceAudioKey };
      const set: Partial<typeof tracks.$inferInsert> = {};
      for (const field of SCRAPED_FIELDS) {
        const value = incoming[field];
        if (value === null || edited.has(field) || existing[field] === value) continue;
        Object.assign(set, { [field]: value });
      }
      const newGenres = knownGenres.filter((g) => !linksByTrack.get(existing.id)?.has(genreIdBySlug.get(g)!));
      const open = openByTrack.get(existing.id) ?? new Set<string>();
      const newFlags = [...flagItems].filter(([key]) => !open.has(key)).map(([, item]) => item);

      if (Object.keys(set).length > 0) {
        statements.push(fromQuery(env, d.update(tracks).set({ ...set, updatedAt: now }).where(eq(tracks.id, existing.id))));
      }
      statements.push(...newGenres.map(genreStatement), ...newFlags.map(reviewStatement));
      if (newFlags.length > 0 && existing.status === "ingested") {
        statements.push(
          env.DB.prepare("UPDATE tracks SET status = 'needs_review', updated_at = ? WHERE id = ? AND status = 'ingested'").bind(now, existing.id),
        );
      }
      outcome = Object.keys(set).length > 0 || newGenres.length > 0 || newFlags.length > 0 ? "updated" : "skipped";
    }

    results.push({
      sourceUrl: rec.sourceUrl,
      trackId: existing?.id ?? null,
      result: outcome,
      ...(unknownGenres.length > 0 ? { unknownGenres } : {}),
    });
  }

  await runBatched(env, statements);

  const createdUrls = results.filter((r) => r.result === "created").map((r) => r.sourceUrl);
  if (createdUrls.length > 0) {
    const ids = await d.select({ id: tracks.id, sourceUrl: tracks.sourceUrl }).from(tracks).where(inArray(tracks.sourceUrl, createdUrls));
    const idByUrl = new Map(ids.map((r) => [r.sourceUrl!, r.id]));
    for (const r of results) if (r.result === "created") r.trackId = idByUrl.get(r.sourceUrl) ?? null;
  }

  const counts = { created: 0, updated: 0, skipped: 0 };
  for (const r of results) counts[r.result]++;
  return c.json({ jobId: body.jobId, counts, results });
});

// ------------------------------------------------------------------ clips

const clipInput = z.strictObject({
  trackId: z.number().int().positive(),
  type: z.enum(CLIP_TYPES),
  startMs: z.number().int().min(0),
  lengthMs: z.number().int().min(1).max(60_000),
  r2Key: z.string().trim().min(1).max(500),
  sha256: z.string().regex(/^[0-9a-f]{64}$/, "must be 64 lowercase hex characters"),
  bytes: z.number().int().min(1),
});

const clipsBody = z
  .strictObject({
    jobId: z.number().int().positive(),
    clips: z.array(clipInput).min(1).max(MAX_BATCH),
  })
  .superRefine((b, ctx) => {
    const seen = new Set<string>();
    b.clips.forEach((cl, i) => {
      const key = `${cl.trackId}:${cl.type}`;
      if (seen.has(key)) ctx.addIssue({ code: "custom", path: ["clips", i], message: `duplicate ${cl.type} clip for track ${cl.trackId}` });
      seen.add(key);
    });
  });

ingestRoutes.post("/clips", async (c) => {
  const env = c.env;
  const d = db(env);
  const body = parse(clipsBody, await readJson(c));
  await requireOpenJob(d, body.jobId, ["cut", "recut"]);

  const trackIds = [...new Set(body.clips.map((cl) => cl.trackId))];
  const [trackRows, clipRows] = await d.batch([
    d.select({ id: tracks.id }).from(tracks).where(inArray(tracks.id, trackIds)),
    d.select().from(clips).where(inArray(clips.trackId, trackIds)),
  ]);
  const found = new Set(trackRows.map((t) => t.id));
  const missing = trackIds.filter((id) => !found.has(id));
  if (missing.length > 0) {
    // Nothing has been written yet, so the whole request is rejected cleanly.
    throw new ApiError(404, "track_not_found", `Unknown trackId(s): ${missing.join(", ")}`);
  }

  const existing = new Map(clipRows.map((cl) => [`${cl.trackId}:${cl.type}`, cl]));
  const outcomes = new Map<string, "created" | "updated" | "skipped">();
  const statements: Prepared[] = [];
  for (const cl of body.clips) {
    const key = `${cl.trackId}:${cl.type}`;
    const prev = existing.get(key);
    const unchanged =
      prev &&
      prev.status === "ready" &&
      prev.startMs === cl.startMs &&
      prev.lengthMs === cl.lengthMs &&
      prev.r2Key === cl.r2Key &&
      prev.sha256 === cl.sha256 &&
      prev.bytes === cl.bytes;
    outcomes.set(key, !prev ? "created" : unchanged ? "skipped" : "updated");
    if (unchanged) continue;
    const { trackId, type, startMs, lengthMs, r2Key, sha256, bytes } = cl;
    statements.push(
      fromQuery(
        env,
        d
          .insert(clips)
          .values({ trackId, type, startMs, lengthMs, r2Key, sha256, bytes, version: 1, status: "ready" })
          .onConflictDoUpdate({
            target: [clips.trackId, clips.type],
            set: { startMs, lengthMs, r2Key, sha256, bytes, status: "ready", version: sql`${clips.version} + 1` },
          }),
      ),
    );
  }
  await runBatched(env, statements);

  const after = await d.select().from(clips).where(inArray(clips.trackId, trackIds));
  const afterByKey = new Map(after.map((cl) => [`${cl.trackId}:${cl.type}`, cl]));
  const results = body.clips.map((cl) => {
    const key = `${cl.trackId}:${cl.type}`;
    const row = afterByKey.get(key);
    return { trackId: cl.trackId, type: cl.type, clipId: row?.id ?? null, version: row?.version ?? null, result: outcomes.get(key)! };
  });
  const counts = { created: 0, updated: 0, skipped: 0 };
  for (const r of results) counts[r.result]++;
  return c.json({ jobId: body.jobId, counts, results });
});

// ------------------------------------------------------------- job status

const jobStatusBody = z.strictObject({
  status: z.enum(INGEST_STATUSES),
  ghRunUrl: z.url().max(500).optional(),
  summary: z
    .record(z.string(), z.unknown())
    .refine((s) => JSON.stringify(s).length <= 20_000, "summary is too large (max 20,000 characters)")
    .optional(),
});

const STATUS_ORDER = { queued: 0, running: 1, succeeded: 2, failed: 2 } as const;

ingestRoutes.post("/jobs/:id/status", async (c) => {
  const d = db(c.env);
  const id = idParam(c);
  const body = parse(jobStatusBody, await readJson(c));
  const job = await d.select().from(ingestJobs).where(eq(ingestJobs.id, id)).get();
  if (!job) throw new ApiError(404, "job_not_found", `Ingest job ${id} not found`);

  const finished = job.status === "succeeded" || job.status === "failed";
  if (finished) {
    // A retried final report is fine; anything else on a finished job is not.
    if (body.status === job.status) return c.json({ job });
    throw new ApiError(409, "job_finished", `Job ${id} already ${job.status}`);
  }
  if (STATUS_ORDER[body.status] < STATUS_ORDER[job.status]) {
    throw new ApiError(409, "invalid_transition", `Cannot move a job from ${job.status} back to ${body.status}`);
  }

  const now = Date.now();
  const set: Partial<typeof ingestJobs.$inferInsert> = { status: body.status };
  if (body.ghRunUrl !== undefined) set.ghRunUrl = body.ghRunUrl;
  if (body.summary !== undefined) set.summaryJson = JSON.stringify(body.summary);
  if (body.status !== "queued" && job.startedAt == null) set.startedAt = now;
  if (STATUS_ORDER[body.status] === 2) set.finishedAt = now;

  const [updated] = await d.update(ingestJobs).set(set).where(eq(ingestJobs.id, id)).returning();
  return c.json({ job: updated });
});

// --------------------------------------------------------------- snapshot

/** Compact catalog for client-side dedupe. Rows are positional arrays; `columns` names them. */
ingestRoutes.get("/catalog-snapshot", async (c) => {
  const d = db(c.env);
  const [artistRows, aliasRows, trackRows] = await d.batch([
    d.select({ id: artists.id, nameAm: artists.nameAm }).from(artists).orderBy(artists.id),
    d.select({ artistId: artistAliases.artistId, aliasNorm: artistAliases.aliasNorm }).from(artistAliases).orderBy(artistAliases.artistId),
    d
      .select({ id: tracks.id, artistId: tracks.artistId, titleAm: tracks.titleAm, titleLatin: tracks.titleLatin, durationMs: tracks.durationMs })
      .from(tracks)
      .orderBy(tracks.id),
  ]);
  const aliasesByArtist = new Map<number, string[]>();
  for (const a of aliasRows) aliasesByArtist.set(a.artistId, [...(aliasesByArtist.get(a.artistId) ?? []), a.aliasNorm]);

  c.header("Cache-Control", "no-store");
  return c.json({
    generatedAt: Date.now(),
    columns: {
      artists: ["id", "name_am", "alias_norms"],
      tracks: ["id", "artist_id", "title_am", "title_latin", "duration_ms"],
    },
    artists: artistRows.map((a) => [a.id, a.nameAm, aliasesByArtist.get(a.id) ?? []]),
    tracks: trackRows.map((t) => [t.id, t.artistId, t.titleAm, t.titleLatin, t.durationMs]),
  });
});
