# Phase 4 · Sprint 1 — Production shell & localization

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

**Prerequisite:** the Phase 2 sign-off in `docs/design/review.md` is complete. The theme (`app/lib/core/theme/`), components (`app/lib/core/widgets/`), ARB strings, and prototype screens (`app/lib/prototype/screens/`, plain data plus callbacks) already exist. The approved screenshots are in `docs/design/screens/`.

**Convention for this whole phase:** to put a screen into production, **move** it from `prototype/screens/` to `features/<feature>/ui/`, have the prototype import it from there, and add a thin Riverpod wrapper that feeds real data and callbacks. Don't restyle; if something must change visually, update the screen and re-export screenshots in the same PR.

Goal: the real app shell, running on real data, fully bilingual.

---

## Task: Production localization and live language toggle

**Model:** sonnet — completing localization across real data, locale defaults, and layout checks in two scripts.

**Context:** ARB files `app/lib/l10n/app_en.arb` and `app_am.arb` hold every string from the Phase 2 copy deck. FR-18: full UI in both languages, defaulting from the device locale, with an in-app toggle. Track and artist names display in the current UI language (Fidel when `am`, Latin when `en`), with the other script as a subtitle where the approved screens show it.

**Do this:**
1. Add strings for any production-only messages not in the copy deck (real error messages from services, sync states). Mark new Amharic strings with `REVIEW` in their description for the native-speaker pass.
2. `localeProvider`: default from the device locale (`am` if the device language is Amharic, else `en`), persist the user's choice, and switch live with no restart.
3. A `DisplayName` helper picks the Fidel or Latin name for tracks and artists by locale.
4. A layout pass with **real catalog data** (long real titles are the risk): every production screen at text scale 1.3 in both locales.

**Before moving on, check:**
- `grep` finds no hard-coded user-facing strings in `lib/features/`.
- The longest real Amharic title in the catalog doesn't overflow the round screen or results list.
- The toggle switches language instantly, including the current screen.

---

## Task: Play-first clip delivery — starter clips, prefetch, clip cache

**Model:** sonnet — new data plumbing under the existing round engine, with download, cache and fallback rules that must never stall a round.

**Context:** Read "Play-first delivery" in `docs/architecture.md` §3. Today the app plays only from installed packs: `PackInstaller` and `ClipDownloader` (`app/lib/features/packs/data/`) download and checksum clips, `local_tracks` in `app/lib/core/db/app_db.dart` holds installed tracks, and `GameLibrary` (`app/lib/features/game/data/game_library.dart`) feeds `RoundGenerator` from them. Manifests are described in `docs/pack-manifest.md`; the published manifests together are the catalog, so no API change is needed. The goal is that a first launch plays at once from clips bundled in the app, online play downloads clips just ahead of use, and offline packs become an optional Settings feature (wired in a later task).

**Do this:**
1. **Starter clips.** `app/tool/fetch_starter_pack.dart`: fetches the current `starter` pack (via `GET /v1/packs` for the chosen flavor) and writes its manifest and clips to `app/assets/starter/`, verifying every SHA-256. Register the folder in `pubspec.yaml`. Commit the fetched files only if they're under 10 MB in total; otherwise fetch in CI before the build and document it in `docs/ops.md`. On first start (and after an app update that changes the starter manifest), register the starter tracks in the local catalog, playing straight from the assets with no copy if `just_audio` can, otherwise copying them once.
2. **Local catalog and clip store.** A drift migration adds:
   - `catalog_tracks`: track metadata from every known manifest, keyed by track id, with clip URLs, checksums, and sizes. It is refreshed from `/v1/packs` and the manifests on start (when online) and every 12 hours.
   - `clips`: one row per clip on the device (track id, intro or middle, path, bytes, source `starter | stream | pack`, last played at).
   
   Migrate the existing `local_tracks` rows into these tables so installed packs keep working, and make `GameLibrary` read from them.
3. **Round selection.** Tracks to ask about are those whose clip for the current mode is on the device, plus (when online and prefetch is allowed) tracks from the catalog. Distractors can be any catalog track. Keep the existing rules in `RoundGenerator` (variety, no repeats from `recent_sessions`) and its tests passing.
4. **Prefetcher** (`app/lib/features/packs/data/clip_prefetcher.dart`): when a session starts, keep the clips for the next 5 rounds downloaded, using `ClipDownloader` and checksum verification. When a round comes up and its clip isn't ready, swap in a track whose clip is on the device: same era as the session's filter, not already used in this session, and regenerate that round's options with `RoundGenerator`'s rules (distinct artists for artist questions). Only when no such track exists does the round wait, showing the designed "next song loading" state, and it is skipped without penalty if the download fails or takes over 10 s. Respect the "Download upcoming songs on mobile data" setting (default on) using `connectivity_plus`. Download only the clip the mode needs.
5. **Cache cap.** Clips with source `stream` are capped at 50 MB by default (a setting), evicting the least recently played first after each session. `starter` and `pack` clips are never evicted. Expose `clearStreamCache()` and a storage-usage provider for Settings.
6. Remove the "install a pack first" gate from the Phase 1 spike's start screen.
7. Tests: a first launch with no network plays a full session from starter clips; a slow fake downloader causes swaps, not waits, when on-device tracks exist for the era; an era with no on-device clips waits, then skips after 10 s; eviction keeps pack and starter clips; the `local_tracks` migration keeps installed packs playable; the data saver on cellular plays only on-device clips.

**Before moving on, check:**
- A fresh install in airplane mode plays a full session.
- Online, a 10-round session on a throttled connection (Android emulator network speed "EDGE") never shows a wait between rounds for "all eras".
- After many sessions, the stream cache stays under its cap and installed packs are untouched.
- Royalty data is unchanged: each session's `trackIds` lists exactly what was played, whatever the source.

---

## Task: Wire home, mode select, era/genre select, and settings screens

**Model:** haiku — moving existing screens and connecting them to existing providers.

**Context:** The four screens exist in `app/lib/prototype/screens/`. Real data comes from existing providers: the local catalog and clip store (previous task), generations and genres (from known manifests), local best scores, auth state, remote config, and settings.

**Do this:**
1. Move each screen to its feature folder per the phase convention and add the provider wrapper. Disable an era when fewer than 4 of its tracks are playable right now: on the device, or prefetchable when online and prefetch is allowed. Home never asks the player to download a pack.
2. Settings: wire the language toggle, sound, the account section (state only; actions come in Sprint 3), the privacy policy link, and the "Offline play" entry (its screen comes in the next task).
3. Make this the app's real `go_router` route tree, replacing the Phase 1 spike screens. Delete the spike screens.

**Before moving on, check:**
- Each screen matches its approved screenshot with real data.
- The prototype entry point still builds.

---

## Task: Wire Settings → Offline play: pack download and data settings

**Model:** sonnet — real download state, update detection, and the Wi-Fi rule all have to stay accurate in the UI.

**Context:** The Settings → Offline play screen (all states) exists in `app/lib/prototype/screens/`. `PackInstaller` (progress stream, install, upgrade), `isUpdateAvailable`, the clip store, `clearStreamCache()`, and the storage-usage provider exist. Packs are optional and live only here (see "Play-first delivery" in `docs/architecture.md` §3). FR-17 requires notifying users of new or updated packs. Pack downloads default to Wi-Fi only.

**Do this:**
1. Move the screen per the phase convention and drive every pack state from `PackInstaller`'s progress stream. Installing a pack marks its clips `pack` in the clip store; clips already cached from streaming are reused, not downloaded again.
2. If "Wi-Fi only" is on and the device is on cellular, show the designed confirm dialog with the size before downloading.
3. Show the update badge on the Settings tab and the Offline play entry when an installed pack has a newer version (check on start and every 12 hours). Never show a pack prompt on home or before play.
4. Wire "Wi-Fi only for pack downloads", "Download upcoming songs on mobile data", the storage-used line (starter, cached, packs), the cache cap, and "Clear cache" (stream clips only).
5. Delete-pack action frees storage (clips the stream cache could still use move to `stream` and fall under its cap). Downloads continue if the user leaves the screen, and progress is correct on return.

**Before moving on, check:**
- On cellular with Wi-Fi only on, nothing downloads without confirmation.
- Publishing a new pack version in the admin site makes the badge appear.
- Leaving and returning mid-download shows correct progress.
- With "Download upcoming songs on mobile data" off and the device on cellular, a session downloads nothing.
