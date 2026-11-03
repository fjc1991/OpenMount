#!/bin/sh
# Builds OpenMount.app into ./dist (universal: arm64 + x86_64).
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
swift build -c release --product OpenMount --arch arm64 --arch x86_64
BIN="$(swift build -c release --product OpenMount --arch arm64 --arch x86_64 --show-bin-path)/OpenMount"
APP=dist/OpenMount.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenMount"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>OpenMount</string>
  <key>CFBundleDisplayName</key><string>OpenMount</string>
  <key>CFBundleIdentifier</key><string>io.github.openmount.OpenMount</string>
  <key>CFBundleExecutable</key><string>OpenMount</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licensed. Not affiliated with be quiet!.</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime "$APP"
echo "Built $APP"
