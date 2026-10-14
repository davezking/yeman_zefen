# Phase 3 · Sprint 2 — Registration & leaderboards

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: guests can register with Google, email, or Apple without losing history. Registered players appear on the all-time and weekly leaderboards, overall and per era. Tunables come from the server.

---

## Task: Remote config endpoint + app config loader

**Model:** haiku — a small endpoint and a cached client fetch.

**Context:** Tunables from the PRD: interstitial frequency (default every 3 rounds), register-prompt threshold (default 5 sessions), and default clip length. Also a minimum supported app version for forced updates.

**Do this:**
1. `GET /v1/config` (public) returns `{ interstitialEveryRounds, registerPromptAfterSessions, registerPromptCooldownDays, minAppVersion, defaultClipMs }` from Worker vars, with a 10-minute cache header.
2. App `lib/core/config/remote_config.dart`: fetch on start, cache in drift or shared preferences, and fall back to the cached value, then to built-in defaults. If the app is older than `minAppVersion`, show a blocking "please update" screen with a store link.

**Before moving on, check:**
- Changing a var and redeploying changes app behavior after restart.
- Offline launch uses cached values.

---

## Task: Leaderboard endpoints

**Model:** sonnet — ranking queries with performance constraints.

**Context:** `leaderboard_entries(period, generation_id, user_id, points, updated_at)`, with PK and a `points DESC` index (see `api/src/db/schema.ts`). Period is `all` or the ISO week, such as `2026-W42`; generation 0 means all eras. FR-14: guests may view but never appear, and ranking requires registration. Shadow-banned users must not appear to others but must see themselves. Target: p95 under 300 ms.

**Do this:**
1. `GET /v1/leaderboard?period=all|week&generation=0..n`: top 100 joined to `users.display_name` and country, excluding `shadow_banned = 1` and deleted users. Ties break by earliest `updated_at`. Cache in the Workers Cache API for 60 s per (period, generation).
2. `GET /v1/leaderboard/me?...` (registered only): the caller's points and rank, where rank = 1 + count of visible entries with more points. A shadow-banned caller sees the rank they *would* have. Return `null` if there's no entry.
3. A shared helper `currentIsoWeek(date)` with tests at year boundaries (e.g. 2026-12-31, 2027-01-01).

**Before moving on, check:**
- A guest token gets the top 100 but 403 on `/me`.
- With 50k seeded entries locally, both endpoints stay fast (check `EXPLAIN QUERY PLAN` uses the index).
- A shadow-banned user is invisible in the top 100 but sees their own rank.

---

## Task: Account linking — Google, email, Apple + conflict merge + backfill

**Model:** opus — auth edge cases plus data migration; mistakes lose players' history or merge the wrong accounts.

**Context:** Players start as Firebase anonymous users with sessions stored server-side under that UID. Linking via `linkWithCredential` keeps the UID. If the credential already belongs to another Firebase user (`credential-already-in-use`, or `email-already-in-use` for email), linking fails. The intended behavior is then to sign into the existing account and merge the guest's history into it. Sign in with Apple is required on iOS (App Store guideline 4.8) and optional on Android. Server endpoints: `PUT /v1/me`, `POST /v1/sessions`, and the `requireUser` middleware.

**Do this:**
1. App `AuthService`:
   - `linkWithGoogle()` using `google_sign_in`.
   - `linkWithEmail(email, password)` and `signInWithEmail` for returning users, plus a password-reset email.
   - `linkWithApple()` using `sign_in_with_apple` with a SHA-256 hashed nonce, iOS only by default.
   - On success, force-refresh the ID token, then call `POST /v1/me/registered`.
   - On conflict: fetch the **anonymous ID token first**, then sign into the existing account with the same credential, then call `POST /v1/me/merge { anonymousIdToken }`.
2. Server:
   - `POST /v1/me/registered`: requires a non-anonymous token. Flip `is_anonymous = 0` and **backfill** leaderboard entries from this user's existing unflagged sessions (recompute per period and generation from `game_sessions`, idempotently by replacing the user's rows).
   - `POST /v1/me/merge`: verify `anonymousIdToken` with the same Firebase verifier, allowing an expired token up to 30 days old (verify the signature, then check age separately). Require that its UID is still anonymous in `users`. Move its `game_sessions` to the caller's UID, delete the anonymous user row, then run the same backfill. Make it idempotent.
3. Never merge two registered accounts; return 409.
4. Tests: link keeping the UID → backfill; conflict → merge; merge replay; an attempt to merge a registered UID (409); a forged or expired-beyond-30-days token (401); and leaderboard points equal to the sum of the backfilled sessions.

**Before moving on, check:**
- A guest with 3 synced sessions who links Google appears on the leaderboard with exactly those points.
- A guest on a second phone who signs into an existing Google account has their phone's sessions merged, and nothing is double-counted.
- No path lets one user claim another registered user's sessions.

---

## Task: Soft registration prompt logic

**Model:** haiku — counter and cooldown logic around existing auth calls.

**Context:** FR-13: after N completed sessions (from `/v1/config`, default 5), prompt the guest to register. The prompt can be dismissed, uses a cooldown (config `registerPromptCooldownDays`), and must never interrupt a round. Linking methods exist in `AuthService`.

**Do this:**
1. `lib/features/account/register_prompt_controller.dart`: count completed sessions locally. After the results screen of session N (and again after each cooldown), emit `shouldPrompt`. Also prompt when a guest taps "see my rank" on the leaderboard.
2. Persist the dismissal time. Never prompt registered users.
3. Unit tests for counting, cooldown, and registered-user suppression.

**Before moving on, check:**
- The prompt appears only on a results screen or from the leaderboard, never mid-round.
- After dismissal it stays hidden for the cooldown period.

---

## Task: Wire the prototype's sign-in and leaderboard screens to real services

**Model:** haiku — the screens already exist from Phase 2; this is connecting them to working services.

**Context:** The register sheet, display-name step, and leaderboard screens were built in Phase 2 as widgets taking plain data plus callbacks, in `app/lib/prototype/screens/`. `AuthService` linking methods, the register prompt controller, and the leaderboard endpoints now exist. Convention: when a screen goes live, **move** it to `app/lib/features/<feature>/ui/` and have the prototype import it from there, so there is only ever one copy of each screen.

**Do this:**
1. Move the register sheet and display-name step to `features/account/ui/` and the leaderboard screen to `features/leaderboard/ui/`. Update the prototype imports.
2. Add thin Riverpod-connected wrappers that feed real data and callbacks: the register sheet calls the `AuthService` link methods (Google, email, Apple on iOS) and shows errors; the display-name step calls `PUT /v1/me`; the leaderboard reads `/v1/leaderboard` and `/v1/leaderboard/me`, with offline and loading states.
3. Hook the register prompt controller to show the sheet on the results screen and from the leaderboard's "see my rank."

**Before moving on, check:**
- Every provider links successfully on its supported platform, end to end.
- A guest sees the leaderboard plus a register call-to-action instead of a rank.
- The prototype entry point still builds and shows the same screens with mock data.

**Phase 3 checkpoint:** two test phones (one Android, one iPhone) play as guests, register, and see each other on the weekly board with server-computed points.
