#!/bin/bash
# Build the 1280x640 card GitHub shows when the repo link is shared.
# Upload it by hand: repo Settings, Social preview, Edit, Upload an image.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/social-preview.png"
FONT="/System/Library/Fonts/SFNS.ttf"

magick -size 1280x640 "xc:#111113" \
  \( "$ROOT/docs/logo-dark.png" -resize 200x200 \) -gravity west -geometry +130+0 -composite \
  -font "$FONT" -fill "#FFFFFF" -pointsize 78 \
  -annotate +390+-16 "dsh-studio" \
  -font "$FONT" -fill "#8A8A8E" -pointsize 32 \
  -annotate +392+48 "A native client for the dsh coding agent" \
  "$OUT"

echo "$OUT"
