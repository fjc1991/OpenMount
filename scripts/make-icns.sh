#!/bin/sh
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swift scripts/make-icon.swift "$TMP/icon_1024.png" >/dev/null
SET="$TMP/AppIcon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z $d $d "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon_1024.png" docs/icon.png
echo "Wrote Resources/AppIcon.icns"
