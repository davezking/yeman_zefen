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
- **Artist** is matched by the folded form of `artistAm` (`normalizeFidel`: NFC, whitespace collapsed,
  and the homophone series ሀ/ሐ/ኀ, ሰ/ሠ, አ/ዐ, ጸ/ፀ folded across all orders), first against the alias
  table, then against `name_am`. So ጥላሁን ገሠሠ and ጥላሁን ገሰሰ are the same artist. A new artist is
  stored under the spelling it first arrived with (whitespace cleaned, not folded) and also gets that
  name as a `canonical` alias whose key is the folded form. Aliases never move from one artist to another.
  The folded form is only ever a comparison key; `ingest/yz/fidel.py` computes the same one
  (`docs/fixtures/normalize.json` is run against both).
- **Track** is upserted on `sourceUrl`. A new track is `needs_review` if it has any flags,
  otherwise `ingested`.
- **Re-scrapes** fill and refresh scraped fields but never null a value out and never touch a
  field an admin edited (`tracks.admin_edited_fields`, recorded by `PATCH /admin/tracks/:id`).
  Status is left alone, except `ingested` becomes `needs_review` when a new flag arrives.
  A track's **genres** count as one such field (`genres` in `admin_edited_fields`): once an admin
  has set them with `PATCH /admin/tracks/:id { genreIds }`, a re-scrape no longer links genres to
  it, so a genre the admin removed does not come back.
- **Era** is derived from the release year (`api/src/lib/era.ts`), using the stored year when the
  scrape has none. Tracks with `generation_overridden = 1` are never reassigned. A missing year or
  one that matches no generation leaves the era null and adds an `era_unknown` review item.
- **Review items**: one per flag; skipped when an identical (reason + details) item is already open.
- **Genres** are slugs from the `genres` table; unknown slugs are ignored and echoed back as `unknownGenres`.
- Sending the same batch again returns `skipped` for every record and changes nothing.

## `POST /admin/ingest/jobs`

For a run that started without a job: the weekly scrape, or one started by hand from the Actions tab.
`{ kind, params? }` (the same body as `POST /admin/jobs`, see `docs/ops.md`) creates a `queued` job and returns
`{ jobId }` (201). Nothing is dispatched: the run that asks is the run. The workflow then reports through
`POST /admin/ingest/jobs/:id/status`.

## `POST /admin/ingest/clips`

Up to 100 each of clips, flags and durations, in any combination:
`{ jobId, clips: [{ trackId, type, startMs, lengthMs, r2Key, sha256, bytes }], flags: [{ trackId, reason, details? }],
durations: [{ trackId, durationMs }] }`
(`type` is `intro` or `middle`, `sha256` is 64 lowercase hex). Upserts on `(track, type)`,
sets `status = ready`, and bumps `version` only when something changed (the clip was not `ready`, or its
start, length, key, checksum or size differ). An unknown `trackId`, in a clip or a flag, rejects the whole
request (404) before anything is written. The job must be a `cut` or `recut` job.

**Keys and versions.** The version is part of the key, `clips/{trackId}/{type}-v{version}.mp3`, and the API
assigns it. So a client that registers a changed clip uploads it to `previous version + 1` (`1` for a new
clip) and sends that key; the API then assigns exactly that version, and the response's `version` lets the
client check it. A clip that comes out identical to what is registered is neither uploaded nor sent, so
objects in `yz-clips` are never rewritten and can be cached for a year (`immutable`).

**Flags.** `flags` is how a cut job reports a problem with a track's *source audio* (one call with the clips,
no separate endpoint). `reason` is `missing_audio` or `short_audio` only; `details` is free-form. Each flag
becomes an open `review_items` row for the track, and an `ingested` track moves to `needs_review` (an
`approved` one is left alone). An identical open item (same reason and details, whatever the key order) is
not duplicated, so re-running a job is safe.

**Durations.** `durations` records the length of a track's source audio, which the cutter measures and the scraper
cannot know. It sets `tracks.duration_ms`, which the clip editor (`PATCH /admin/clips/:id`) needs to check a new start
time and duplicate detection uses to compare lengths. A track is only written when its length changes, and never
when an admin has edited `durationMs` (`tracks.admin_edited_fields`). One track per request at most once.

The response lists each flag as `created` or `skipped` and each duration as `updated` or `skipped`:
`{ jobId, counts, results, flags: [{ trackId, reason, result }], durations: [{ trackId, result }] }`.

## `GET /admin/ingest/clip-targets`

What the cutter reads before it cuts. Send exactly one of `trackIds=1,2,3` (up to 200) or `missing=1`
(optionally `after=<id>` and `limit=<1..200, default 100>` to page through).

`{ tracks: [{ id, status, sourceAudioKey, durationMs, clips: [{ type, startMs, lengthMs, r2Key, sha256,
bytes, version, status }] }], next }`. With `trackIds`, every track that exists is returned, whatever its
status or source key; unknown ids are left out. With `missing=1`, only tracks that are `ingested`,
`needs_review` or `approved`, have a `source_audio_key`, and do not have both clips `ready` (so a clip an
admin moved, which is `pending`, shows up). `next` is the cursor for the following page, `null` on the last.

## `POST /admin/ingest/jobs/:id/status`

`{ status, ghRunUrl?, summary? }`. Status only moves forward (`queued` → `running` →
`succeeded` | `failed`). `started_at` is set on the first non-queued status and
`finished_at` on a terminal one. Repeating the final status is fine (200); anything else on a
finished job is 409.

## `GET /admin/ingest/catalog-snapshot`

For client-side dedupe (`ingest/yz/dedupe.py`). Positional arrays, named by `columns`:
`artists: [id, name_am, alias_norms[]]`, `tracks: [id, artist_id, title_am, title_latin, duration_ms]`.
About 240 KB for 2,000 tracks and 400 artists.

## D1 query budget (Cloudflare Free plan)

The Free plan allows **50 D1 queries per Worker invocation**, and **every statement inside a
`batch()` counts**. So a request must cost the same whether it carries 1 record or 100.

Both write endpoints therefore send their records to D1 as **one JSON bound parameter** and expand
it with `json_each()` in set-based `INSERT ... SELECT` / `UPDATE ... FROM` statements:

| Request | D1 queries |
|---|---|
| `POST /tracks`, 1, 10 or 100 new records | 15 |
| `POST /tracks`, 100 re-sent or re-scraped records | 13 |
| `POST /clips`, any number of clips up to 100 | 6 |
| `POST /clips`, 3 or 100 flags and no clips | 6 |
| `POST /clips`, 100 clips and 100 flags | 8 |
| `POST /clips`, 3 or 100 durations, none changed / some changed | 4 / 5 |
| `POST /clips`, 100 each of clips, flags and durations | 9 |
| `GET /clip-targets`, any number of tracks | 2 |

`test/queryBudget.test.ts` counts the statements that reach D1 and fails if a request goes over
30 (tracks) or 12 (clips), or if the cost starts growing with the number of records.

Other D1 limits that shaped this: 100 bound parameters per statement (passing the payload as one
JSON parameter sidesteps it) and a 2 MB limit per value (requests over 1 MB are rejected with 413).
