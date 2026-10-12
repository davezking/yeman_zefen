# Phase 3 · Sprint 1 — Identity & sessions

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: every player, guest included, has a Firebase identity. The Worker verifies it on every call. Sessions sync to the server, which computes the authoritative score. Nightly roll-ups produce the royalty and analytics tables.

---

## Task: Firebase setup + anonymous sign-in + authenticated API client

**Model:** sonnet — multi-platform Firebase configuration with flavors is fiddly but well documented.

**Context:** The Flutter app in `app/` has `dev` and `prod` flavors. Use one Firebase project per environment (`yz-dev`, `yz-prod`). FR-13 requires guests to play immediately, so the app signs in anonymously on first launch without any UI. Providers enabled now: Anonymous, Google, Email/Password, and Apple (the linking UI comes next sprint).

**Do this:**
1. Create both Firebase projects and register Android and iOS apps per flavor. Run `flutterfire configure` per flavor into `lib/core/config/firebase_options_{dev,prod}.dart`, and pick the right one at startup. Document the steps in `docs/ops.md`.
2. `lib/core/auth/auth_service.dart`: on startup, if there's no current user, `signInAnonymously()`. Expose `authStateProvider` (uid, isAnonymous, providers). Handle the offline-at-first-launch case: the game must still start. Retry anonymous sign-in when connectivity returns; until then, sessions queue locally without a UID.
3. `lib/core/http/api_client.dart`: attaches `Authorization: Bearer <getIdToken()>`, refreshes once and retries on a 401, and maps the `{ error }` shape to typed exceptions.
4. Move `PacksApi` onto this client.

**Before moving on, check:**
- A fresh install on both platforms gets an anonymous UID with no UI shown.
- Launching in airplane mode still reaches the game and plays installed packs.
- The UID persists across app restarts.

---

## Task: Firebase JWT middleware in the Worker

**Model:** opus — this is the authentication boundary for every player request; verification details must be exactly right.

**Context:** Worker in `api/`, with `jose` installed and env `FIREBASE_PROJECT_ID`. Firebase ID tokens are RS256 JWTs. Google publishes the signing keys as a JWKS at `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`. The anonymous flag comes from the `firebase.sign_in_provider` claim (`anonymous`).

**Do this:**
1. `api/src/lib/firebaseAuth.ts`: verify with `createRemoteJWKSet` (module-scope cache), algorithms `['RS256']`, `issuer = https://securetoken.google.com/${projectId}`, `audience = projectId`. Also require that `sub` is non-empty and ≤ 128 characters, and that `auth_time` is in the past. Allow 60 s clock tolerance.
2. Middleware `requireUser({ allowAnonymous = true })` sets `c.var.user = { uid, isAnonymous, provider, email? }`. Return 401 on any failure, with a generic message (no detail about which check failed in the response; log it server-side).
3. Apply it to every `/v1/*` route except `GET /v1/config` and `GET /v1/packs`, which stay public.
4. Tests with a locally generated RSA key and injected JWKS: valid, expired, wrong aud, wrong iss, `alg: none`, HS256 signed with the public key, missing `sub`, an anonymous token on an `allowAnonymous: false` route (403), and a JWKS fetch failure (503, not 401).

**Before moving on, check:**
- All attack-shaped tokens are rejected.
- A real token from the dev app passes.
- JWKS is fetched once per isolate, not per request (assert with a counting fetch mock).

---

## Task: `/v1/me` upsert and account deletion

**Model:** sonnet — simple endpoints, but deletion has to cascade correctly.

**Context:** `requireUser` exists. The `users.id` column is the Firebase UID. Both stores require in-app account deletion. Deleting must remove personal data and leaderboard presence, but keep anonymized session rows so royalty counts stay correct.

**Do this:**
1. `PUT /v1/me { displayName? }`: upsert the user. Set `is_anonymous` from the token, `country` from `c.req.raw.cf?.country`, and `last_seen_at`. Validate `displayName` as 2–24 characters (Fidel and Latin letters, digits, spaces), and reject a small blocklist (start a `api/src/lib/blocklist.ts` that the admin can extend).
2. `GET /v1/me` returns the profile.
3. `DELETE /v1/me`: in one D1 batch, delete `leaderboard_entries` for the UID, set `game_sessions.user_id` to `'deleted'`, and delete the `users` row. The client then deletes the Firebase user (`currentUser.delete()`, with re-auth if Firebase requires it) and signs in anonymously again.
4. App side: call `PUT /v1/me` after sign-in and on each app open (at most once per 6 hours).

**Before moving on, check:**
- After deletion, the user is absent from all leaderboard queries, and royalty counts for their past plays are unchanged.
- A display name containing Fidel saves and reads back exactly.

---

## Task: `POST /v1/sessions` — server-authoritative scoring, sanity bounds, idempotency

**Model:** opus — anti-cheat and leaderboard integrity depend on this; it must match the client scorer exactly and resist forged payloads.

**Context:** The payload contract is in `docs/session-payload.md`, and the rules are in `docs/scoring.md` (read both). The client never sends a score. The server must:
- verify every referenced track and artist exists and that the options are valid;
- compute points;
- store **one** `game_sessions` row (this is how D1 writes stay low);
- update leaderboards only for non-anonymous, non-shadow-banned users.

Leaderboard rows are `(period, generation_id, user_id, points)`, where period is `all` or the ISO week of `received_at` (e.g. `2026-W42`), and generation 0 means all eras. The client's local `Scorer` in `app/lib/features/game/domain/` uses the same rules.

**Do this:**
1. `api/src/lib/scoring.ts`: a pure implementation of `docs/scoring.md`. Port the client's worked-example tests so both sides run the same cases (put the cases in `docs/fixtures/scoring.json` and load them from both test suites).
2. `api/src/routes/v1/sessions.ts`:
   - zod-validate the payload (≤ 50 rounds, 4 options each, enums).
   - **Idempotency:** if `id` already exists for this user, return the stored result. If the ID exists for a different user, return 409.
   - Load referenced tracks in one query. Reject unknown IDs. Check `trackId ∈ optionIds`, options are distinct, and for `artist` questions that the options are artist IDs and the correct answer is the track's artist.
   - Compute points per round with sanity bounds: under 200 ms means the round is invalid and the session is flagged. The sum of `responseMs` must fit inside `clientEndedAt − clientStartedAt` (tolerance 10 s). `clientStartedAt` can't be more than 14 days old or 5 minutes in the future (server time wins for leaderboard period assignment).
   - Write the session row, then do leaderboard upserts (`points = points + excluded.points`) for `all`/`week` × `generation 0`/session era, but only if the user is registered, not shadow-banned, and the session isn't flagged. Use a single `batch()`.
   - Return `{ score, rounds: [{ points, correct }], flagged }`.
3. Tests: honest session, replayed ID, foreign ID, forged correct answer (option list not containing the track), inhuman response times, a session whose time doesn't add up, an anonymous user (stored but no leaderboard write), and a shadow-banned user.

**Before moving on, check:**
- Every shared scoring fixture produces identical results on client and server.
- A replayed session never double-counts leaderboard points.
- A typical session costs ≤ 6 D1 row writes (count statements in a test).

---

## Task: Offline session queue and sync

**Model:** sonnet — retry and ordering logic with real failure modes.

**Context:** Sessions are saved to the drift table `pending_sessions` (Phase 1). `ApiClient` and `POST /v1/sessions` exist; the endpoint is idempotent on session `id`. FR-15 requires offline play with sync on reconnect, with the server as the source of truth.

**Do this:**
1. `lib/features/game/data/session_sync.dart`: send pending sessions oldest-first when the app starts, when connectivity is regained (`connectivity_plus`), after each session ends, and on resume.
   - Use exponential backoff per item (cap at 1 hour). Stop retrying permanently on a 4xx validation error, but keep the row with `last_error` for debugging.
   - Delete the row on 2xx.
   - Never send in parallel. Use a single-flight lock.
2. Sessions recorded before a UID existed get sent once anonymous sign-in succeeds.
3. After a successful sync, update the local "server score" for that session so the results history shows the authoritative number.
4. Tests with a fake API: offline → online, a 500 then success, a 422 parked permanently, and a duplicate send (idempotent).

**Before moving on, check:**
- Five sessions played in airplane mode all sync after reconnecting, in order.
- Killing the app mid-sync loses nothing and duplicates nothing.

---

## Task: Nightly cron roll-ups — royalty, ads, analytics

**Model:** sonnet — aggregation SQL with careful date boundaries.

**Context:** `game_sessions` stores `track_ids_json`, `country`, `received_at`, `rounds`, and an `ads` object in `events_json`. The rest of the system reads only roll-ups: `royalty_daily(date, track_id, plays)`, `ad_events_daily(date, country, format, event, count)`, `analytics_daily(date, metric, dimension, value)`. Dates are UTC `YYYY-MM-DD`. FR-22 needs exact per-track play counts for any date range.

**Do this:**
1. Add a Workers Cron Trigger at 00:30 UTC daily, in `api/src/cron/rollups.ts`.
2. For "yesterday" (and accept a `date` param for backfill via an admin endpoint `POST /admin/rollups/run { date }`), compute:
   - Royalty plays per track. Use SQLite `json_each` over `track_ids_json` with `GROUP BY` to count every played track, including rounds the player got wrong.
   - Ad counts per country and format.
   - Analytics metrics: `dau`, `new_users` (users created that day), `sessions`, `rounds`, `rounds_per_session`, `plays_by_country`.
   - Make it **replace** that date's rows (delete, then insert in one batch) so reruns are safe.
3. Log a summary line per run. On failure, the next run should detect missing dates in the last 7 days and fill them.

**Before moving on, check:**
- Running twice for the same date gives identical rows.
- The royalty total for a day equals the sum of `json_array_length(track_ids_json)` over that day's sessions.
- A session received at 23:59:59 UTC lands on the correct date.
