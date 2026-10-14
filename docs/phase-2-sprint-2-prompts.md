# Phase 2 · Sprint 2 — UI: theme, hi-fi screens & clickable prototype

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: turn the designs you approved in artifacts (Sprint 1 handoff package in `docs/design/`) into **real Flutter screens running on mock data**, plus a clickable prototype on your phone and screenshots to compare against the approved designs. After sign-off, Phase 4 wires these same screens to real data instead of rebuilding them.

---

## Task: Flutter theme and component library from tokens

**Model:** sonnet — translating a design system into a well-structured Flutter theme takes judgment about structure, not just copying values.

**Context:** `docs/design/tokens.json` defines the system. The approved screen designs are HTML in `docs/design/artifacts/` and images in `docs/design/screens/`. The Flutter app is in `app/` (Material 3, Riverpod, Noto Sans Ethiopic bundled). Fidel needs its own line heights, and correct/wrong states use an icon as well as color.

**Do this:**
1. `app/lib/core/theme/`:
   - `tokens.dart`: generated from `tokens.json` by `app/tool/gen_tokens.dart`, so tokens change in one place.
   - `app_theme.dart`: light and dark if defined, with a `ThemeExtension` for game tokens (correct/wrong, timer, era accents, motion).
   - A per-locale `TextTheme` applying Fidel line heights when the locale is `am`.
2. `app/lib/core/widgets/`: primary and secondary buttons; an answer option tile (idle, selected, correct, wrong, disabled, hint-removed); a timer bar; a playing indicator (animated, with reduced motion respected); era chip and era card; pack card (download states); score badge; list row; dialog; and bottom sheet. Each takes plain data, not providers.
3. `app/lib/main_gallery.dart`: a component gallery showing every component in every state, with a toggle between `en`/`am` and light/dark.

**Before moving on, check:**
- No hard-coded colors, sizes, or durations outside `tokens.dart`.
- The gallery's components match the approved artifact designs in `docs/design/screens/`, in both languages.
- Changing one value in `tokens.json` and re-running the generator updates the gallery.

---

## Task: Hi-fi screens, part 1 — home, mode, era/genre, settings with offline play

**Model:** sonnet — composing polished screens from components to match the approved designs, in two scripts.

**Context:** The approved designs are in `docs/design/artifacts/` (HTML source; read exact sizes and spacing from it) and `docs/design/screens/` (images), with specs in `screens.md`, copy in `copy.md`, and components in `app/lib/core/widgets/`. The prototype runs on **mock data only**, with no services. Move every string from `copy.md` into `app/lib/l10n/app_en.arb` and `app_am.arb` now; the production phase reuses them.

**Do this:**
1. `app/lib/prototype/mock_data.dart`: realistic mock data with about 20 real-looking tracks across all five eras (Fidel and Latin names), 4 packs in different download states, clip-cache usage (MB used of the cap), and a mock user (guest and registered variants).
2. Screens in `app/lib/prototype/screens/`, each a widget taking plain data plus callbacks (no providers inside), so Phase 4 can wire them up directly: home (guest and returning variants), mode select (intro / middle / era-guess, plus difficulty), era & genre select (eras with too few songs available are disabled, offline only, with "download a pack in Settings"), settings (language toggle, sounds, account section in guest and registered variants, privacy options entry, and an "Offline play" entry with an update badge variant), and **Settings → Offline play** (pack list: not installed, downloading, installed, update available, delete confirm, cellular confirm; plus "Wi-Fi only for pack downloads", "Download upcoming songs on mobile data", storage used, and "Clear cache"). Home has no pack prompt; see "Play-first delivery" in `docs/architecture.md` §3.
3. Use the ARB strings, with a live `am`/`en` switch.

**Before moving on, check:**
- Each screen matches its approved artifact design side by side.
- No overflow in either language at text scale 1.0 and 1.3 on a 360-dp-wide screen.
- No screen imports a provider or service.

---

## Task: Hi-fi screens, part 2 — round, feedback, results, leaderboard, sign-in

**Model:** sonnet — the core game screens need careful motion and state design.

**Context:** Same inputs as part 1. The round screen's approved layout and interactive behavior are in its artifact in `docs/design/artifacts/`. Motion durations and curves are in the tokens. The round rules: the clip plays, the timer runs for clip length + 5 s, tapping an answer locks input and reveals correct and wrong, points animate, then the screen auto-advances. A rewarded hint removes 2 wrong options.

**Do this:**
1. Screens in `app/lib/prototype/screens/`:
   - Round, with all states: clip playing, answering, correct reveal, wrong reveal with the correct answer shown, hint available, hint applied, time-out, and paused or backgrounded.
   - Feedback micro-animations.
   - Results: provisional score, synced score, new-best variant, and the register-prompt variant.
   - Leaderboard: weekly/all-time, era filter, guest with call-to-action, registered with pinned own rank, offline.
   - Register sheet: Google, email, and Apple (iOS only), plus error states.
   - Display-name step.
2. Simulate the round in the prototype with a fake timer and fake "playing" state (no real audio needed), so motion and pacing can be judged.
3. Respect reduced-motion settings: replace motion with fades.

**Before moving on, check:**
- One complete mock round, from clip start to auto-advance, feels right at the token timings on a real phone.
- Correct and wrong are distinguishable in grayscale (take a screenshot and desaturate it).
- Both languages work on every screen.

---

## Task: Edge states — first launch, consent, offline, empty, update, errors

**Model:** haiku — screens to an already-decided pattern, using the existing components.

**Context:** `screens.md` lists the implied states. Components and the screen pattern from parts 1 and 2 exist in `app/lib/prototype/screens/`.

**Do this:**
1. Add prototype screens for: first launch (what a guest sees before the first round: straight into play from the bundled starter clips, with no download or sign-up prompt), an ad-consent placeholder (where the UMP form appears, and the in-settings privacy options entry), forced update, offline banners and full-screen offline states, out of songs (offline and every clip on the device recently played, with a link to Settings → Offline play), next clip still downloading (a short wait on a slow connection), generic error with retry, and loading skeletons for the leaderboard and the offline-play pack list.
2. Use only existing components and tokens. If a new component is truly needed, add it to `app/lib/core/widgets/` and the gallery.

**Before moving on, check:**
- Every state in `screens.md` now has a prototype screen.
- The wording comes from the ARB files in both languages.

---

## Task: Clickable prototype and screenshot export for sign-off

**Model:** sonnet — navigation wiring plus golden-test export, with font loading that's easy to get wrong.

**Context:** All prototype screens exist in `app/lib/prototype/screens/` with mock data. The navigation between screens is described in `docs/design/screens.md`. The sign-off review needs screenshots in both languages and two sizes, and a prototype to try on a phone. Golden tests render text as blank boxes unless real fonts are loaded in the test.

**Do this:**
1. `app/lib/main_prototype.dart`: wire every flow with `go_router` over mock data (first launch → session → results → register; settings → offline play → pack download; leaderboard; settings toggle; account deletion). Add a hidden debug menu to jump to any screen or state, and to switch guest/registered, online/offline, and `en`/`am`. Make it buildable as its own entry point on both platforms.
2. Golden tests in `app/test/design/`: render every screen and state in `en` and `am`, at 360×780 and 430×932. Load Noto Sans Ethiopic and the Latin family with `FontLoader` so Fidel renders. Add a script `app/tool/export_screens.sh` that updates the goldens and copies them to `docs/design/flutter/<screen>-<state>-<lang>-<size>.png`.
3. `docs/design/review.md`: a gallery page placing each Flutter screenshot next to its approved artifact design plus a sign-off checklist covering: every PRD key screen in both languages; native-speaker Amharic review done; 3–5 target users (domestic and diaspora) tried the prototype, with notes; accessibility checks; and your approval line with date.

**Before moving on, check:**
- The prototype installs and runs on a real Android phone and a real iPhone, and every screen is reachable by tapping through.
- Exported screenshots show proper Fidel, not boxes or blanks.
- `review.md` links every exported screenshot.

**Phase 2 exit (M1 sign-off):** you complete the checklist in `docs/design/review.md`, including the native Amharic review and a short test with real players (Telegram or Facebook music groups are a good source). Design changes after this point go through a PR that updates the prototype screens and re-exports screenshots, so the design and the code never drift apart.
