// Pack building: which tracks may go into a pack, and publishing a new immutable version of it.
//
// Query budget: a publish costs a fixed handful of D1 statements however many tracks the pack holds (the
// eligible tracks come back in one query and `pack_tracks` is written from one JSON array with json_each).
import type { Bindings } from "../env";
import { isUniqueViolation } from "./dbErrors";
import { ApiError } from "./errors";
import { manifestKey, MANIFEST_SCHEMA_VERSION, packManifest, type PackManifest } from "./packManifest";

export type PackRow = {
  id: number;
  slug: string;
  name_am: string;
  name_en: string;
  generation_id: number | null;
  genre_id: number | null;
  current_version: number | null;
};

export async function requirePack(env: Bindings, id: number): Promise<PackRow> {
  const pack = await env.DB.prepare("SELECT * FROM packs WHERE id = ?1").bind(id).first<PackRow>();
  if (!pack) throw new ApiError(404, "not_found", `Pack ${id} not found`);
  return pack;
}

type EligibleRow = {
  id: number;
  title_am: string | null;
  title_latin: string | null;
  release_year: number | null;
  generation_id: number | null;
  artist_id: number;
  artist_am: string;
  artist_latin: string | null;
  genre_ids: string;
  intro_id: number;
  intro_key: string;
  intro_sha: string;
  intro_bytes: number;
  intro_len: number;
  middle_id: number;
  middle_key: string;
  middle_sha: string;
  middle_bytes: number;
  middle_len: number;
};

// ?1 generation filter, ?2 genre filter, ?3 optional JSON array of track ids to restrict to (NULL: all).
// A track is eligible when it is approved and both clips are ready with a file, checksum and size.
const ELIGIBLE_FROM = `
  FROM tracks t
  JOIN artists a ON a.id = t.artist_id
  JOIN clips ci ON ci.track_id = t.id AND ci.type = 'intro' AND ci.status = 'ready'
       AND ci.r2_key IS NOT NULL AND ci.sha256 IS NOT NULL AND ci.bytes IS NOT NULL
  JOIN clips cm ON cm.track_id = t.id AND cm.type = 'middle' AND cm.status = 'ready'
       AND cm.r2_key IS NOT NULL AND cm.sha256 IS NOT NULL AND cm.bytes IS NOT NULL
  WHERE t.status = 'approved'
    AND (?1 IS NULL OR t.generation_id = ?1)
    AND (?2 IS NULL OR EXISTS (SELECT 1 FROM track_genres g WHERE g.track_id = t.id AND g.genre_id = ?2))
    AND (?3 IS NULL OR t.id IN (SELECT value FROM json_each(?3)))`;

const ELIGIBLE_ROWS = `
  SELECT t.id, t.title_am, t.title_latin, t.release_year, t.generation_id,
         a.id AS artist_id, a.name_am AS artist_am, a.name_latin AS artist_latin,
         (SELECT json_group_array(genre_id) FROM (SELECT genre_id FROM track_genres WHERE track_id = t.id ORDER BY genre_id)) AS genre_ids,
         ci.id AS intro_id, ci.r2_key AS intro_key, ci.sha256 AS intro_sha, ci.bytes AS intro_bytes, ci.length_ms AS intro_len,
         cm.id AS middle_id, cm.r2_key AS middle_key, cm.sha256 AS middle_sha, cm.bytes AS middle_bytes, cm.length_ms AS middle_len
  ${ELIGIBLE_FROM}
  ORDER BY t.id`;

export async function eligibleTracks(env: Bindings, pack: PackRow, trackIds?: number[]): Promise<EligibleRow[]> {
  const ids = trackIds ? JSON.stringify(trackIds) : null;
  const { results } = await env.DB.prepare(ELIGIBLE_ROWS).bind(pack.generation_id, pack.genre_id, ids).all<EligibleRow>();
  return results;
}

/** Tracks that would go into a new default version, vs what the current version holds. */
export async function diffAgainstCurrent(env: Bindings, pack: PackRow) {
  const [eligible, current] = await Promise.all([
    eligibleTracks(env, pack),
    pack.current_version === null
      ? Promise.resolve({ results: [] as { id: number; title_am: string | null; title_latin: string | null }[] })
      : env.DB.prepare(
          `SELECT t.id, t.title_am, t.title_latin FROM pack_tracks pt
             JOIN pack_versions pv ON pv.id = pt.pack_version_id AND pv.pack_id = ?1 AND pv.version = ?2
             JOIN tracks t ON t.id = pt.track_id ORDER BY t.id`,
        )
          .bind(pack.id, pack.current_version)
          .all<{ id: number; title_am: string | null; title_latin: string | null }>(),
  ]);
  const inCurrent = new Set(current.results.map((r) => r.id));
  const inNext = new Set(eligible.map((r) => r.id));
  const brief = (r: { id: number; title_am: string | null; title_latin: string | null }) => ({ id: r.id, titleAm: r.title_am, titleLatin: r.title_latin });
  return {
    currentVersion: pack.current_version,
    eligibleCount: eligible.length,
    added: eligible.filter((r) => !inCurrent.has(r.id)).map(brief),
    removed: current.results.filter((r) => !inNext.has(r.id)).map(brief),
  };
}

const cdnUrl = (env: Bindings, key: string) => `${env.CDN_BASE_URL.replace(/\/+$/, "")}/${key}`;

export function buildManifest(env: Bindings, pack: PackRow, version: number, rows: EligibleRow[], now: number): PackManifest {
  const tracks = rows.map((r) => ({
    id: r.id,
    titleAm: r.title_am,
    titleLatin: r.title_latin,
    artistId: r.artist_id,
    artistAm: r.artist_am,
    artistLatin: r.artist_latin,
    generationId: r.generation_id,
    genreIds: JSON.parse(r.genre_ids ?? "[]") as number[],
    releaseYear: r.release_year,
    clips: {
      intro: { url: cdnUrl(env, r.intro_key), sha256: r.intro_sha, bytes: r.intro_bytes, lengthMs: r.intro_len },
      middle: { url: cdnUrl(env, r.middle_key), sha256: r.middle_sha, bytes: r.middle_bytes, lengthMs: r.middle_len },
    },
  }));
  return {
    schema: MANIFEST_SCHEMA_VERSION,
    slug: pack.slug,
    version,
    publishedAt: now,
    names: { am: pack.name_am, en: pack.name_en },
    generationId: pack.generation_id,
    genreId: pack.genre_id,
    tracks,
    totalBytes: tracks.reduce((n, t) => n + t.clips.intro.bytes + t.clips.middle.bytes, 0),
  };
}

const MAX_VERSION_ATTEMPTS = 5;

/**
 * Publish the next version of a pack: check every track is eligible, write the manifest (create-only, so no
 * existing version's manifest is ever replaced), then record the version and move `current_version` in one batch.
 * A manifest left behind by a publish that died before the batch is skipped over, not overwritten.
 */
export async function publishVersion(env: Bindings, pack: PackRow, trackIds: number[] | undefined, publishedBy: string | null) {
  const rows = await eligibleTracks(env, pack, trackIds);
  if (trackIds) {
    const ok = new Set(rows.map((r) => r.id));
    const bad = [...new Set(trackIds)].filter((id) => !ok.has(id));
    if (bad.length > 0) {
      throw new ApiError(409, "tracks_not_eligible", `Not approved with both clips ready, or outside this pack's filter: ${bad.join(", ")}`);
    }
  }
  if (rows.length === 0) throw new ApiError(409, "no_eligible_tracks", "No approved tracks with both clips ready match this pack");

  const latest = await env.DB.prepare("SELECT COALESCE(MAX(version), 0) AS v FROM pack_versions WHERE pack_id = ?1").bind(pack.id).first<{ v: number }>();
  const now = Date.now();
  for (let version = (latest?.v ?? 0) + 1, attempt = 0; attempt < MAX_VERSION_ATTEMPTS; version++, attempt++) {
    const manifest = packManifest.parse(buildManifest(env, pack, version, rows, now));
    const key = manifestKey(pack.slug, version);
    const written = await env.CLIPS.put(key, JSON.stringify(manifest), {
      httpMetadata: { contentType: "application/json", cacheControl: "public, max-age=31536000, immutable" },
      onlyIf: { etagDoesNotMatch: "*" },
    });
    if (written === null) continue; // a manifest is already there: never touch it, try the next number

    const members = JSON.stringify(rows.map((r) => ({ t: r.id, i: r.intro_id, m: r.middle_id })));
    try {
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO pack_versions (pack_id, version, manifest_key, track_count, total_bytes, published_at, published_by)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
        ).bind(pack.id, version, key, manifest.tracks.length, manifest.totalBytes, now, publishedBy),
        env.DB.prepare(
          `INSERT INTO pack_tracks (pack_version_id, track_id, intro_clip_id, middle_clip_id)
           SELECT pv.id, json_extract(j.value, '$.t'), json_extract(j.value, '$.i'), json_extract(j.value, '$.m')
             FROM json_each(?3) j JOIN pack_versions pv ON pv.pack_id = ?1 AND pv.version = ?2`,
        ).bind(pack.id, version, members),
        env.DB.prepare("UPDATE packs SET current_version = ?2 WHERE id = ?1").bind(pack.id, version),
      ]);
    } catch (err) {
      if (isUniqueViolation(err)) throw new ApiError(409, "version_conflict", "Another publish took this version number; try again");
      throw err;
    }
    return { version, manifestUrl: cdnUrl(env, key), trackCount: manifest.tracks.length, totalBytes: manifest.totalBytes, publishedAt: now };
  }
  throw new ApiError(409, "version_conflict", "Could not find a free version number; try again");
}
