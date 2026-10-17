#!/bin/bash
# Creates "Sendle Local Signing", a self-signed code-signing certificate, once. build-app.sh signs
# with it, so macOS keeps Sendle's Full Disk Access and its Keychain item across rebuilds; an
# ad-hoc signature changes with every build. The certificate is good for ten years and is trusted
# by nothing but your own builds.
#   scripts/make-signing-identity.sh [keychain]   (default: your login keychain)
set -euo pipefail
NAME="Sendle Local Signing"
KEYCHAIN="${1:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\"" >/dev/null; then
  echo "✓ $NAME is already in $KEYCHAIN"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/certificate.cnf" <<CONFIG
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = $NAME
[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONFIG

# macOS's own LibreSSL writes a PKCS #12 file that `security import` can read.
PASSWORD="$(uuidgen)"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/certificate.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" \
  -name "$NAME" -passout "pass:$PASSWORD" -out "$WORK/identity.p12"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
echo "✓ Created $NAME in $KEYCHAIN"
echo "  The first build signed with it may ask to let codesign use the key: choose Always Allow."
