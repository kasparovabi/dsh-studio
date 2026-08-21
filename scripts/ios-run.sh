#!/bin/bash
# Build the phone app, put it on the simulator and bring back a screenshot.
# Never touches the Mac app or the server it talks to.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE=${DSH_SIM:-"iPhone 17 Pro"}
SHOT=${1:-/tmp/dsh-phone.png}
APP="$ROOT/build-ios/Build/Products/Debug-iphonesimulator/DshStudioIOS.app"
BUNDLE=com.kasparov.dshstudio.phone

cd "$ROOT"
xcodegen generate >/dev/null || exit 1
out=$(xcodebuild -project DshStudio.xcodeproj -scheme DshStudioIOS -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build-ios build 2>&1)
if ! grep -q 'BUILD SUCCEEDED' <<<"$out"; then
  grep -E 'error:' <<<"$out" | head -20
  exit 1
fi

udid=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$udid" ] || { echo "no simulator named $DEVICE"; exit 1; }
state=$(xcrun simctl list devices | grep "$udid" | grep -o 'Booted' || true)
[ -n "$state" ] || xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1

xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$udid" "$APP" || exit 1
if [ -n "${DSH_PORT:-}" ]; then
  SIMCTL_CHILD_DSH_STUDIO_PORT="$DSH_PORT" xcrun simctl launch "$udid" "$BUNDLE" >/dev/null || exit 1
else
  xcrun simctl launch "$udid" "$BUNDLE" >/dev/null || exit 1
fi
sleep "${DSH_SETTLE:-4}"
xcrun simctl io "$udid" screenshot "$SHOT" >/dev/null 2>&1 && echo "saved $SHOT"
