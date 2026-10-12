# Phase 1 · Sprint 3 — Admin dashboard v1 & packs

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: a working internal dashboard where you review and fix ingested tracks, set clip start times, approve tracks, and publish versioned packs that the app can download. Catalog curation toward ~200 approved tracks starts at the end of this sprint.

---

## Task: Admin SPA shell

**Model:** haiku — framework scaffolding with decided libraries.

**Context:** The admin site is a Vite + React + TypeScript SPA in `admin/`, deployed to Cloudflare Pages at `admin.<domain>` behind Cloudflare Access. The API is at `api.<domain>` (dev: `http://localhost:8787`). Access sets a cookie, so the browser calls the API with `credentials: 'include'`. In dev, the Worker accepts `DEV_ADMIN_EMAIL`.

**Do this:**
1. Scaffold with Vite (react-ts). Add Mantine (core, hooks, notifications, dates), `@tanstack/react-query`, `react-router-dom`, `zod`, and Noto Sans Ethiopic via `@fontsource/noto-sans-ethiopic`, applied globally so Fidel always renders.
2. `src/api/client.ts`: a typed fetch wrapper (base URL from `VITE_API_BASE`, includes credentials, parses the `{ error }` shape into thrown errors shown as Mantine notifications).
3. App shell with a sidebar: Tracks, Review queue, Artists, Packs, Jobs, Reports, Analytics, Moderation. Each later route is a placeholder page. A header shows the email and role from `GET /admin/whoami`.
4. Make the API allow CORS from the admin origin only, with credentials.
5. Add `admin` to `ci.yml` (typecheck + build) and a Pages deploy note in `docs/ops.md`.

**Before moving on, check:**
- `npm run dev` shows the shell with your dev email in the header.
- A failed API call shows a readable notification, not a blank screen.
- Fidel text renders in the sidebar test string "የማን ዘፈን".

---

## Task: Tracks table, editor, and approve/reject workflow

**Model:** sonnet — the main catalog UI, with real workflow rules.

**Context:** The API (`api/src/routes/admin/catalog.ts`) provides track list, detail, patch, approve, and reject, plus artist search. Statuses: `ingested`, `needs_review`, `approved`, `rejected`, `retired`. Approve returns 409 if the intro or middle clip isn't ready.

**Do this:**
1. `/tracks`: a table with columns Fidel title, Latin title, artist (am / latin), year, era, status badge, clip readiness (two dots: intro and middle), and open-flag count. Filters: status, era, genre, and search. Use cursor pagination with "load more". Multi-select allows bulk approve and bulk reject, each showing per-row results.
2. `/tracks/:id`: an edit form for all FR-1 fields:
   - Era select, marked "overridden" when manually set.
   - Genre multi-select.
   - Artist picker with search, and "create new artist".
   - A link to source.
   - An audio preview of each clip from the CDN URL.
   - Open review items listed inline with resolve buttons.
3. Approve and reject buttons with the 409 reason shown clearly ("Middle clip not ready — cut job pending").
4. Keyboard flow for fast curation: `j`/`k` for next/previous track in the current filter, `a` to approve, `e` to focus edit.

**Before moving on, check:**
- Editing and saving a Fidel title round-trips exactly (no normalization applied to stored display text).
- Bulk approve reports which rows failed and why.
- Curating 20 tracks with keyboard shortcuts feels fast.

---

## Task: Review queue UI

**Model:** sonnet — several flag types, each needing a different resolution UI.

**Context:** `GET /admin/review-items` and the resolve/dismiss endpoints exist. Reasons are `translit_uncertain`, `possible_duplicate` (details include candidate IDs and scores), `missing_audio`, `short_audio`, and `era_unknown`. The artist merge endpoint exists (admin role only).

**Do this:**
1. `/review`: tabs per reason with counts, oldest first.
2. Per-reason resolution panels:
   - `translit_uncertain`: side-by-side source vs generated text, editable, with accept.
   - `possible_duplicate`: the incoming record next to each candidate (titles, artist, year, duration, audio previews). Actions: "Same artist → merge" (admin only), "Same song → mark this as duplicate" (sets `canonical_track_id` and status `rejected`), or "Different".
   - `era_unknown`: year input + era select.
   - `missing_audio` / `short_audio`: retire or re-run cut.
3. Resolving an item auto-advances to the next one. If the track has no remaining open items, offer "approve now".
4. Add any small API endpoints you need, e.g. `POST /admin/tracks/:id/mark-duplicate { canonicalTrackId }`, with tests.

**Before moving on, check:**
- Every reason type can be resolved without leaving the page.
- Marking a duplicate never deletes data; the track is rejected and linked to its canonical track.
- Counts update after resolving.

---

## Task: Clip start-time editor with waveform and recut

**Model:** sonnet — audio UI with timing precision and async job feedback.

**Context:** Each track has `intro` and `middle` clips. `PATCH /admin/clips/:id { start_ms }` sets the clip to `pending` and dispatches a recut job (`ingest_jobs`). Source audio is private in `yz-source`, so the browser can't read it directly.

**Do this:**
1. Add `GET /admin/tracks/:id/source-url`, returning a short-lived (10 min) signed URL for the source object. Use `aws4fetch` presigning against R2's S3 endpoint with R2 API credentials stored as Worker secrets.
2. On the track page, add a clip editor using `wavesurfer.js` with the Regions plugin:
   - Load the full source and show two 10 s regions (intro, middle), each draggable but fixed-length.
   - Play from a region start, plus nudge buttons of ±100 ms and ±1 s.
   - A "preview 3 s / 5 s / 10 s" button that plays just that length, to mimic difficulty levels.
3. Save calls `PATCH` for any changed region. Then show the job status inline, polling `GET /admin/jobs?id=` every 5 s until done, and refresh the clip preview from its new versioned URL.

**Before moving on, check:**
- The waveform start time and the recut clip's first sound line up by ear.
- Saving both regions dispatches at most two recut jobs.
- The signed URL expires (a fetch after expiry fails).

---

## Task: Pack builder — versioned manifests published to R2 + `/v1/packs`

**Model:** sonnet — straightforward logic, but the manifest is a contract the app depends on, so it must be exact.

**Context:** Tables: `packs`, `pack_versions`, `pack_tracks`. Only `approved` tracks with both clips `ready` may be included. Manifests are immutable at `packs/{slug}/v{n}/manifest.json` in the public bucket `yz-clips`, served at `CDN_BASE_URL`. FR-16 requires version, track list, and checksums.

**Do this:**
1. Admin endpoints:
   - `POST /admin/packs` (slug, names, optional generation_id or genre_id filter)
   - `GET /admin/packs` (with version history)
   - `POST /admin/packs/:id/versions { trackIds? }`: default to all eligible tracks matching the pack's filter. Validate eligibility, write `pack_versions` and `pack_tracks`, write the manifest JSON to R2 with immutable cache headers, then set `packs.current_version`.
2. Manifest format (write it to `docs/pack-manifest.md` as the contract):
   `{ schema: 1, slug, version, publishedAt, names: {am, en}, generationId, genreId, tracks: [{ id, titleAm, titleLatin, artistId, artistAm, artistLatin, generationId, genreIds, releaseYear, clips: { intro: { url, sha256, bytes, lengthMs }, middle: {...} } }], totalBytes }`
3. Public `GET /v1/packs` (no auth yet; the Firebase middleware arrives in Phase 3, so leave a TODO marker in the route list): returns current versions with `manifestUrl`, `trackCount`, `totalBytes`, names, and filters. Cache for 5 minutes.
4. Admin UI `/packs`: create a pack, see eligible-track count, publish a new version with a confirm step showing the diff (added and removed tracks vs the current version), and view history.

**Before moving on, check:**
- A published manifest validates against the documented format (add a zod schema test).
- Publishing never overwrites an existing version's manifest.
- A track that is retired after publishing stays in old versions and is excluded from the next one.

---

## Task: Jobs page — run and schedule scraper, job status

**Model:** haiku — a UI over endpoints that already exist.

**Context:** `POST /admin/jobs` and `GET /admin/jobs` exist. The scrape workflow also runs weekly on a GitHub schedule.

**Do this:**
1. `/jobs` table: kind, status badge, params, started, duration, a summary (scraped/created/flagged counts), and a link to the GitHub run. Auto-refresh every 10 s while any job is queued or running.
2. "Run scraper" dialog with `limit` and `since` inputs. "Cut missing clips" button runs `cut` with `--all-missing`.
3. A note on the page with the weekly schedule and where to change it (the workflow file).

**Before moving on, check:**
- Starting a run from the page shows it as queued, then running, then finished, without a manual refresh.
- Failed jobs show their error summary.
