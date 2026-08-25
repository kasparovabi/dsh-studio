#!/bin/bash
# Build the mac app in Release and put it in /Applications.
# Refuses while the installed copy is running, because replacing a bundle out
# from under a live process crashes it on the next lazy resource load.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="/Applications/DSH Studio.app"
DERIVED="${DSH_DERIVED_DATA:-$ROOT/.build-mac}"

if pgrep -f "/Applications/DSH Studio.app/Contents/MacOS/DshStudio" > /dev/null; then
  echo "DSH Studio is running. Quit it first, then run this again." >&2
  exit 1
fi

# The signing file names a real developer team, so it is not in the tree. A
# fresh checkout gets the placeholder copy and still builds ad-hoc.
[ -f "$ROOT/Signing.xcconfig" ] || cp "$ROOT/Signing.example.xcconfig" "$ROOT/Signing.xcconfig"

xcodegen generate --project "$ROOT" > /dev/null
xcodebuild -project "$ROOT/DshStudio.xcodeproj" \
  -scheme DshStudio \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build > /dev/null

BUILT="$DERIVED/Build/Products/Release/DshStudio.app"
[ -d "$BUILT" ] || { echo "no build product at $BUILT" >&2; exit 1; }

rm -rf "$TARGET"
cp -R "$BUILT" "$TARGET"
echo "installed $TARGET"
