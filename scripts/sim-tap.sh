#!/bin/bash
# Tap the simulator at a point given in device points, then screenshot.
# Usage: sim-tap.sh <x> <y> [shot.png]
# Simulator.app must be open; simctl alone boots a runtime with no window.
set -u
X=$1
Y=$2
SHOT=${3:-/tmp/dsh-phone-tap.png}

geom=$(osascript -e 'tell application "System Events" to tell process "Simulator" to return (position of window 1) & (size of window 1)' | tr -d ' ')
WX=${geom%%,*}
rest=${geom#*,}
WY=${rest%%,*}
rest=${rest#*,}
WW=${rest%%,*}
WH=${rest#*,}

# The window is a device screen inside a drawn bezel. Both insets scale with the
# window, so they live here as fractions measured once on iPhone 17 Pro.
read -r PX PY < <(python3 -c "
ww, wh, wx, wy = $WW, $WH, $WX, $WY
inset = ww * 0.0644
top = wh * 0.0801
scale = (ww - 2 * inset) / 402.0
print(int(wx + inset + $X * scale), int(wy + top + $Y * scale))
")

osascript -e 'tell application "Simulator" to activate' >/dev/null
sleep 0.5
cliclick "c:$PX,$PY"
sleep "${TAP_SETTLE:-1.5}"
xcrun simctl io booted screenshot "$SHOT" >/dev/null 2>&1 && echo "saved $SHOT"
