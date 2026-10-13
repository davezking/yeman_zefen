# Ingest API (`/admin/ingest/*`)

Used by the GitHub Actions pipeline. Every route requires the Cloudflare Access
**service token** (see `docs/ops.md`); human admin tokens get 403. Errors use the
usual `{ error: { code, message } }` shape. Code: `api/src/routes/admin/ingest.ts`.

All write endpoints take a `jobId` (or have it in the path) for an `ingest_jobs`
row. Tracks need a `scrape` job; clips need a `cut` or `recut` job. A missing job is
404, the wrong kind or an already finished job is 409.

## `POST /admin/ingest/tracks`

Up to 100 records per request. Unknown fields are rejected (400).

```json
{ "jobId": 7,
  "tracks": [{
    "sourceUrl": "https://ethiozeima.com/2014/11/02/some-slug/",
    "titleAm": "ትዝታ", "titleLatin": "Tizita",
    "artistAm": "ጥላሁን ገሠሠ", "artistLatin": "Tilahun Gessesse", "artistAliases": ["Tilahun G."],
    "album": "Greatest Hits", "releaseYear": 1975, "genres": ["tizita"],
    "durationMs": 200000, "sourceAudioKey": "source/some-slug.mp3",
    "flags": [{ "reason": "era_unknown", "details": { "year": null } }]
  }] }
```

Only `sourceUrl` and `artistAm` are required. Empty strings and `null` mean "no value".

Response: `{ jobId, counts: { created, updated, skipped }, results: [{ sourceUrl, trackId, result, unknownGenres? }] }`.

Rules:
- **Artist** is matched by normalized `name_am` (via the alias table, then `name_am`); a new
  artist also gets its canonical name as an alias. Aliases never move from one artist to another.
- **Track** is upserted on `sourceUrl`. A new track is `needs_review` if it has any flags,
  otherwise `ingested`.
- **Re-scrapes** fill and refresh scraped fields but never null a value out and never touch a
  field an admin edited (`tracks.admin_edited_fields`, recorded by `PATCH /admin/tracks/:id`).
  Status is left alone, except `ingested` becomes `needs_review` when a new flag arrives.
- **Review items**: one per flag; skipped when an identical (reason + details) item is already open.
- **Genres** are slugs from the `genres` table; unknown slugs are ignored and echoed back as `unknownGenres`.
- Sending the same batch again returns `skipped` for every record and changes nothing.

## `POST /admin/ingest/clips`

Up to 100 clips: `{ jobId, clips: [{ trackId, type, startMs, lengthMs, r2Key, sha256, bytes }] }`
(`type` is `intro` or `middle`, `sha256` is 64 lowercase hex). Upserts on `(track, type)`,
sets `status = ready`, and bumps `version` only when something changed. An unknown `trackId`
rejects the whole request (404) before anything is written.

## `POST /admin/ingest/jobs/:id/status`

`{ status, ghRunUrl?, summary? }`. Status only moves forward (`queued` → `running` →
`succeeded` | `failed`). `started_at` is set on the first non-queued status and
`finished_at` on a terminal one. Repeating the final status is fine (200); anything else on a
finished job is 409.

## `GET /admin/ingest/catalog-snapshot`

For client-side dedupe. Positional arrays, named by `columns`:
`artists: [id, name_am, alias_norms[]]`, `tracks: [id, artist_id, title_am, title_latin, duration_ms]`.
About 240 KB for 2,000 tracks and 400 artists.

## D1 limits worth remembering

D1 allows 100 bound parameters per statement, so multi-row inserts are chunked, and writes go
through `env.DB.batch` in chunks of 100 statements. A 100-record request is a handful of
round trips. If the Free plan's per-invocation query cap ever bites, lower the batch size.
