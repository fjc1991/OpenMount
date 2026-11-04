#!/bin/sh
# Packages dist/OpenMount.app into dist/OpenMount-<version>.dmg with an Applications shortcut and
# the illustrated "How to open OpenMount" guide.
# The DMG is deliberately left unsigned: on macOS 15+ an ad-hoc-signed disk image is itself blocked
# by Gatekeeper, whereas an unsigned one opens normally and only the app needs approving.
# Run ./scripts/build-app.sh first.
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OpenMount.app/Contents/Info.plist)}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/OpenMount.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
./scripts/make-install-guide.sh "$STAGE/How to open OpenMount.html" >/dev/null
# Window layout (app left, Applications right, guide below), saved once with Finder.
cp Resources/dmg-layout.DS_Store "$STAGE/.DS_Store"
DMG="dist/OpenMount-v${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "OpenMount ${VERSION}" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
