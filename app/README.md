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
