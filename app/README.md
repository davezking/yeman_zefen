# app/

The Flutter app (Android + iOS). See `docs/architecture.md` §2 and §8.

## Flavors and config

Two flavors, `dev` and `prod`. Each has its own app name and bundle/application id.
The API base URL and flavor name come from `config/<flavor>.json`, injected at build time:

```sh
flutter run --flavor dev  --dart-define-from-file=config/dev.json
flutter run --flavor prod --dart-define-from-file=config/prod.json
```

The app refuses to start without `--dart-define-from-file` (see `lib/core/config/app_config.dart`).

## Running on a phone

```sh
flutter devices
flutter run -d <id> --flavor dev --dart-define-from-file=config/dev.json
```

`config/dev.json` points at `10.0.2.2:8787`, which only the Android emulator understands. For a real phone, copy it
to `config/dev.local.json` (ignored by git), set `API_BASE` to your computer's address on the same Wi-Fi, for example
`http://192.168.1.20:8787`, and run the API with `wrangler dev --ip 0.0.0.0`. Then use
`--dart-define-from-file=config/dev.local.json`. Plain http is allowed only in the dev flavor on Android, and only to
local-network addresses on iOS.

Use `--profile` when measuring audio timing. Debug builds are slower. On iOS, set your Apple ID as the signing team for
the Runner target in `ios/Runner.xcworkspace` first, and turn on Developer Mode on the phone.

`config/prod.json` has a placeholder `API_BASE`. Set the real domain before a prod build.

## Code generation

Drift tables live in `lib/core/db/app_db.dart`. After changing them, run
`dart run build_runner build --delete-conflicting-outputs` and commit the generated `*.g.dart`.
Localizations are generated from `lib/l10n/*.arb` by `flutter pub get`.

## Checks

```sh
flutter analyze
flutter test
```

## Design tokens, theme and components

The approved design lives in `docs/design/` (see its README). The app takes its colors, type, spacing, radii,
shadows, sizes and motion from `docs/design/tokens.json`, never from literals:

```sh
dart run tool/gen_tokens.dart            # tokens.json -> lib/core/theme/tokens.dart (commit the result)
dart run tool/gen_tokens.dart --check    # fails if tokens.dart is stale; a test runs the same check
```

- `lib/core/theme/`: `tokens.dart` (generated, `ColorTokens.correctFill`, `SpacingTokens.n12`, ...), `app_theme.dart`
  (`buildAppTheme(locale)`), `app_text.dart` (the type scale per language, Fidel line heights), `game_tokens.dart`
  (a `ThemeExtension`: correct/wrong, timer, era colors, motion). Read them with `context.game` and `context.text`.
- `lib/core/widgets/`: the designed components, imported through `widgets.dart`. They take plain data and callbacks,
  never providers. `test/core/theme/no_hardcoded_values_test.dart` fails if a color, size or duration literal
  sneaks into the theme or the widgets.
- A grid of answers or eras must use `EqualHeightGrid`, not a fixed-aspect `GridView`: Amharic and text scale 1.3
  make cells taller, and a fixed ratio clips them.
- Widget tests load the real fonts with `loadAppFonts()` (`test/core/widgets/widget_kit.dart`). Without it every
  glyph is a fixed-width square and overflow checks mean nothing.

### Component gallery

Every component in every state, with an English/Amharic switch and a text scale 1.0/1.3 switch:

```sh
flutter run -t lib/main_gallery.dart
```

Compare it with the screenshots in `docs/design/screens/`. There is no dark theme: none was designed.

### Prototype screens (Phase 2)

The hi-fi screens on mock data, with no services or config. Home, Mode select, Era & genre, Settings, Settings ›
Offline play, the round (all its states), Results, the leaderboard and the sign-in sheets (account choice, email,
display name) are in, with the edge states: first launch, ad consent, forced update, offline notices, out of songs,
a late next song, a generic error and loading skeletons.

```sh
flutter run -t lib/main_prototype.dart
```

It is its own app, for trying on a phone. The `dev` flavor gives it its own application id and the name "Yeman Zefen
DEV", so it installs next to a real build, and it needs no `--dart-define-from-file`:

```sh
# Android: an APK to install (signed with the debug key)
flutter build apk --release --flavor dev -t lib/main_prototype.dart
# iPhone: from a Mac, with your Apple ID as the signing team (see above)
flutter run -d <id> --release --flavor dev -t lib/main_prototype.dart
```

The "prototype" workflow (Actions › prototype › Run workflow) builds the Android APK on GitHub and attaches it to the
run, so it can be downloaded without a Flutter install. Pull requests that touch the prototype build it too.
Navigation is `go_router` (`lib/prototype/prototype_router.dart`, paths in `prototype_paths.dart`): the first launch
and the forced update are redirects, and Back goes to Home when a screen was opened directly.

Settings › Language switches Amharic/English live. Play starts a game on a fake clock with no audio
(`lib/prototype/round_simulation.dart`): the real scorer counts the points, the answer window is the clip plus 5 s,
a right answer shows for 1 s, a wrong one for 5 s (a tap skips), the hint sheet closes after 8 s with the timer
stopped, and an ad follows every 3rd round. Backgrounding the app pauses it. With the system's "reduce motion" on, the
reveal pop, the score count-up, the sheet slide and the cassette reels become plain fades or stand still.

**The hidden dev menu** opens with three fingers on the screen at once (Ctrl+Shift+D on a keyboard); it has no button,
so testers do not see it. It switches the player (guest, guest on a first run, registered), the connection (Wi-Fi,
mobile, offline) and the language, and **jumps to any screen or state** (`lib/prototype/prototype_jumps.dart`; a test
opens every one in both languages). Below those, switches set up the variants: a failing download or sign-in, the
state of the score on Results, an empty or saved leaderboard, and the edge states:

- First launch: `main_prototype.dart` starts here (wordmark, then language, welcome, and straight into a game from the
  built-in songs, with no download or sign-up asked). The toggle replays it.
- Ad consent required: after the first finished game, the consent screen and then a placeholder where Google's UMP form
  appears, then Results. Settings › Ad privacy choices opens the same placeholder.
- Update required: the forced-update screen replaces Home; "Play offline" plays the songs on the phone.
- Every song played recently: offline, Play shows "out of songs" (browse packs, or play them again).
- Round 2's clip: on time, after 3 s ("Getting the next song…"), or never (skipped after 10 s, with a notice).
- Lists load slowly: the leaderboard and Offline play's pack list show their loading state for 2 s (skeletons after
  300 ms). Leaderboard fails: the next load shows the error, and Try again loads it.
- Sending offline games fails: games finished offline wait ("1 games waiting to be sent"); coming back online sends them,
  or says it will try again. Going offline mid-game shows a short notice.

- `lib/prototype/screens/`: one widget per screen (or sheet). Each takes plain data (`models.dart`) and callbacks, and imports no
  provider or service (`test/prototype/prototype_guards_test.dart` checks the imports). Phase 4 builds the same data
  from the real services and reuses these widgets.
- `lib/prototype/mock_data.dart`: 20 invented tracks across the five eras, four packs in four states, cache use and
  the guest and signed-in users. `prototype_model.dart` and `prototype_app.dart` only run the prototype.
- Strings come from the ARB files, which mirror `docs/design/copy.md` key for key (`test/prototype/prototype_guards_test.dart`
  fails when they differ). A key `round.hint.watch` is `roundHintWatch`. After editing an ARB file, `flutter gen-l10n`
  regenerates `lib/l10n/app_localizations*.dart` (they are committed).
- `test/prototype/screens_layout_test.dart` renders every screen variant in both languages at text scale 1.0 and 1.3
  on a 360 dp phone and fails on any overflow. `test/prototype/edge_states_test.dart` walks each edge state, and
  `test/prototype/navigation_test.dart` taps through each flow (first launch to register, settings to a pack download,
  the leaderboard, account deletion) and the dev menu.

### Screenshots for the design sign-off

`test/design/` draws every screen and state (the list is `screen_catalog.dart`) in `en` and `am` on a 360×780 and a
430×932 phone, as golden files in `docs/design/flutter/<screen>-<state>-<lang>-<size>.png`. They fail when a screen
changes, so the prototype and the screenshots cannot drift apart. After a deliberate change:

```sh
tool/export_screens.sh
```

It rewrites the screenshots and the gallery in `docs/design/review.md`, which sets each one beside its approved board
and holds the sign-off checklist. The fonts are loaded for real in the tests (`loadAppFonts` in
`test/core/widgets/widget_kit.dart`: Poppins, Noto Sans Ethiopic and the SDK's Material icons); without them every
glyph is a square. The goldens are only exact on the same Flutter version (3.47.7) and Linux text rendering as CI: if
the check fails on another machine for a screen you did not touch, regenerate them in the CI container or ignore it.

## Fonts

Poppins (Latin) and Noto Sans Ethiopic (Fidel), both SIL Open Font License (`assets/fonts/OFL-Poppins.txt`,
`assets/fonts/OFL.txt`). Each is the other's fallback, so neither script renders as boxes. Noto Sans Ethiopic is a
variable font, so the text styles ask for their weight with `fontVariations` (see `AppTextStyles`).
