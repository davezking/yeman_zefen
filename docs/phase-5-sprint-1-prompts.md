# Phase 5 · Sprint 1 — Hardening & release

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: observability, abuse protection, verified performance, signed release builds, and store paperwork, ready for closed beta on Google Play and TestFlight.

---

## Task: Crashlytics and structured Worker logging

**Model:** haiku — standard instrumentation using documented setup.

**Context:** Firebase is already configured per flavor. The Worker uses Hono with a request-ID middleware. Workers Logs is enabled in `wrangler.toml` via `[observability]`.

**Do this:**
1. App: add `firebase_crashlytics`. Route `FlutterError.onError` and `PlatformDispatcher.onError` to it. Set the UID as the user identifier (never email). Log non-fatal errors for pack install failures, sync parks, and audio failures. Disable collection in the dev flavor. Upload iOS dSYMs and Android mapping files as part of release builds.
2. Worker: a logging helper that writes one JSON line per request with `requestId`, `route`, `status`, `latencyMs`, `uidHash` (SHA-256 of the UID, truncated), `country`, and error code if any. Enable `[observability]` in `wrangler.toml`. Never log tokens or bodies.

**Before moving on, check:**
- A forced test crash appears in Crashlytics for the prod flavor's test build.
- Worker logs show request lines with no tokens or emails.

---

## Task: Rate limiting on the player API

**Model:** sonnet — protecting endpoints without blocking legitimate offline bursts (a player syncing 10 queued sessions at once).

**Context:** Player endpoints: `POST /v1/sessions`, `GET /v1/leaderboard*`, `PUT /v1/me`, `POST /v1/me/merge`, and `POST /v1/reports/clip`. Offline players may sync many sessions at once after reconnecting. Use Cloudflare's Workers Rate Limiting binding if it's available on the current plan; otherwise use a WAF rate-limiting rule for per-IP limits plus a lightweight per-UID check. Check the current Cloudflare docs for what the account's plan allows before choosing, and record the choice in `docs/ops.md`.

**Do this:**
1. Limits per UID: sessions 60/hour (bursts up to 20 allowed), merge 5/hour, me 30/hour, clip reports 10/day. Per IP: 300 requests/minute across `/v1`.
2. On exceeding a limit, return 429 with `Retry-After`. The app's sync loop must respect `Retry-After` (update `session_sync.dart` and its tests).
3. Tests for the limiter's middleware logic using a fake binding.

**Before moving on, check:**
- Syncing 15 queued sessions at once succeeds.
- A scripted loop of 100 session posts gets 429s, and the app backs off correctly.

---

## Task: Performance check against the p95 targets

**Model:** sonnet — measurement setup and targeted fixes.

**Context:** Targets: p95 under 300 ms for `/v1/packs`, `/v1/leaderboard`, and `/v1/sessions`. A staging Worker and D1 should exist for this. Create them now if not (`[env.staging]` in `wrangler.toml`, a separate D1, a seed script).

**Do this:**
1. Seed staging with realistic volume: 1,000 tracks, 20k users, 300k sessions, and leaderboard rows for 8 weeks.
2. Write a `k6` script (`ops/load/`) that simulates a mix: 70 % leaderboard reads, 20 % session posts with valid generated payloads and Firebase test tokens from a test project or a staging-only token bypass guarded by `ENV=staging`, and 10 % pack lists. Run at the equivalent of 2,000 DAU peak-hour traffic.
3. Report p50/p95/p99 per route in `docs/perf.md`. If any route misses its target, find the slow query with `EXPLAIN QUERY PLAN`, fix it with an index or query change, and re-run.
4. Also record D1 rows written per session from the run, to confirm the write budget in `docs/architecture.md` §9.

**Before moving on, check:**
- All three routes meet the p95 target, or the doc explains the remaining gap and next steps.
- The staging bypass can't be enabled in prod (a test asserts this).

---

## Task: Release pipeline — Android signing and CI build, iOS archive steps

**Model:** sonnet — signing and store-upload configuration where mistakes cost days.

**Context:** Android builds in GitHub Actions. iOS builds locally on your Mac with Xcode (macOS CI runners use free minutes fast). Both use the `prod` flavor. Store accounts: Google Play Console ($25, one-time) and Apple Developer Program ($99/year). Play's first upload must be an AAB with Play App Signing enabled.

**Do this:**
1. Android: create an upload keystore (document storing it safely and never committing it). Configure `key.properties` loading from env in CI. Add `.github/workflows/app-android.yml`, triggered by tag `app-v*`, which builds the prod AAB with obfuscation and split debug info, uploads mapping files to Crashlytics, and attaches the AAB as an artifact. Optionally add a Fastlane `supply` step to the Play internal track.
2. iOS: write `docs/release-ios.md` with exact steps:
   - signing (automatic) and bundle ID per flavor;
   - capabilities: Sign in with Apple, and push only if used (it isn't in v1);
   - `Info.plist` keys: `NSUserTrackingUsageDescription` (in Amharic and English) and `GADApplicationIdentifier`;
   - archive, then upload to TestFlight;
   - dSYM upload.
   Add a `make ios-release` (or `scripts/ios_release.sh`) that runs `flutter build ipa --flavor prod` with the right defines.
3. Versioning: `pubspec.yaml` version as the single source; the build number comes from the CI run number (Android) or a script (iOS).

**Before moving on, check:**
- A tag push produces a signed AAB that installs from the Play internal track.
- Following `docs/release-ios.md` uploads a build that installs from TestFlight.

---

## Task: Store compliance documents

**Model:** haiku — drafting documents from facts that are already decided; you review them before submitting.

**Context:** Data collected: Firebase UID, optional email and display name (if registered), country from IP, gameplay sessions, crash data (Crashlytics), and advertising ID and usage (AdMob, with consent). No SMS or phone number in v1. Account deletion exists in-app. Audience: general (not designed for children). Music is used under a license from the Ethiopian music association; Apple may ask for proof.

**Do this:**
1. `docs/legal/privacy-policy.md` (English) plus a structure ready for an Amharic version. It covers each data type, its purpose and processor (Firebase, Google AdMob, Cloudflare), retention, deletion, consent for EEA and UK users, and a contact address. Include a note to have a lawyer review it.
2. `docs/store/play-data-safety.md`: answers mapped to Google Play's Data safety form sections.
3. `docs/store/apple-privacy-labels.md`: answers for App Store Connect privacy labels, including "Used to Track You" for advertising data.
4. `docs/store/content-rating.md`: draft IARC and Apple age-rating questionnaire answers.
5. `docs/store/review-notes.md`: notes for Apple and Play reviewers explaining the music license (with a placeholder to attach the license letter), how to reach gameplay without an account, and a test account for registered features.

**Before moving on, check:**
- Every data type the app actually sends (check `ApiClient` calls, Crashlytics, and AdMob) appears in the policy and both store forms.
- The license proof placeholder is clearly marked as blocking store submission.

**Phase 5 exit:** signed builds in Play closed testing and TestFlight, with paperwork drafted. Start the closed beta via the Telegram and Facebook music groups. Write beta-fix sprint prompts from real feedback using this same template.
