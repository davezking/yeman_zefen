# Phase 1 · Sprint 4 — Flutter playable spike

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: prove the core loop on real hardware before any design work lands. A bare, unstyled app downloads a published pack, verifies it, and plays complete Guess-the-Intro rounds offline on a real Android phone and a real iPhone. These screens are throwaway; the engine and services are not.

---

## Task: Flutter scaffold — flavors, structure, fonts, local DB

**Model:** haiku — project setup with every library already chosen.

**Context:** The Flutter app lives in `app/`. Libraries: `flutter_riverpod`, `go_router`, `just_audio`, `drift` (+ `sqlite3_flutter_libs`), `background_downloader`, `path_provider`, `crypto`, `uuid`, `http`, `flutter_localizations` + `intl`. Font: Noto Sans Ethiopic, bundled as an asset. API base URLs: dev `http://10.0.2.2:8787` (Android emulator) or a LAN IP, and prod `https://api.<domain>`.

**Do this:**
1. `flutter create app` with org `com.yemanzefen`. Set up `dev` and `prod` flavors on both Android (productFlavors) and iOS (schemes and configurations), each with its own app name suffix and `API_BASE` via `--dart-define-from-file`.
2. Folder structure, feature-first: `lib/core/` (config, http, db, audio), `lib/features/packs/`, `lib/features/game/`, `lib/features/account/`, `lib/features/leaderboard/`, `lib/features/settings/`, `lib/l10n/`.
3. Bundle Noto Sans Ethiopic and make it the fallback in the base `ThemeData` so Fidel never renders as boxes. Add ARB scaffolding for `en` and `am` with 3 sample strings.
4. Drift database `AppDb` with tables `installed_packs` (slug, version, manifest_json, installed_at, total_bytes), `local_tracks` (id, pack_slug, fields from the manifest, intro_path, middle_path), and `pending_sessions` (id, payload_json, created_at, attempts, last_error). Include migration version 1.
5. Add `flutter analyze` and `flutter test` to CI.

**Before moving on, check:**
- Both flavors build and launch on an Android emulator and the iOS simulator.
- A test screen shows "የማን ዘፈን" correctly on both.
- `flutter analyze` is clean.

---

## Task: Pack download with checksum verification

**Model:** sonnet — download robustness and file integrity across both platforms.

**Context:** `GET /v1/packs` returns packs with `manifestUrl`. The manifest contract is in `docs/pack-manifest.md` (read it). Clip files are about 160 KB each, so a pack of 50 tracks is about 16 MB. Packs must be fully usable offline after download, and players may lose connectivity mid-download.

**Do this:**
1. `lib/features/packs/data/`:
   - `PacksApi` (list packs, fetch manifest, and parse it with a strict model that rejects unknown `schema` values).
   - `PackInstaller`, which:
     - downloads all clip files with `background_downloader` into `appSupportDir/packs/{slug}/v{version}/`, with up to 4 parallel downloads and resume on reconnect;
     - verifies each file's SHA-256 against the manifest, deleting and re-fetching up to 2 times on mismatch;
     - writes `installed_packs` and `local_tracks` in **one drift transaction only after every file verifies**;
     - deletes the previous version's folder after a successful upgrade.
2. Expose progress as a Riverpod `StreamProvider` (bytes and files done or total, current state: queued, downloading, verifying, installed, failed).
3. An `isUpdateAvailable` check comparing installed vs listed versions.
4. Tests: manifest parsing (valid, missing checksum, unknown schema), and installer logic with a fake downloader, including checksum mismatch → retry → success, mismatch ×3 → failed (no partial install), and an interrupted install leaving the previous version intact.

**Before moving on, check:**
- Airplane mode mid-download, then reconnecting, finishes the install.
- After install, the app plays with networking fully off (verified in the next tasks).
- A failed install never leaves a half-registered pack in the DB.

---

## Task: Clip playback service with just_audio, verified on both platforms

**Model:** sonnet — audio timing behavior differs between ExoPlayer and AVFoundation; this task is the PRD's "prototype the clip-seek early."

**Context:** Clips are pre-cut local MP3 files starting exactly at the musical moment, 10 s long. Difficulty plays only the first 3, 5, or 10 s. The game needs: start playback instantly when a round begins, stop exactly at the limit, stop instantly when the player answers, and report elapsed time for response timing.

**Do this:**
1. `lib/core/audio/clip_player.dart`: wrap one reused `AudioPlayer`.
   - `prepare(path, lengthMs)` sets a `ClippingAudioSource(child: AudioSource.file(path), start: Duration.zero, end: lengthMs)`.
   - `play()` returns when audio actually starts (listen for `playing && processingState == ready` and position advancing).
   - `stop()`.
   - Streams `elapsedMs` and `completed`.
   - **Preload the next round's clip** while the current one plays (use a second player or `ConcatenatingAudioSource`; pick whichever gives the lower measured start latency and note it in a code comment).
2. Configure the audio session (`audio_session` package) for game playback: don't duck other apps permanently, and handle interruptions (a phone call pauses the round).
3. A debug screen: pick any installed track, choose 3/5/10 s, play, and display measured start latency and actual stop position.
4. Run it on **a real Android phone and a real iPhone** and record the results (start latency, stop accuracy, any click or pop) in `docs/spikes/clip-playback.md`.

**Before moving on, check:**
- Start latency under ~150 ms with preload on both devices.
- The 3 s clip stops within ±50 ms of 3 s on both.
- An incoming call or notification sound doesn't crash or desync the player.

---

## Task: Round engine — question generation, distractors, provisional scoring

**Model:** sonnet — game logic that must exactly match the server's validation rules later.

**Context:** Rounds are generated on the device from installed packs (`local_tracks`). FR-8: 4 options, with distractors drawn from the same generation. Question kinds: `song` (options are track IDs) or `artist` (options are artist IDs, which must be 4 distinct artists). Scoring and sanity rules are in `docs/architecture.md` §4, "Scoring formula" (read only that part). Copy them verbatim into `docs/scoring.md` with worked examples. The server implements the same rules in Phase 3.

**Do this:**
1. `lib/features/game/domain/` as pure Dart with no Flutter imports:
   - `RoundGenerator(tracks, rng)` produces a session of N rounds for a mode (intro or middle), a generation filter (or all), and a question kind (song, artist, or mixed).
     - Avoid repeating a track within a session, and prefer tracks not seen in the player's last 3 sessions (pass the history in).
     - Distractors come from the same generation and are distinct. For `artist` questions, use distinct artists. If the same era lacks enough candidates, fall back to adjacent eras, then any era, and record a `distractorFallback` count.
     - Option order is shuffled.
   - `Scorer` implements `docs/scoring.md` exactly and returns per-round points and a total.
   - `SessionRecorder` builds the exact session payload in `docs/architecture.md` §5 ("Session payload"); copy the shape into `docs/session-payload.md`.
2. Make the RNG seedable for tests.
3. Tests: distractor rules (same era, distinct, artist-distinctness), the fallback path, no repeats, scoring worked examples from `docs/scoring.md` (including hint halving, the middle multiplier, response under 200 ms counting as invalid, and the response window), and payload shape.

**Before moving on, check:**
- Every worked example in `docs/scoring.md` has a passing test.
- A pack with only 3 artists in an era still produces valid artist questions through the fallback.
- The engine has zero Flutter or IO dependencies.

---

## Task: Bare round screen + session recorder

**Model:** sonnet — wiring engine, audio, and storage into a playable loop.

**Context:** `ClipPlayer`, `RoundGenerator`, `Scorer`, `SessionRecorder`, and `PackInstaller` exist. There's no auth or server sync yet; completed sessions are saved to `pending_sessions` for Phase 3 to send. Styling is not a goal; the M1 design replaces these screens in Phase 4.

**Do this:**
1. A minimal flow with plain Material widgets:
   - Packs list (install button with progress).
   - Start screen: pick mode, era, difficulty, and question kind.
   - Round screen: the clip auto-plays, a countdown bar runs for the answer window, and 4 option buttons appear. Tapping an option stops audio, shows right or wrong plus points for 1 s, then auto-advances.
   - Results screen: total score and per-round list.
2. Measure `responseMs` from the moment audio actually starts (from `ClipPlayer.play()` returning), not from screen build.
3. Session length is 10 rounds. On completion, store the payload in `pending_sessions` and keep a local best score per mode and era.
4. Missing clip file → skip that round and record a local error count (full handling comes in Phase 4).

**Before moving on, check:**
- With networking fully off, a full 10-round session plays on a real Android phone and a real iPhone.
- `pending_sessions` contains a payload that matches `docs/session-payload.md`.
- Response times look human (inspect a few; none at 0 ms).

**Phase 1 exit check:** ~200 approved tracks across all five eras in published packs, and the playable loop works offline on both platforms. If clip latency or stop accuracy failed the spike targets, resolve that before Phase 3.
