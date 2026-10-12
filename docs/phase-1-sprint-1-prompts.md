# Phase 1 · Sprint 1 — Foundations

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: a monorepo with a deployable Worker, a per-task PR workflow with required Claude Opus review, the full D1 schema, admin authentication, and the catalog and ingest APIs. Everything later builds on this.

---

## Task: Scaffold monorepo, Worker hello-world, and CLAUDE.md

**Model:** haiku — pure scaffolding; every choice is already decided.

**Context:** New project "Yeman Zefen", an Amharic music-guessing game. Stack: Cloudflare Workers (TypeScript, Hono, zod, Drizzle on D1), R2, Vite + React admin, Flutter app, Python ingestion on GitHub Actions. Existing files `ethiozeima_scraper.py` and `clip_maker.py` will be copied into `ingest/`.

**Do this:**
1. Create the layout: `api/`, `admin/` (empty placeholder with README), `app/` (empty placeholder with README), `ingest/` (move the two existing Python files here, add `requirements.txt` and `pyproject.toml` with pytest), `docs/`, `.github/workflows/`.
2. In `api/`: init a Worker with `wrangler` (TypeScript), add `hono`, `zod`, `drizzle-orm`, `jose`, plus `vitest` with `@cloudflare/vitest-pool-workers`. Make `wrangler.toml` contain:
   - D1 binding `DB` (database `yz-db`)
   - R2 bindings `CLIPS` (`yz-clips`) and `SOURCE` (`yz-source`)
   - vars `ENV`, `FIREBASE_PROJECT_ID`, `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `CDN_BASE_URL`
   - a `[env.prod]` block
3. `api/src/index.ts`: a Hono app with request-ID middleware, JSON error handler returning `{ error: { code, message } }`, and `GET /health` → `{ ok: true, env }`. Route modules live in `api/src/routes/`, shared helpers in `api/src/lib/`.
4. Add `.github/workflows/ci.yml` running `npm ci && npm run typecheck && npm test` in `api/`, and `pytest` in `ingest/`.
5. Write a root `CLAUDE.md` under 60 lines covering: what the product is (2 lines), the repo layout, commands per package (dev, test, deploy), conventions (TypeScript strict, zod on every request body, epoch-ms UTC timestamps, error shape, no secrets in code), and "the architecture doc is `docs/architecture.md`; read only the section a task names." Add a **Git workflow** section: one branch per task named `task/p<phase>s<sprint>-<slug>`, small commits, push, and open a PR with `gh pr create` using the PR template. Never push directly to `main`.
6. Copy `architecture.md` into `docs/`.

**Before moving on, check:**
- `cd api && npx wrangler dev` serves `/health` locally.
- `npm test` passes with one smoke test hitting `/health`.
- `CLAUDE.md` is short enough to read in a few seconds.

---

## Task: Per-task PR workflow with required Claude Opus code review

**Model:** sonnet — CI configuration with secrets and branch protection; well documented, but the gating logic must be right or the review becomes optional in practice.

**Context:** The rule for this project is that every task lands on `main` only through a pull request reviewed by **Claude Opus**, pinned to `claude-opus-5-5`, regardless of which model wrote the code. Use the official `anthropics/claude-code-action@v1`, which takes the model through `claude_args: "--model ..."`. It authenticates with either an `ANTHROPIC_API_KEY` secret or a `CLAUDE_CODE_OAUTH_TOKEN` secret (via the `claude_code_oauth_token` input). Check the action's README for the current inputs and required permissions before writing the workflow. `CLAUDE.md` holds the project conventions. `ci.yml` already exists.

**Do this:**
1. `.github/pull_request_template.md` with sections: **Task** (title + prompt file name), **Model used**, **Checklist** (paste the task's "Before moving on" bullets as `- [ ]` items), and **Notes / deviations**.
2. `.github/workflows/claude-review.yml`:
   - Trigger on `pull_request` types `opened`, `synchronize`, `reopened`, `ready_for_review`. Skip drafts.
   - Set `concurrency: claude-review-${{ github.event.pull_request.number }}` with `cancel-in-progress: true`, so a new push replaces a stale review instead of paying for both.
   - Use least-privilege permissions: `contents: read`, `pull-requests: write`, plus whatever the action's README says it needs (e.g. `id-token: write`).
   - Check out with `fetch-depth: 0`, then run the action with `claude_args: "--model claude-opus-5-5 --max-turns 20 --allowedTools 'Read,Grep,Glob,Write,Bash(gh pr view:*),Bash(gh pr diff:*),Bash(gh pr comment:*)'"`.
   - Use a review prompt that tells Opus to:
     - read `CLAUDE.md` and the PR description;
     - review **only the diff** for correctness, security (auth checks, secrets, injection, unvalidated input), adherence to `CLAUDE.md`, missing tests, and whether each checklist item is actually satisfied by the code;
     - post one PR comment that lists findings as **Blocking** or **Suggestion**, each with file and line, and ends with `VERDICT: APPROVE` or `VERDICT: CHANGES_REQUESTED`;
     - write that same verdict word to `review-verdict.txt` in the workspace.
   - A final step fails the job unless `review-verdict.txt` contains `APPROVE`. If the file is missing, fail with "review did not complete".
   - Name the job `Opus review` so it shows clearly as a status check.
3. Write `docs/ops.md` → "Code review" covering:
   - adding the auth secret;
   - a branch protection rule (or ruleset) on `main` that requires a PR, requires the `Opus review` and CI checks to pass, and blocks force-pushes and direct pushes;
   - what to do on a false positive: reply on the PR explaining why, then re-run the job. Don't add a bypass label, because that would make the review optional.
4. Open this task's own PR and confirm the workflow reviews it.

**Before moving on, check:**
- This task's PR received an Opus review comment ending in a `VERDICT:` line, and the `Opus review` check reflects it.
- A test PR with a deliberate bug (e.g. a route missing `requireAdmin`) gets `CHANGES_REQUESTED` and cannot be merged.
- Pushing a fix to the same branch re-runs the review and cancels any in-flight run.
- A direct `git push` to `main` is rejected.

---

## Task: D1 schema, migrations, and seed data

**Model:** sonnet — translating a decided schema into correct constraints and indexes needs care, but no new design.

**Context:** The schema is specified in `docs/architecture.md` §4 (read only §4). Use Drizzle schema definitions in `api/src/db/schema.ts`, and generate SQL migrations into `api/migrations/` applied with `wrangler d1 migrations apply`.

**Do this:**
1. Define every table in §4 with the listed columns, using integer epoch-ms timestamps. Include:
   - FKs where listed
   - `UNIQUE` on `artists.name_am` and `artist_aliases.alias_norm`
   - PK `(period, generation_id, user_id)` on `leaderboard_entries`, plus index `(period, generation_id, points DESC)`
   - PK `(date, track_id)` on `royalty_daily`
   - indexes on `tracks(status)`, `tracks(artist_id)`, `tracks(generation_id)`, `review_items(status, reason)`, `game_sessions(user_id, received_at)`, `game_sessions(received_at)`
2. Use CHECK constraints (or Drizzle enums) for status and type columns.
3. Seed migration: the 5 generations with year ranges (golden-age ≤1979, 80s 1980–1989, 90s 1990–1999, 2000s 2000–2009, modern ≥2010), Amharic and English names, and the 5 genres (tizita, ethio-jazz, traditional, pop, hip-hop).
4. Export a typed `db(env)` helper in `api/src/db/client.ts`.

**Before moving on, check:**
- Migrations apply cleanly to a fresh local D1 twice, the second time as a no-op.
- A vitest test inserts an artist + track + clip and reads them back with joins.
- Inserting a duplicate `alias_norm` fails.

---

## Task: Admin auth middleware — Cloudflare Access JWT + role check

**Model:** opus — security boundary; a subtle verification mistake exposes the whole catalog and royalty data.

**Context:** All `/admin/*` routes sit behind Cloudflare Access. Access adds a `Cf-Access-Jwt-Assertion` header. Humans authenticate by email. GitHub Actions authenticates with an Access **service token**, whose JWT has a `common_name` claim instead of `email`. Env vars: `ACCESS_TEAM_DOMAIN` (e.g. `https://yz.cloudflareaccess.com`) and `ACCESS_AUD`. The `admin_users` table holds email and role (`admin | editor`).

**Do this:**
1. `api/src/lib/accessAuth.ts`: verify the header JWT with `jose` against `${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs` (use `createRemoteJWKSet`, cached at module scope). Check `aud` includes `ACCESS_AUD`, `iss` equals the team domain, and `exp`. Reject on a missing header; never fall back to trusting other headers.
2. Middleware `requireAdmin(roles?)` for humans: email must exist in `admin_users` with an allowed role. Put `{ email, role }` on the Hono context.
3. Middleware `requireService()` for `/admin/ingest/*`: accept only service-token JWTs whose `common_name` matches the env var `INGEST_SERVICE_CLIENT_ID`.
4. Mount both on a `/admin` router. Add a temporary `GET /admin/whoami`.
5. Write a script `api/scripts/add-admin.ts <email> <role>` to seed admins, and a short section in `docs/` on configuring the two Access applications (`admin.<domain>`, and `api.<domain>/admin/*`) plus the service token.
6. Tests: sign test JWTs with a local key pair and inject a test JWKS. Cover valid, wrong aud, expired, wrong issuer, unknown email, service token on a human route, and human token on an ingest route.

**Before moving on, check:**
- Every negative test returns 401 or 403, never 500.
- `/admin/whoami` with no header returns 401, even in dev (provide an explicit `DEV_ADMIN_EMAIL` bypass that only works when `ENV=dev`).
- No route under `/admin` is reachable without passing through one of the two middlewares.

---

## Task: Catalog admin API — artists, aliases, tracks, clips

**Model:** sonnet — standard CRUD with real business rules (status transitions, artist merge).

**Context:** Schema exists (`api/src/db/schema.ts`). The admin middleware `requireAdmin` exists. Track statuses are `ingested → needs_review → approved | rejected`, and `approved → retired`. The canonical artist key is `name_am`. Latin and other spellings live in `artist_aliases` with a normalized `alias_norm`. The normalization function itself comes in Sprint 2. For now, create `api/src/lib/normalize.ts` exporting `normalizeLatin()` (lowercase, strip diacritics and apostrophes, collapse whitespace) and a stub `normalizeFidel()` that does NFC + trim.

**Do this:**
1. `api/src/routes/admin/catalog.ts` with zod-validated:
   - `GET /admin/tracks` (filters: status, generation, artist, q search over both titles; cursor pagination, 50 per page)
   - `GET /admin/tracks/:id` (with artist, aliases, clips, open review items)
   - `PATCH /admin/tracks/:id` (editable fields; setting `generation_id` sets `generation_overridden = 1`)
   - `POST /admin/tracks/:id/approve` (requires both intro and middle clips with `status = ready`, else 409 with reason)
   - `POST /admin/tracks/:id/reject`
2. Artists: `GET/PATCH /admin/artists`, alias add/remove, and `POST /admin/artists/:id/merge { intoArtistId }`. Merge moves tracks and aliases, and adds the merged artist's `name_am` as an alias. Run it in a D1 batch.
3. `PATCH /admin/clips/:id { start_ms }`: validate `0 ≤ start_ms ≤ duration_ms − length_ms`, set clip `status = pending`. Return `{ needsRecut: true }`. The job trigger comes in Sprint 2.
4. Editors can edit; only `admin` can merge artists.

**Before moving on, check:**
- Approving a track without ready clips returns 409 with a clear message.
- The merge test leaves no orphaned tracks or aliases.
- List queries use indexes (spot-check with `EXPLAIN QUERY PLAN` on the main filter).

---

## Task: Ingest API for GitHub Actions — batch upserts, job status, catalog snapshot

**Model:** sonnet — upsert and idempotency logic across several tables.

**Context:** GitHub Actions jobs authenticate via `requireService()`. A scraper run sends tracks in batches of up to 100. Records arrive already normalized and transliterated, with a list of `flags` the pipeline raised. Tables involved: `artists`, `artist_aliases`, `tracks`, `track_genres`, `clips`, `review_items`, `ingest_jobs`.

**Do this:**
1. `POST /admin/ingest/tracks` body: `{ jobId, tracks: [{ sourceUrl, titleAm, titleLatin, artistAm, artistLatin, artistAliases[], album, releaseYear, genres[], durationMs, sourceAudioKey, flags: [{ reason, details }] }] }`.
   - Upsert the artist by normalized `name_am`, and add aliases.
   - Upsert the track by `source_url` (re-scrapes update metadata but never overwrite admin-edited fields; track `updated_by_admin_at` or compare timestamps).
   - New tracks get `status = needs_review` if any flags exist, else `ingested`.
   - Insert one `review_items` row per flag, skipping an identical open item.
   - Return per-record results `{ sourceUrl, trackId, created|updated|skipped }`.
2. `POST /admin/ingest/clips` body: `{ jobId, clips: [{ trackId, type, startMs, lengthMs, r2Key, sha256, bytes }] }`. Upsert by `(track_id, type)`, bump `version`, set `status = ready`.
3. `POST /admin/ingest/jobs/:id/status` body: `{ status, ghRunUrl?, summary? }`. Sets `started_at` and `finished_at` appropriately.
4. `GET /admin/ingest/catalog-snapshot` returns compact arrays of artists (id, name_am, alias_norms) and tracks (id, artist_id, title_am, title_latin, duration_ms) for client-side dedupe.
5. Use D1 `batch()` so each request is one round-trip per chunk. Keep each batch under D1's statement limits; chunk if needed.

**Before moving on, check:**
- Re-sending the same batch is idempotent: no duplicate tracks, aliases, or review items.
- An admin edit to `title_latin` survives a re-scrape of the same source URL.
- The snapshot for 2,000 tracks stays under ~1 MB.
