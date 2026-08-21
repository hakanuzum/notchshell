#!/bin/bash
# Create the long-lived self-signed identity that build-install.sh signs with.
#
# Why this exists: TCC keys permission grants on the code signature. An ad-hoc
# build gets a fresh signature every time, so every rebuild — and every shipped
# update — forgot the user's Accessibility and Screen Recording grants. Signing
# every build with one stable certificate gives the app one identity for life:
# grants given once survive updates, and only a genuinely new permission is ever
# asked for again. A Developer ID does the same job (and adds notarization); this
# is the no-account version, and switching to a Developer ID later costs one more
# re-grant, same as the switch to this cert did.
#
# One-time per machine. Interactive: macOS asks for the login password once to
# trust the certificate for code signing, and the first build that uses the key
# pops "codesign wants to sign" — answer Always Allow.
#
# The identity name is deliberately generic. Which identity a given machine signs
# with still comes from NOTCHSHELL_SIGNING_IDENTITY (see build-install.sh); this
# script just makes that variable have something to point at.
set -euo pipefail

NAME="${1:-Notchshell Signing}"
DAYS=3650
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
    echo "==> Identity \"$NAME\" already exists; nothing to do."
    echo "    export NOTCHSHELL_SIGNING_IDENTITY=\"$NAME\""
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating certificate \"$NAME\" (valid $DAYS days)..."
openssl req -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days "$DAYS" -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -out "$TMP/cert.pem" 2>/dev/null

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:notchshell-temp -out "$TMP/cert.p12"

echo "==> Importing into the login keychain..."
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P notchshell-temp -T /usr/bin/codesign

echo "==> Trusting it for code signing (macOS will ask for your password)..."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "==> Verifying..."
if security find-identity -v -p codesigning | grep -qF "\"$NAME\""; then
    echo "==> Done. Point builds at it:"
    echo "    export NOTCHSHELL_SIGNING_IDENTITY=\"$NAME\"     # bash/zsh"
    echo "    set -Ux NOTCHSHELL_SIGNING_IDENTITY \"$NAME\"    # fish"
else
    echo "!! Identity did not come out valid — check Keychain Access." >&2
    exit 1
fi
