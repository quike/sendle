#!/bin/bash
# Builds the disk image people download: build/Sendle-<version>.dmg and its SHA-256.
#   ./scripts/release-mac.sh
#   SENDLE_VERSION=1.2.0 UNSIGNED=1 ./scripts/release-mac.sh   (what CI runs after semantic-release)
#
# The version is SENDLE_VERSION, or the latest v* tag (see scripts/build-app.sh).
# UNSIGNED=1 signs the app ad hoc. Sendle has no Developer ID, so it is not notarized either way:
# macOS asks people to allow it once (README → Download).
# Needs uv (brew install uv), which runs dmgbuild to lay out the disk image.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LATEST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
LATEST_TAG="${LATEST_TAG#v}"
export SENDLE_VERSION="${SENDLE_VERSION:-${LATEST_TAG:-0.0.0}}"
# Its own folder, so a release build never replaces the app you run from build/.
APP="$ROOT/build/release/Sendle.app"
ART="$ROOT/build/dmg"
DMG="$ROOT/build/Sendle-$SENDLE_VERSION.dmg"
command -v uvx >/dev/null || { echo "Install uv first: brew install uv"; exit 1; }

APP_PATH="$APP" "$ROOT/scripts/build-app.sh"

mkdir -p "$ART"
swift "$ROOT/scripts/make-dmg-background.swift" "$ART/background.tiff"
echo "▸ Packing $DMG"
rm -f "$DMG"
uvx --quiet dmgbuild -s "$ROOT/scripts/dmg-settings.py" \
  -D app="$APP" -D background="$ART/background.tiff" \
  -D icon="$APP/Contents/Resources/AppIcon.icns" "Sendle $SENDLE_VERSION" "$DMG"
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"
echo "✓ $DMG"
