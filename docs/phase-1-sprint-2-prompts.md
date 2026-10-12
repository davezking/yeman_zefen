# Phase 1 · Sprint 2 — Ingestion pipeline

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: the scraper and clip cutter run on GitHub Actions, triggered from the API. They feed transliterated, deduplicated, era-tagged tracks and ready clips into D1 and R2, and flag anything uncertain into the review queue.

---

## Task: Era auto-assignment and missing-year flags on ingest

**Model:** haiku — a small, rule-based function plus a hook into existing code.

**Context:** `POST /admin/ingest/tracks` exists in `api/src/routes/admin/ingest.ts`. The `generations` table has `year_from` and `year_to` (either end may be NULL). Admin overrides set `tracks.generation_overridden = 1`.

**Do this:**
1. `api/src/lib/era.ts`: `assignGeneration(year, generations)` returns the generation whose range contains the year, or null.
2. In the ingest upsert: if `generation_overridden = 0`, set `generation_id` from `release_year`. If the year is missing or matches no range, leave it null and add a `review_items` row with reason `era_unknown`, setting the track to `needs_review`.
3. Unit tests for boundary years (1979, 1980, 2009, 2010), null year, and an overridden track not being reassigned.

**Before moving on, check:**
- Boundary years land in the right era.
- Overridden tracks are never changed by ingest.

---

## Task: Wire the scraper to the ingest API and the source bucket

**Model:** sonnet — adapting existing code to a new output contract without breaking what works.

**Context:** `ingest/ethiozeima_scraper.py` already scrapes metadata and audio, and currently writes local output. It must now upload source audio to the private R2 bucket `yz-source` through the S3 API (boto3, endpoint `https://<account>.r2.cloudflarestorage.com`) and POST metadata to `POST /admin/ingest/tracks` (contract in `api/src/routes/admin/ingest.ts`). Auth headers: `CF-Access-Client-Id` and `CF-Access-Client-Secret`. Env vars: `API_BASE`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `JOB_ID`.

**Do this:**
1. Read the existing scraper first and keep its scraping logic. Refactor the output into `ingest/yz/` modules: `api_client.py` (session with Access headers, retries with backoff, batch POST of 100, job status updates), `storage.py` (R2 upload, key `source/{sha1(source_url)}.mp3`, skipped if the object already exists with the same size), and `pipeline.py` (scrape → build record → upload → collect → POST).
2. Add a CLI: `python -m yz.scrape --limit N --since DATE --dry-run`. Dry-run writes JSONL locally and uploads nothing.
3. Be polite to the source: configurable delay between requests (default 2 s), a descriptive User-Agent, and resume from the last processed URL (checkpoint file).
4. Leave `normalize`, `transliterate`, and `dedupe` as call sites with pass-through stubs. The next two tasks fill them in.
5. Post job status `running` at start and `succeeded` or `failed` with a summary (`scraped`, `created`, `updated`, `flagged`, `errors`) at the end.

**Before moving on, check:**
- `--dry-run --limit 5` produces 5 valid records with no network writes.
- A real run against local `wrangler dev` creates tracks visible via `GET /admin/tracks`.
- Re-running doesn't re-upload existing audio.

---

## Task: Fidel ↔ Latin transliteration module with confidence flags

**Model:** sonnet — a well-defined mapping problem; tricky in places, but not an architecture call.

**Context:** Tracks need both `title_am`/`title_latin` and `artist_am`/`artist_latin`. Sources give one or both, often with inconsistent Latin spellings (e.g. "Tilahun Gessesse" vs "Tilahun Gesesse"). The Amharic (Fidel) name is canonical. Normalization rules are in `docs/architecture.md` §4, "Amharic normalization" (read only that paragraph).

**Do this:**
1. `ingest/yz/fidel.py`:
   - `normalize_fidel(s)`: NFC, trim, collapse whitespace, and fold the homophone series ሀ/ሐ/ኀ, ሰ/ሠ, አ/ዐ, ጸ/ፀ across all seven orders.
   - `normalize_latin(s)`.
   - Mirror the same two functions in TypeScript at `api/src/lib/normalize.ts`, replacing the stub. Both must produce identical output; add a shared fixture file `docs/fixtures/normalize.json` that both test suites run against.
2. `ingest/yz/transliterate.py`:
   - `fidel_to_latin(s)`: a readable, SERA-inspired but simplified scheme (e.g. ሰላም → "selam"), with a complete syllable table covering all Ethiopic base characters and labialized forms.
   - `latin_to_fidel(s)`: best effort. It returns `(text, confidence)`; confidence is low when a Latin string has multiple plausible Fidel readings (gemination, the 6th-order vowel, ambiguous "e" or "a").
3. In the pipeline: when only one script is present, generate the other. Add flag `translit_uncertain` if Latin→Fidel confidence is below 0.8, or if the source Latin differs substantially from the generated Latin (normalized edit distance > 0.3). Store the source Latin as an alias.
4. Tests with ≥ 30 real artist and title pairs, including well-known names across eras.

**Before moving on, check:**
- Python and TypeScript normalization agree on every fixture.
- Fidel→Latin covers every character in the Ethiopic Unicode block used by Amharic (no `?` or passthrough characters in output).
- Uncertain cases are flagged, not silently guessed.

---

## Task: Artist and track duplicate detection

**Model:** opus — fuzzy matching with real trade-offs; false merges corrupt the catalog's canonical keys and are painful to unwind.

**Context:** Before POSTing, the pipeline fetches `GET /admin/ingest/catalog-snapshot` (artists with `name_am` and `alias_norms`; tracks with `artist_id`, titles, `duration_ms`). Normalizers exist in `ingest/yz/fidel.py`. Requirement FR-4: one canonical playable track per song; covers, live versions, and re-uploads are flagged for admin review, never auto-merged. Artist matching also feeds alias collection (FR-2).

**Do this:**
1. `ingest/yz/dedupe.py`:
   - **Artist resolution:** exact match on normalized Fidel → same artist. Exact match on any `alias_norm` → same artist, and add the incoming spelling as an alias. A near match (normalized edit-distance ratio ≥ 0.85 on Fidel or Latin, with token-order-insensitive comparison for multi-word names) → create no new artist yet; attach flag `possible_duplicate` with candidate artist IDs and scores.
   - **Track resolution within the resolved artist:** normalized title similarity ≥ 0.9 → `possible_duplicate`. Add the hint `variant_of` when the title contains live/remix/cover/version markers in Latin or Amharic (e.g. "live", "remix", "ቀጥታ"). A duration difference above 15 % lowers the score. Exact source URL means the same record (an update, not a duplicate).
   - Also detect duplicates **within the current batch**, not just against the snapshot.
2. Expose `resolve(record, snapshot) → (artist_decision, track_decision, flags)` as a pure function.
3. Document the thresholds as constants at the top of the file, with a one-line rationale each, so the admin can tune them later.
4. Tests: a table of ≥ 25 cases including spelling variants, homophone-letter variants, live versions, two different songs with similar titles by the same artist (must **not** flag above threshold if titles differ meaningfully), and same title by different artists (not a duplicate).

**Before moving on, check:**
- No auto-merges anywhere; every uncertain case becomes a flag.
- Homophone-only differences in Fidel resolve as an exact match (they normalize the same).
- The function is deterministic and has no network calls (snapshot is passed in).

---

## Task: Clip cutter — intro and middle clips to R2 + registration

**Model:** sonnet — extending existing ffmpeg tooling with a new storage and API contract.

**Context:** `ingest/clip_maker.py` already cuts clips with ffmpeg using per-track start times. Each approved-candidate track needs two clips: `intro` (start = `clips.start_ms`, defaulting to the first non-silent moment) and `middle` (default start = 45 % of duration). Clip spec: 10 s, MP3 CBR 128 kbps, file starts exactly at the start point. Public bucket `yz-clips`, key `clips/{trackId}/{type}-v{version}.mp3`. Register results via `POST /admin/ingest/clips`.

**Do this:**
1. Refactor into `ingest/yz/clips.py`:
   - Download source from `yz-source` (S3 API).
   - Detect a default intro start: skip leading silence using ffmpeg `silencedetect` (−40 dB, 0.3 s).
   - Cut with sample-accurate trimming (decode, then `-ss` after `-i`, re-encode). Apply a 30 ms fade in and out.
   - Compute SHA-256 and byte size.
   - Upload with `Cache-Control: public, max-age=31536000, immutable`.
2. CLI: `python -m yz.cut --track-ids 1,2,3` or `--all-missing`. For recuts, accept `--track-id X --type intro --start-ms N`.
3. Flag to the API (via a review item in the clip registration response, or a separate small call; pick one and document it) when the source is shorter than 25 s (`short_audio`) or missing (`missing_audio`).

**Before moving on, check:**
- Clips play from the first sample with no click (spot-listen to 3).
- A clip's duration is 10.0 s ± 30 ms (check with `ffprobe`).
- Re-running with the same parameters doesn't change the checksum, or bumps the version only when the start changes.

---

## Task: GitHub Actions workflows + Worker dispatch + job tracking

**Model:** sonnet — glue across GitHub's API, secrets, and our job table; easy to get subtly wrong but well-trodden.

**Context:** The scrape and cut CLIs exist (`python -m yz.scrape`, `python -m yz.cut`). The `ingest_jobs` table and `POST /admin/ingest/jobs/:id/status` exist. The Worker holds a fine-grained GitHub PAT (secret `GH_DISPATCH_TOKEN`, Actions read/write on this repo only), plus vars `GH_REPO` (`owner/name`) and `GH_REF` (`main`).

**Do this:**
1. `.github/workflows/ingest-scrape.yml`: triggered by `workflow_dispatch` (inputs: `job_id`, `limit`, `since`) and a weekly `schedule`. For scheduled runs, first create a job row via the API, using a `POST /admin/ingest/jobs` service-token route (add it). Steps: set up Python with a pip cache, install ffmpeg, then run the scraper with secrets. Use concurrency group `ingest` so only one runs at a time.
2. `.github/workflows/ingest-cut.yml`: `workflow_dispatch` with inputs `job_id` and `args` (passed to `yz.cut`).
3. Worker `POST /admin/jobs { kind, params }` (requireAdmin): insert an `ingest_jobs` row with status `queued`, then call `POST https://api.github.com/repos/{GH_REPO}/actions/workflows/{file}/dispatches`. On a GitHub error, mark the job `failed` with the message. `GET /admin/jobs` lists the last 50.
4. Hook the clip start-time edit (`PATCH /admin/clips/:id`) to automatically dispatch a `recut` job for that clip.
5. Each workflow posts `running` with `ghRunUrl = ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}` and a final status, including on failure (`if: always()` step).
6. Document required repo secrets and Worker secrets in `docs/ops.md`.

**Before moving on, check:**
- Triggering a scrape with `limit=3` from the API leads to a GitHub run, and the job row ends `succeeded` with a summary.
- A deliberately failing run ends with the job `failed`, not stuck in `running`.
- The PAT has no scope beyond this repo's Actions.
