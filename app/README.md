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
display name) are in; edge states (first launch, consent, offline, empty, update, errors) are next.

```sh
flutter run -t lib/main_prototype.dart
```

Settings › Language switches Amharic/English live. Play starts a game on a fake clock with no audio
(`lib/prototype/round_simulation.dart`): the real scorer counts the points, the answer window is the clip plus 5 s,
a right answer shows for 1 s, a wrong one for 5 s (a tap skips), the hint sheet closes after 8 s with the timer
stopped, and an ad follows every 3rd round. Backgrounding the app pauses it. With the system's "reduce motion" on, the
reveal pop, the score count-up, the sheet slide and the cassette reels become plain fades or stand still.

The flask icon at the top right opens a dev-only sheet for trying the variants: signed in, first run, offline, mobile
data, a failing download or sign-in, the state of the score on Results, an empty or saved leaderboard.

- `lib/prototype/screens/`: one widget per screen (or sheet). Each takes plain data (`models.dart`) and callbacks, and imports no
  provider or service (`test/prototype/prototype_guards_test.dart` checks the imports). Phase 4 builds the same data
  from the real services and reuses these widgets.
- `lib/prototype/mock_data.dart`: 20 invented tracks across the five eras, four packs in four states, cache use and
  the guest and signed-in users. `prototype_model.dart` and `prototype_app.dart` only run the prototype.
- Strings come from the ARB files, which mirror `docs/design/copy.md` key for key (`test/prototype/prototype_guards_test.dart`
  fails when they differ). A key `round.hint.watch` is `roundHintWatch`. After editing an ARB file, `flutter gen-l10n`
  regenerates `lib/l10n/app_localizations*.dart` (they are committed).
- `test/prototype/screens_layout_test.dart` renders every screen variant in both languages at text scale 1.0 and 1.3
  on a 360 dp phone and fails on any overflow.

## Fonts

Poppins (Latin) and Noto Sans Ethiopic (Fidel), both SIL Open Font License (`assets/fonts/OFL-Poppins.txt`,
`assets/fonts/OFL.txt`). Each is the other's fallback, so neither script renders as boxes. Noto Sans Ethiopic is a
variable font, so the text styles ask for their weight with `fontVariations` (see `AppTextStyles`).
