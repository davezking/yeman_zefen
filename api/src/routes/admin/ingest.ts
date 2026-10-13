// Ingest API for GitHub Actions (service-token auth, mounted under /admin/ingest).
// Spec: docs/phase-1-sprint-1-prompts.md "Ingest API" and docs/architecture.md §3, §5.
//
// Design notes
// - QUERY BUDGET: Cloudflare's Free plan allows 50 D1 queries per Worker invocation, and every
//   statement inside a batch() counts. So the number of statements per request must NOT grow with
//   the number of records. Each request sends its records to D1 as ONE JSON bound parameter and
//   expands it with json_each() in set-based INSERT/UPDATE ... SELECT statements. A tracks request
//   costs at most ~16 queries (and clips ~5) whether it carries 1 record or 100.
//   test/queryBudget.test.ts pins this.
// - Re-sending the same request is a no-op: tracks upsert on source_url, aliases and genre links
//   are INSERT-OR-IGNORE / ON CONFLICT DO NOTHING, review items are skipped when an identical open
//   one exists, and clips are only rewritten (and version-bumped) when something actually changed.
// - Reads happen up front in one batch so the response can say created | updated | skipped.
import { eq } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db } from "../../db/client";
import { artistAliases, artists, CLIP_TYPES, INGEST_KINDS, INGEST_STATUSES, ingestJobs, REVIEW_REASONS, tracks } from "../../db/schema";
import type { AppEnv, Bindings } from "../../env";
import { ApiError } from "../../lib/errors";
import { normalizeAlias, normalizeFidel } from "../../lib/normalize";
import { idParam, parse, readJson } from "../../lib/validate";

export const MAX_BATCH = 100;
/** A JSON payload bound as a single parameter must stay far below D1's 2 MB value limit. */
const MAX_PAYLOAD_BYTES = 1_000_000;

export const ingestRoutes = new Hono<AppEnv>();

// ---------------------------------------------------------------- helpers

type Prepared = D1PreparedStatement;
type Row = Record<string, unknown>;

/** One D1 round trip. Every statement in it counts toward the Free plan's per-request query cap. */
function runBatch(env: Bindings, statements: Prepared[]) {
  return env.DB.batch<Row>(statements);
}

/** JSON with sorted keys, so "identical details" compares equal regardless of key order. */
function stableJson(value: unknown): string {
  return JSON.stringify(value, (_k, v: unknown) =>
    v && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)))
      : v,
  );
}

function payloadOrThrow(value: unknown): string {
  const json = JSON.stringify(value);
  if (new TextEncoder().encode(json).length > MAX_PAYLOAD_BYTES) {
    throw new ApiError(413, "payload_too_large", "Request is too large; send fewer records per request");
  }
  return json;
}

type JobRow = { id: number; kind: (typeof INGEST_KINDS)[number]; status: (typeof INGEST_STATUSES)[number] };

const JOB_SQL = "SELECT id, kind, status FROM ingest_jobs WHERE id = ?1";

function assertJobOpen(job: JobRow | undefined, id: number, kinds: readonly JobRow["kind"][]) {
  if (!job) throw new ApiError(404, "job_not_found", `Ingest job ${id} not found`);
  if (!kinds.includes(job.kind)) {
    throw new ApiError(409, "job_kind_mismatch", `Job ${id} is a '${job.kind}' job; this endpoint takes ${kinds.join(" or ")} jobs`);
  }
  if (job.status === "succeeded" || job.status === "failed") {
    throw new ApiError(409, "job_finished", `Job ${id} already ${job.status}`);
  }
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
type ScrapedField = (typeof SCRAPED_FIELDS)[number];

/** camelCase scraped field -> tracks column. */
const COLUMN: Record<ScrapedField, string> = {
  titleAm: "title_am",
  titleLatin: "title_latin",
  album: "album",
  releaseYear: "release_year",
  artistId: "artist_id",
  durationMs: "duration_ms",
  sourceAudioKey: "source_audio_key",
};

type TrackRow = {
  id: number;
  source_url: string;
  artist_id: number;
  title_am: string | null;
  title_latin: string | null;
  album: string | null;
  release_year: number | null;
  duration_ms: number | null;
  source_audio_key: string | null;
  status: string;
  admin_edited_fields: string;
};

// --- SQL fragments. ?1 is the JSON payload, ?2 is "now".

/** True when an admin has edited `field` on `tracks` (re-scrapes must leave it alone). */
const adminEdited = (field: string) =>
  `EXISTS (SELECT 1 FROM json_each(tracks.admin_edited_fields) e WHERE e.value = '${field}')`;

/** A scraped value should replace the stored one: present, different, and not admin-edited. */
const shouldReplace = (field: ScrapedField) => {
  const col = COLUMN[field];
  return `(n.${col} IS NOT NULL AND n.${col} IS NOT tracks.${col} AND NOT ${adminEdited(field)})`;
};

const UPDATE_EXISTING_TRACKS_SQL = `
  UPDATE tracks SET
    ${SCRAPED_FIELDS.map((f) => `${COLUMN[f]} = CASE WHEN ${shouldReplace(f)} THEN n.${COLUMN[f]} ELSE tracks.${COLUMN[f]} END`).join(",\n    ")},
    updated_at = ?2
  FROM (
    SELECT json_extract(t.value, '$.url') AS url,
      ${SCRAPED_FIELDS.map((f) => `json_extract(t.value, '$.${f}') AS ${COLUMN[f]}`).join(",\n      ")}
    FROM json_each(?1, '$.tracks') t
  ) n
  WHERE tracks.source_url = n.url
    AND (${SCRAPED_FIELDS.map(shouldReplace).join("\n      OR ")})`;

const INSERT_NEW_TRACKS_SQL = `
  INSERT INTO tracks (artist_id, title_am, title_latin, album, release_year, source_url,
                      source_audio_key, duration_ms, status, created_at, updated_at)
  SELECT json_extract(t.value, '$.artistId'), json_extract(t.value, '$.titleAm'),
         json_extract(t.value, '$.titleLatin'), json_extract(t.value, '$.album'),
         json_extract(t.value, '$.releaseYear'), json_extract(t.value, '$.url'),
         json_extract(t.value, '$.sourceAudioKey'), json_extract(t.value, '$.durationMs'),
         json_extract(t.value, '$.newStatus'), ?2, ?2
  FROM json_each(?1, '$.tracks') t
  WHERE true
  ON CONFLICT(source_url) DO NOTHING`;

const INSERT_ALIASES_SQL = `
  INSERT INTO artist_aliases (artist_id, alias, alias_norm, source)
  SELECT json_extract(a.value, '$.id'), json_extract(al.value, '$.alias'),
         json_extract(al.value, '$.norm'), 'scraper'
  FROM json_each(?1, '$.artists') a, json_each(a.value, '$.aliases') al
  WHERE true
  ON CONFLICT(alias_norm) DO NOTHING`;

const FILL_LATIN_NAMES_SQL = `
  UPDATE artists SET name_latin = n.latin, updated_at = ?2
  FROM (SELECT json_extract(a.value, '$.id') AS id, json_extract(a.value, '$.latin') AS latin
        FROM json_each(?1, '$.artists') a) n
  WHERE artists.id = n.id AND artists.name_latin IS NULL AND n.latin IS NOT NULL`;

const LINK_GENRES_SQL = `
  INSERT OR IGNORE INTO track_genres (track_id, genre_id)
  SELECT t.id, g.value
  FROM json_each(?1, '$.tracks') j, json_each(j.value, '$.genreIds') g
  JOIN tracks t ON t.source_url = json_extract(j.value, '$.url')
  WHERE true`;

const INSERT_REVIEW_ITEMS_SQL = `
  INSERT INTO review_items (entity_type, entity_id, reason, details_json, status)
  SELECT 'track', t.id, json_extract(f.value, '$.reason'), json_extract(f.value, '$.details'), 'open'
  FROM json_each(?1, '$.tracks') j, json_each(j.value, '$.flags') f
  JOIN tracks t ON t.source_url = json_extract(j.value, '$.url')
  WHERE NOT EXISTS (
    SELECT 1 FROM review_items r
    WHERE r.entity_type = 'track' AND r.entity_id = t.id AND r.status = 'open'
      AND r.reason = json_extract(f.value, '$.reason')
      AND r.details_json IS json_extract(f.value, '$.details'))`;

/** A track that was ingested clean but just got flagged needs a human look. */
const BUMP_STATUS_SQL = `
  UPDATE tracks SET status = 'needs_review', updated_at = ?2
  WHERE status = 'ingested' AND source_url IN (
    SELECT json_extract(j.value, '$.url') FROM json_each(?1, '$.tracks') j
    WHERE json_array_length(j.value, '$.flags') > 0)`;

ingestRoutes.post("/tracks", async (c) => {
  const env = c.env;
  const body = parse(tracksBody, await readJson(c));
  const now = Date.now();

  const recs = body.tracks.map((t) => ({ ...t, artistKey: normalizeFidel(t.artistAm) }));
  const urlsJson = JSON.stringify(recs.map((r) => r.sourceUrl));
  const keys = [...new Set(recs.map((r) => r.artistKey))];

  // ---- Batch 1: every read this request needs (6 queries).
  const [jobRes, trackRes, artistRes, genreRes, linkRes, openRes] = await runBatch(env, [
    env.DB.prepare(JOB_SQL).bind(body.jobId),
    env.DB.prepare(
      `SELECT id, source_url, artist_id, title_am, title_latin, album, release_year, duration_ms,
              source_audio_key, status, admin_edited_fields
       FROM tracks WHERE source_url IN (SELECT value FROM json_each(?1))`,
    ).bind(urlsJson),
    // A key is a known artist if it is an alias (the canonical name is stored as one) or a name_am.
    env.DB.prepare(
      `SELECT alias_norm AS k, artist_id AS id FROM artist_aliases WHERE alias_norm IN (SELECT value FROM json_each(?1))
       UNION ALL
       SELECT name_am, id FROM artists WHERE name_am IN (SELECT value FROM json_each(?1))`,
    ).bind(JSON.stringify(keys)),
    env.DB.prepare("SELECT id, slug FROM genres"),
    env.DB.prepare(
      `SELECT track_id, genre_id FROM track_genres
       WHERE track_id IN (SELECT id FROM tracks WHERE source_url IN (SELECT value FROM json_each(?1)))`,
    ).bind(urlsJson),
    env.DB.prepare(
      `SELECT entity_id, reason, details_json FROM review_items
       WHERE entity_type = 'track' AND status = 'open'
         AND entity_id IN (SELECT id FROM tracks WHERE source_url IN (SELECT value FROM json_each(?1)))`,
    ).bind(urlsJson),
  ]);
  assertJobOpen((jobRes!.results as unknown as JobRow[])[0], body.jobId, ["scrape"]);

  // ---- Artists: match by normalized name_am (alias first, then name_am itself).
  const artistIdByKey = new Map<string, number>();
  for (const r of artistRes!.results as { k: string; id: number }[]) if (!artistIdByKey.has(r.k)) artistIdByKey.set(r.k, r.id);

  const groups = new Map<string, typeof recs>();
  for (const r of recs) groups.set(r.artistKey, [...(groups.get(r.artistKey) ?? []), r]);
  const firstLatin = (key: string) => groups.get(key)!.find((r) => r.artistLatin)?.artistLatin ?? null;

  // ---- Batch 2 (only when there are brand-new artists): create them and read their ids (3 queries).
  const newKeys = keys.filter((k) => !artistIdByKey.has(k));
  if (newKeys.length > 0) {
    const newArtistsJson = JSON.stringify(newKeys.map((key) => ({ key, latin: firstLatin(key) })));
    const [, , idRes] = await runBatch(env, [
      env.DB.prepare(
        `INSERT INTO artists (name_am, name_latin, created_at, updated_at)
         SELECT json_extract(a.value, '$.key'), json_extract(a.value, '$.latin'), ?2, ?2
         FROM json_each(?1) a WHERE true ON CONFLICT(name_am) DO NOTHING`,
      ).bind(newArtistsJson, now),
      // The canonical name is also an alias, so future folding of name_am keeps matching it.
      env.DB.prepare(
        `INSERT INTO artist_aliases (artist_id, alias, alias_norm, source)
         SELECT x.id, k.key, k.key, 'canonical'
         FROM (SELECT json_extract(a.value, '$.key') AS key FROM json_each(?1) a) k
         JOIN artists x ON x.name_am = k.key
         WHERE true ON CONFLICT(alias_norm) DO NOTHING`,
      ).bind(newArtistsJson),
      env.DB.prepare("SELECT id, name_am FROM artists WHERE name_am IN (SELECT json_extract(value, '$.key') FROM json_each(?1))").bind(newArtistsJson),
    ]);
    for (const r of idRes!.results as { id: number; name_am: string }[]) artistIdByKey.set(r.name_am, r.id);
  }
  for (const key of keys) {
    if (!artistIdByKey.has(key)) throw new ApiError(500, "internal", `Could not resolve artist for '${key}'`);
  }

  // ---- Work out, in memory, what each record will do (also drives the response).
  const existingByUrl = new Map((trackRes!.results as unknown as TrackRow[]).map((t) => [t.source_url, t]));
  const genreIdBySlug = new Map((genreRes!.results as { id: number; slug: string }[]).map((g) => [g.slug, g.id]));
  const linksByTrack = new Map<number, Set<number>>();
  for (const l of linkRes!.results as { track_id: number; genre_id: number }[]) {
    linksByTrack.set(l.track_id, (linksByTrack.get(l.track_id) ?? new Set()).add(l.genre_id));
  }
  const openByTrack = new Map<number, Set<string>>();
  for (const o of openRes!.results as { entity_id: number; reason: string; details_json: string | null }[]) {
    openByTrack.set(o.entity_id, (openByTrack.get(o.entity_id) ?? new Set()).add(`${o.reason}|${o.details_json ?? ""}`));
  }

  type Result = { sourceUrl: string; trackId: number | null; result: "created" | "updated" | "skipped"; unknownGenres?: string[] };
  const results: Result[] = [];
  const payloadTracks: Row[] = [];
  let anyNew = false;
  let anyExisting = false;
  let anyGenre = false;
  let anyFlag = false;

  for (const rec of recs) {
    const artistId = artistIdByKey.get(rec.artistKey)!;
    const uniqueGenres = [...new Set(rec.genres)];
    const genreIds = uniqueGenres.filter((g) => genreIdBySlug.has(g)).map((g) => genreIdBySlug.get(g)!);
    const unknownGenres = uniqueGenres.filter((g) => !genreIdBySlug.has(g));
    const flagItems = new Map<string, { reason: string; details: string | null }>();
    for (const f of rec.flags) {
      const details = f.details ? stableJson(f.details) : null;
      flagItems.set(`${f.reason}|${details ?? ""}`, { reason: f.reason, details });
    }
    if (genreIds.length > 0) anyGenre = true;
    if (flagItems.size > 0) anyFlag = true;

    const existing = existingByUrl.get(rec.sourceUrl);
    let outcome: Result["result"];
    if (!existing) {
      outcome = "created";
      anyNew = true;
    } else {
      anyExisting = true;
      const edited = new Set<string>(JSON.parse(existing.admin_edited_fields) as string[]);
      const incoming: Record<ScrapedField, unknown> = {
        titleAm: rec.titleAm, titleLatin: rec.titleLatin, album: rec.album, releaseYear: rec.releaseYear,
        artistId, durationMs: rec.durationMs, sourceAudioKey: rec.sourceAudioKey,
      };
      // Mirrors shouldReplace() in SQL: present, different, and not admin-edited.
      const changed = SCRAPED_FIELDS.some(
        (f) => incoming[f] !== null && !edited.has(f) && existing[COLUMN[f] as keyof TrackRow] !== incoming[f],
      );
      const links = linksByTrack.get(existing.id);
      const newGenres = genreIds.some((g) => !links?.has(g));
      const open = openByTrack.get(existing.id);
      const newFlags = [...flagItems.keys()].some((k) => !open?.has(k));
      outcome = changed || newGenres || newFlags ? "updated" : "skipped";
    }

    payloadTracks.push({
      url: rec.sourceUrl, artistId, titleAm: rec.titleAm, titleLatin: rec.titleLatin, album: rec.album,
      releaseYear: rec.releaseYear, durationMs: rec.durationMs, sourceAudioKey: rec.sourceAudioKey,
      newStatus: flagItems.size > 0 ? "needs_review" : "ingested",
      genreIds, flags: [...flagItems.values()],
    });
    results.push({
      sourceUrl: rec.sourceUrl,
      trackId: existing?.id ?? null,
      result: outcome,
      ...(unknownGenres.length > 0 ? { unknownGenres } : {}),
    });
  }

  const payloadArtists = keys.map((key) => {
    const byNorm = new Map<string, string>();
    for (const r of groups.get(key)!) {
      for (const alias of [...r.artistAliases, ...(r.artistLatin ? [r.artistLatin] : [])]) {
        const norm = normalizeAlias(alias);
        if (norm) byNorm.set(norm, alias);
      }
    }
    return {
      id: artistIdByKey.get(key)!,
      latin: newKeys.includes(key) ? null : firstLatin(key), // new artists were created with it
      aliases: [...byNorm].map(([norm, alias]) => ({ alias, norm })),
    };
  });

  // ---- Batch 3: all writes, set-based (at most 8 statements, whatever the number of records).
  const payload = payloadOrThrow({ artists: payloadArtists, tracks: payloadTracks });
  const writes: Prepared[] = [];
  // D1 insists on exactly as many bound values as the highest ?N in the statement.
  const withPayload = (sqlText: string) => {
    const highest = Math.max(...[...sqlText.matchAll(/\?(\d+)/g)].map((m) => Number(m[1])));
    return env.DB.prepare(sqlText).bind(...[payload, now].slice(0, highest));
  };
  if (payloadArtists.some((a) => a.aliases.length > 0)) writes.push(withPayload(INSERT_ALIASES_SQL));
  if (payloadArtists.some((a) => a.latin)) writes.push(withPayload(FILL_LATIN_NAMES_SQL));
  if (anyNew) writes.push(withPayload(INSERT_NEW_TRACKS_SQL));
  if (anyExisting) writes.push(withPayload(UPDATE_EXISTING_TRACKS_SQL));
  if (anyGenre) writes.push(withPayload(LINK_GENRES_SQL));
  if (anyFlag) writes.push(withPayload(INSERT_REVIEW_ITEMS_SQL), withPayload(BUMP_STATUS_SQL));
  const idStatement = env.DB.prepare(
    "SELECT id, source_url FROM tracks WHERE source_url IN (SELECT value FROM json_each(?1))",
  ).bind(JSON.stringify(results.filter((r) => r.result === "created").map((r) => r.sourceUrl)));
  writes.push(idStatement);
  const written = await runBatch(env, writes);

  const createdIds = new Map((written[written.length - 1]!.results as { id: number; source_url: string }[]).map((r) => [r.source_url, r.id]));
  for (const r of results) if (r.result === "created") r.trackId = createdIds.get(r.sourceUrl) ?? null;

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

// Idempotent upsert: an existing clip is only rewritten (and its version bumped) when something
// about it differs, so a retried request changes nothing.
const UPSERT_CLIPS_SQL = `
  INSERT INTO clips (track_id, type, start_ms, length_ms, r2_key, sha256, bytes, version, status)
  SELECT json_extract(c.value, '$.trackId'), json_extract(c.value, '$.type'),
         json_extract(c.value, '$.startMs'), json_extract(c.value, '$.lengthMs'),
         json_extract(c.value, '$.r2Key'), json_extract(c.value, '$.sha256'),
         json_extract(c.value, '$.bytes'), 1, 'ready'
  FROM json_each(?1) c
  WHERE true
  ON CONFLICT(track_id, type) DO UPDATE SET
    start_ms = excluded.start_ms, length_ms = excluded.length_ms, r2_key = excluded.r2_key,
    sha256 = excluded.sha256, bytes = excluded.bytes, status = 'ready', version = clips.version + 1
  WHERE clips.status <> 'ready' OR clips.start_ms IS NOT excluded.start_ms
     OR clips.length_ms IS NOT excluded.length_ms OR clips.r2_key IS NOT excluded.r2_key
     OR clips.sha256 IS NOT excluded.sha256 OR clips.bytes IS NOT excluded.bytes`;

type ClipRow = {
  id: number; track_id: number; type: string; start_ms: number; length_ms: number;
  r2_key: string | null; sha256: string | null; bytes: number | null; version: number; status: string;
};

ingestRoutes.post("/clips", async (c) => {
  const env = c.env;
  const body = parse(clipsBody, await readJson(c));
  const payload = payloadOrThrow(body.clips);
  const trackIdsJson = JSON.stringify([...new Set(body.clips.map((cl) => cl.trackId))]);
  const inTrackIds = "IN (SELECT value FROM json_each(?1))";

  // ---- Batch 1: reads (3 queries).
  const [jobRes, trackRes, clipRes] = await runBatch(env, [
    env.DB.prepare(JOB_SQL).bind(body.jobId),
    env.DB.prepare(`SELECT id FROM tracks WHERE id ${inTrackIds}`).bind(trackIdsJson),
    env.DB.prepare(
      `SELECT id, track_id, type, start_ms, length_ms, r2_key, sha256, bytes, version, status FROM clips WHERE track_id ${inTrackIds}`,
    ).bind(trackIdsJson),
  ]);
  assertJobOpen((jobRes!.results as unknown as JobRow[])[0], body.jobId, ["cut", "recut"]);

  const found = new Set((trackRes!.results as { id: number }[]).map((t) => t.id));
  const missing = [...new Set(body.clips.map((cl) => cl.trackId))].filter((id) => !found.has(id));
  if (missing.length > 0) {
    // Nothing has been written yet, so the whole request is rejected cleanly.
    throw new ApiError(404, "track_not_found", `Unknown trackId(s): ${missing.join(", ")}`);
  }

  const existing = new Map((clipRes!.results as unknown as ClipRow[]).map((cl) => [`${cl.track_id}:${cl.type}`, cl]));
  const outcomes = new Map<string, "created" | "updated" | "skipped">();
  for (const cl of body.clips) {
    const prev = existing.get(`${cl.trackId}:${cl.type}`);
    const unchanged =
      prev !== undefined &&
      prev.status === "ready" &&
      prev.start_ms === cl.startMs &&
      prev.length_ms === cl.lengthMs &&
      prev.r2_key === cl.r2Key &&
      prev.sha256 === cl.sha256 &&
      prev.bytes === cl.bytes;
    outcomes.set(`${cl.trackId}:${cl.type}`, !prev ? "created" : unchanged ? "skipped" : "updated");
  }

  // ---- Batch 2: one set-based upsert, then read back ids and versions (2 queries).
  const [, afterRes] = await runBatch(env, [
    env.DB.prepare(UPSERT_CLIPS_SQL).bind(payload),
    env.DB.prepare(`SELECT id, track_id, type, version FROM clips WHERE track_id ${inTrackIds}`).bind(trackIdsJson),
  ]);
  const afterByKey = new Map(
    (afterRes!.results as { id: number; track_id: number; type: string; version: number }[]).map((cl) => [`${cl.track_id}:${cl.type}`, cl]),
  );
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
