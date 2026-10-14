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

## Fonts

Noto Sans Ethiopic (SIL Open Font License, see `assets/fonts/OFL.txt`) is the fallback font,
so Fidel never renders as boxes.
