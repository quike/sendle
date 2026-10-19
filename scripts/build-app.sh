#!/bin/bash
# Builds Sendle.app, a menu bar app with no Dock icon, into build/: one binary for Apple silicon
# and Intel Macs.
#   SENDLE_VERSION=…     the version About shows (default 0.1.0)
#   APP_PATH=…           where to put the app (default build/Sendle.app)
#   CODESIGN_IDENTITY=…  the certificate to sign with (`security find-identity -p codesigning`).
#                        The default is "Sendle Local Signing" from scripts/make-signing-identity.sh,
#                        or an ad-hoc signature without it. macOS forgets Full Disk Access and the
#                        Keychain item's approval each time an ad-hoc signature changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_PATH:-$ROOT/build/Sendle.app}"
[[ "$APP" == /* ]] || APP="$PWD/$APP"
VERSION="${SENDLE_VERSION:-0.1.0}"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
LOCAL_IDENTITY="Sendle Local Signing"
[[ "$APP" == *.app ]] || { echo "APP_PATH must end in .app"; exit 1; }

cd "$ROOT"
# One build per architecture, each copied out before the next: some SwiftPM versions put every
# triple's product in the same folder.
SLICES="$(mktemp -d)"
trap 'rm -rf "$SLICES"' EXIT
for ARCH in arm64 x86_64; do
  echo "▸ Building for $ARCH"
  swift build -c release --product Sendle --triple "$ARCH-apple-macosx14.0"
  BIN="$(swift build -c release --triple "$ARCH-apple-macosx14.0" --show-bin-path)"
  cp "$BIN/Sendle" "$SLICES/Sendle-$ARCH"
done

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Sendle" "$SLICES"/Sendle-*
# The panel's images, the same for every architecture.
cp -R "$BIN/Sendle_SendleUI.bundle" "$APP/Contents/Resources/"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/scripts/AppIcon-source.png" \
  "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sendle</string>
  <key>CFBundleDisplayName</key><string>Sendle</string>
  <key>CFBundleIdentifier</key><string>io.github.quike.Sendle</string>
  <key>CFBundleExecutable</key><string>Sendle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
elif security find-identity -p codesigning | grep -F "\"$LOCAL_IDENTITY\"" >/dev/null; then
  codesign --force --options runtime --sign "$LOCAL_IDENTITY" "$APP"
else
  echo "  Signing ad hoc. Run scripts/make-signing-identity.sh once, so that Full Disk Access"
  echo "  and the Keychain item outlast rebuilds."
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ Done: $APP ($(lipo -archs "$APP/Contents/MacOS/Sendle"))"
