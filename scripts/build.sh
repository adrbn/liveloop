#!/usr/bin/env bash
#
# Builds and signs LiveLoop.app for local use with a personal Apple team.
#
# The camera extension is a system extension; a free/personal team can run it
# once you enable developer mode (`systemextensionsctl developer on`). We build
# unsigned and then re-sign inside-out with a Development certificate + explicit
# entitlements, which sidesteps provisioning-profile limits of free teams.
#
# Override the team / identity via env vars if yours differ:
#   LIVELOOP_SIGN_ID   a codesigning identity (see `security find-identity -p codesigning -v`)
#   LIVELOOP_TEAM_ID   overrides the auto-detected team OU
#
set -euo pipefail
cd "$(dirname "$0")/.."

# Default to the first available Apple Development identity.
SIGN_ID="${LIVELOOP_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/{print $2; exit}')}"
if [[ -z "$SIGN_ID" ]]; then
  echo "✗ No 'Apple Development' signing identity found. Set LIVELOOP_SIGN_ID." >&2
  exit 1
fi
CONFIG="${CONFIG:-Release}"
DERIVED="build"
APP="$DERIVED/Build/Products/$CONFIG/LiveLoop.app"
EXT="$APP/Contents/Library/SystemExtensions/LiveLoopExtension.systemextension"

# The Mach service name of the camera extension MUST be prefixed by the team
# that signs it (the certificate OU), or the sandbox rejects it. Detect it from
# the cert so this is correct no matter which identity is used.
TEAM_ID="${LIVELOOP_TEAM_ID:-$(security find-certificate -c "$SIGN_ID" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | grep -o 'OU=[A-Z0-9]*' | head -1 | cut -d= -f2)}"
if [[ -z "$TEAM_ID" ]]; then
  echo "✗ Could not determine signing team for identity: $SIGN_ID" >&2
  exit 1
fi
echo "▶ Signing identity: $SIGN_ID"
echo "▶ Team (OU):        $TEAM_ID"

echo "▶ Generating Xcode project…"
xcodegen generate >/dev/null

echo "▶ Building (unsigned)…"
rm -rf "$DERIVED"
xcodebuild -project LiveLoop.xcodeproj -scheme LiveLoop -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

echo "▶ Stamping camera extension Mach service with team prefix…"
/usr/libexec/PlistBuddy -c \
  "Set :CMIOExtension:CMIOExtensionMachServiceName ${TEAM_ID}.com.adrbn.LiveLoop.Extension" \
  "$EXT/Contents/Info.plist"

echo "▶ Signing camera extension…"
codesign --force --options runtime --timestamp=none \
  --sign "$SIGN_ID" \
  --entitlements LiveLoopExtension/LiveLoopExtension.entitlements \
  "$EXT"

echo "▶ Signing app…"
codesign --force --options runtime --timestamp=none \
  --sign "$SIGN_ID" \
  --entitlements LiveLoop/LiveLoop.entitlements \
  "$APP"

echo "▶ Verifying signatures…"
codesign --verify --strict --verbose=2 "$APP"
echo "  app entitlements:"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -Eo 'system-extension.install|application-groups' | sed 's/^/    - /' | sort -u || true
echo "  extension team:"
codesign -dv "$EXT" 2>&1 | grep -E "TeamIdentifier" | sed 's/^/    /' || true

echo "✅ Built and signed: $APP"
