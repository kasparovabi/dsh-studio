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

command -v xcodegen > /dev/null || {
  echo "xcodegen is not on PATH. brew install xcodegen, then run this again." >&2
  exit 1
}

# The signing file names a real developer team, so it is not in the tree. A
# fresh checkout gets the placeholder copy and still builds ad-hoc.
[ -f "$ROOT/Signing.xcconfig" ] || cp "$ROOT/Signing.example.xcconfig" "$ROOT/Signing.xcconfig"

# The phone spec is a superset and is the one to use when it is present, so
# generating for the Mac does not silently drop the phone target from the
# project the other script just wrote.
SPEC="project.yml"
[ -f "$ROOT/project.phone.yml" ] && SPEC="project.phone.yml"
(cd "$ROOT" && xcodegen generate --spec "$SPEC" > /dev/null)
xcodebuild -project "$ROOT/DshStudio.xcodeproj" \
  -scheme DshStudio \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build > /dev/null

BUILT="$DERIVED/Build/Products/Release/DshStudio.app"
[ -d "$BUILT" ] || { echo "no build product at $BUILT" >&2; exit 1; }

# The old bundle is only removed once its replacement is sitting next to it,
# so a failed copy leaves the installed app intact.
STAGE="$TARGET.new"
rm -rf "$STAGE"
cp -R "$BUILT" "$STAGE"
rm -rf "$TARGET"
mv "$STAGE" "$TARGET"
echo "installed $TARGET"
