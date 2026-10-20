#!/usr/bin/env bash
# Builds the prod iOS app for the App Store / TestFlight, on a Mac with Xcode (docs/release-ios.md):
#
#   app/tool/ios_release.sh build      # checks the config, builds build/ios/ipa/*.ipa (obfuscated)
#   app/tool/ios_release.sh symbols    # uploads the dSYMs and Dart symbols of that build to Crashlytics
#
# The version is app/pubspec.yaml (the single source). The build number is the UTC time, YYMMDDHHMM, so it
# always goes up; set IOS_BUILD_NUMBER to use another (App Store Connect needs a new one per upload).
#
# `symbols` needs these in the environment:
#   IOS_GOOGLESERVICE_PLIST   path to the prod iOS app's GoogleService-Info.plist (Firebase console > Project
#                             settings > the iOS app). Keep it outside the repository.
# and the Firebase CLI logged in (`firebase login`) or GOOGLE_APPLICATION_CREDENTIALS set.
set -euo pipefail

cd "$(dirname "$0")/.."
action=${1:-build}
symbols_dir=build/symbols-ios
archive=build/ios/archive/Runner.xcarchive

build() {
  [ "$(uname)" = Darwin ] || { echo "error: iOS builds need a Mac with Xcode" >&2; exit 1; }
  tool/check_release_config.sh ios

  if ! git diff --quiet -- . ':!build'; then
    echo "error: uncommitted changes under app/. Release from a clean checkout of the tag." >&2
    exit 1
  fi

  name=$(sed -n 's/^version: *\([^+ ]*\)+.*/\1/p' pubspec.yaml)
  number=${IOS_BUILD_NUMBER:-$(date -u +%y%m%d%H%M)}
  echo "Building Yeman Zefen $name ($number)"

  flutter pub get
  flutter build ipa --release --flavor prod \
    --dart-define-from-file=config/prod.json \
    --obfuscate --split-debug-info="$symbols_dir" \
    --build-name="$name" --build-number="$number"

  echo
  echo "Built: $(ls build/ios/ipa/*.ipa)"
  echo "Next: upload it to App Store Connect (docs/release-ios.md, step 5), then run: tool/ios_release.sh symbols"
}

symbols() {
  : "${IOS_GOOGLESERVICE_PLIST:?set IOS_GOOGLESERVICE_PLIST to the prod GoogleService-Info.plist}"
  [ -d "$archive/dSYMs" ] || { echo "error: no archive at $archive: run '$0 build' first" >&2; exit 1; }
  # The app gets Firebase through Swift Package Manager, so Crashlytics' upload tool is in Xcode's package
  # checkout under DerivedData. ios/Pods is the place it would be if the project moved back to CocoaPods.
  uploader=$(find ios/Pods/FirebaseCrashlytics "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*FirebaseCrashlytics/upload-symbols' -o -path '*firebase-ios-sdk/Crashlytics/upload-symbols' \
    2>/dev/null | head -1 || true)
  [ -n "$uploader" ] || { echo "error: Crashlytics' upload-symbols not found: run '$0 build' first (it fetches the packages)" >&2; exit 1; }

  # Native frames: the app's and the frameworks' dSYMs from the archive.
  "$uploader" -gsp "$IOS_GOOGLESERVICE_PLIST" -p ios "$archive/dSYMs"

  # Dart frames: this build is obfuscated, so its Dart symbols are needed to read a stack trace.
  app_id=$(/usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$IOS_GOOGLESERVICE_PLIST")
  npx --yes firebase-tools@15 crashlytics:symbols:upload --app="$app_id" "$symbols_dir"
}

case "$action" in
  build) build ;;
  symbols) symbols ;;
  *) echo "usage: $0 build|symbols" >&2; exit 2 ;;
esac
