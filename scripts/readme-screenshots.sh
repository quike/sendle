#!/bin/bash
# Renders the README's screenshots into docs/ with snapshot mode, reading the fixture library from
# make-fixture-library.swift instead of your Books library. A throwaway home and data folder keep
# covers, settings and history out of your own. Needs ImageMagick (brew install imagemagick).
# Usage: scripts/readme-screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v magick >/dev/null || {
  echo "Needs ImageMagick: brew install imagemagick" >&2
  exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/sendle-readme.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/.cargo/bin" "$work/data" "$work/shots"

swift build --product Sendle
library=$(swift scripts/make-fixture-library.swift "$work/library")

# Lets the USB side show EPUBs as sendable; snapshot mode never runs it.
printf '#!/bin/sh\nexit 1\n' >"$work/home/.cargo/bin/boko"
chmod +x "$work/home/.cargo/bin/boko"

cat >"$work/data/settings.json" <<'JSON'
{
  "email": {
    "kindleAddress": "my-kindle@kindle.com",
    "provider": "iCloud",
    "senderAddress": "you@icloud.com",
    "server": { "host": "smtp.mail.me.com", "port": 587, "security": "startTLS" }
  },
  "kindleAddresses": ["my-kindle@kindle.com", "paperwhite@kindle.com"]
}
JSON

echo "Rendering the panel (about two minutes)…"
CFFIXED_USER_HOME="$work/home" SENDLE_LIBRARY_DB="$library" SENDLE_DATA_DIR="$work/data" \
  SENDLE_SNAPSHOT_DIR="$work/shots" "$(swift build --show-bin-path)/Sendle"

# Writes $1 from the rest of the arguments, as a compressed PNG without metadata.
optimise() {
  local output=$1
  shift
  magick "$@" -strip -define png:compression-level=9 -define png:compression-filter=5 \
    -define png:exclude-chunks=date,time "$output"
}
# Each panel without the window's empty margins.
for shot in floating-send-card queue-sending kindle-grid edit-epub settings-sender; do
  magick "$work/shots/$shot.png" -trim +repage "$work/$shot.png"
done
optimise docs/hero.png "$work/floating-send-card.png" "$work/queue-sending.png" \
  "$work/kindle-grid.png" -background none -gravity north +smush 64
optimise docs/edit.png "$work/edit-epub.png"
optimise docs/settings.png "$work/settings-sender.png"
ls -l docs/hero.png docs/edit.png docs/settings.png
