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

## Task: Wire home, mode select, era/genre select, and settings screens

**Model:** haiku — moving existing screens and connecting them to existing providers.

**Context:** The four screens exist in `app/lib/prototype/screens/`. Real data comes from existing providers: installed packs, generations and genres (from installed manifests), local best scores, auth state, remote config, and settings.

**Do this:**
1. Move each screen to its feature folder per the phase convention and add the provider wrapper. Disable eras with fewer than 4 installed tracks, as designed.
2. Settings: wire the language toggle, sound, Wi-Fi only, the account section (state only; actions come in Sprint 3), and the privacy policy link.
3. Make this the app's real `go_router` route tree, replacing the Phase 1 spike screens. Delete the spike screens.

**Before moving on, check:**
- Each screen matches its approved screenshot with real data.
- The prototype entry point still builds.

---

## Task: Wire the pack browse and download screen

**Model:** sonnet — real download state, update detection, and the Wi-Fi rule all have to stay accurate in the UI.

**Context:** The pack browse screen (all states) exists in `app/lib/prototype/screens/`. `PackInstaller` (progress stream, install, upgrade) and `isUpdateAvailable` exist. FR-17 requires notifying users of new or updated packs. Downloads default to Wi-Fi only.

**Do this:**
1. Move the screen per the phase convention and drive every state from `PackInstaller`'s progress stream.
2. If "Wi-Fi only" is on and the device is on cellular, show the designed confirm dialog with the size before downloading.
3. Show the update badge on home and the packs tab when an installed pack has a newer version (check on start and every 12 hours).
4. Delete-pack action frees storage. Downloads continue if the user leaves the screen, and progress is correct on return.

**Before moving on, check:**
- On cellular with Wi-Fi only on, nothing downloads without confirmation.
- Publishing a new pack version in the admin site makes the badge appear.
- Leaving and returning mid-download shows correct progress.
