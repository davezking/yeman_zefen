#!/usr/bin/env bash
# Re-exports the design screenshots after a deliberate change to a screen:
#
#   app/tool/export_screens.sh
#
# Every screen and state, in English and Amharic, on a 360x780 and a 430x932
# phone, is drawn by the golden tests in app/test/design/ with the real fonts
# (Poppins, Noto Sans Ethiopic and the Material icons). The pictures are the
# goldens themselves: they are written to docs/design/flutter/
# <screen>-<state>-<lang>-<size>.png, and the gallery in docs/design/review.md
# is regenerated to link them. Without this script the golden tests fail on a
# changed screen, so the design and the code cannot drift apart.
set -euo pipefail

cd "$(dirname "$0")/.."

out=../docs/design/flutter
mkdir -p "$out"
# Start clean, so a screenshot of a screen that was removed does not stay behind.
rm -f "$out"/*.png

flutter test --update-goldens test/design

# Check what was written against the tests (the same run CI does).
flutter test test/design

echo "Exported $(ls "$out"/*.png | wc -l | tr -d ' ') screenshots to docs/design/flutter/."
echo "Review the changes with: git status docs/design"
