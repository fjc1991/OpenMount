#!/bin/sh
# Packages dist/OpenMount.app into dist/OpenMount-<version>.dmg with an Applications shortcut.
# Run ./scripts/build-app.sh first.
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OpenMount.app/Contents/Info.plist)}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/OpenMount.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/OpenMount-v${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "OpenMount ${VERSION}" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign - "$DMG"
echo "Built $DMG"
