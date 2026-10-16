#!/bin/bash
# Builds Sendle.app, a menu bar app with no Dock icon, into build/.
#   CODESIGN_IDENTITY=…  sign with your own certificate (`security find-identity -v -p codesigning`).
#                        An ad-hoc signature changes with every build, and macOS may then ask
#                        for Full Disk Access again.
#   APP_PATH=…           where to put the app (default build/Sendle.app)
#   VERSION=…            the version About shows (default 0.1.0)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_PATH:-$ROOT/build/Sendle.app}"
VERSION="${VERSION:-0.1.0}"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
[[ "$APP" == *.app ]] || { echo "APP_PATH must end in .app"; exit 1; }

echo "▸ Building"
cd "$ROOT"
swift build -c release --product Sendle
BIN="$(swift build -c release --show-bin-path)/Sendle"
[ -x "$BIN" ] || { echo "Swift build failed"; exit 1; }

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sendle"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sendle</string>
  <key>CFBundleDisplayName</key><string>Sendle</string>
  <key>CFBundleIdentifier</key><string>io.github.quike.Sendle</string>
  <key>CFBundleExecutable</key><string>Sendle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"

echo "▸ Signing"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ Done: $APP"
