#!/bin/bash
# Drag inside the simulator, in device points, then screenshot.
# Usage: sim-drag.sh <x1> <y1> <x2> <y2> [shot.png]
set -u
X1=$1
Y1=$2
X2=$3
Y2=$4
SHOT=${5:-/tmp/dsh-phone-drag.png}

geom=$(osascript -e 'tell application "System Events" to tell process "Simulator" to return (position of window 1) & (size of window 1)' | tr -d ' ')
WX=${geom%%,*}
rest=${geom#*,}
WY=${rest%%,*}
rest=${rest#*,}
WW=${rest%%,*}
WH=${rest#*,}

read -r AX AY BX BY < <(python3 -c "
ww, wh, wx, wy = $WW, $WH, $WX, $WY
inset = ww * 0.0644
top = wh * 0.0801
scale = (ww - 2 * inset) / 402.0
def point(x, y):
    return int(wx + inset + x * scale), int(wy + top + y * scale)
ax, ay = point($X1, $Y1)
bx, by = point($X2, $Y2)
print(ax, ay, bx, by)
")

osascript -e 'tell application "Simulator" to activate' >/dev/null
sleep 0.5
cliclick "m:$AX,$AY" "dd:$AX,$AY" "m:$AX,$(( (AY + BY) / 2 ))" "m:$BX,$BY" "du:$BX,$BY"
sleep "${DRAG_SETTLE:-1.5}"
xcrun simctl io booted screenshot "$SHOT" >/dev/null 2>&1 && echo "saved $SHOT"
