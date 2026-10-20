#!/usr/bin/env bash
# Refuses a store build whose prod config is still a placeholder:
#
#   app/tool/check_release_config.sh android|ios
#
# Run by .github/workflows/app-android.yml and tool/ios_release.sh before anything is built.
# Errors stop the build; warnings only print.
set -euo pipefail

platform=${1:?usage: check_release_config.sh android|ios}
cd "$(dirname "$0")/.."

case "$platform" in
  android)
    # The prod line of admobAppIds in android/app/build.gradle.kts.
    admob_app_id=$(sed -n 's/.*"prod" to "\(ca-app-pub-[^"]*\)".*/\1/p' android/app/build.gradle.kts)
    unit_keys="ADMOB_INTERSTITIAL_ANDROID ADMOB_REWARDED_ANDROID"
    ;;
  ios)
    admob_app_id=$(sed -n 's/^ADMOB_APP_ID=\(.*\)$/\1/p' ios/Flutter/prodRelease.xcconfig)
    unit_keys="ADMOB_INTERSTITIAL_IOS ADMOB_REWARDED_IOS"
    ;;
  *) echo "usage: check_release_config.sh android|ios" >&2; exit 2 ;;
esac

python3 - "$platform" "$admob_app_id" "$unit_keys" <<'PY'
import json, sys

platform, admob_app_id, unit_keys = sys.argv[1], sys.argv[2], sys.argv[3].split()
cfg = json.load(open("config/prod.json"))
errors, warnings = [], []

api = cfg.get("API_BASE", "")
if not api.startswith("https://") or "TODO" in api:
    errors.append(f"config/prod.json API_BASE is '{api}': set the real https:// API domain")
if cfg.get("APP_FLAVOR") != "prod":
    errors.append("config/prod.json APP_FLAVOR must be 'prod'")
if not cfg.get("STORE_URL"):
    errors.append("config/prod.json STORE_URL is empty")

# docs/ops.md (Ads): real ad units with Google's sample app id must never ship.
sample = "ca-app-pub-3940256099942544"
units = [cfg.get(k, "") for k in unit_keys]
if not admob_app_id:
    errors.append("could not find the prod AdMob app id for " + platform)
elif admob_app_id.startswith(sample):
    if any(units):
        errors.append("prod has real ad units but still uses Google's sample AdMob app id")
    else:
        warnings.append("prod uses Google's sample AdMob app id and no ad units: the app ships without ads")
elif not all(units):
    warnings.append("prod has a real AdMob app id but a missing ad unit: that ad type will not show")

if not cfg.get("GOOGLE_SERVER_CLIENT_ID"):
    warnings.append("GOOGLE_SERVER_CLIENT_ID is empty: there is no Google sign-in button")

for w in warnings:
    print(f"warning: {w}")
for e in errors:
    print(f"error: {e}", file=sys.stderr)
sys.exit(1 if errors else 0)
PY
