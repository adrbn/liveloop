#!/usr/bin/env bash
#
# Packages the signed LiveLoop.app into a distributable .dmg with a
# drag-to-Applications layout. Run scripts/build.sh first.
#
set -eo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Release}"
APP="build/Build/Products/$CONFIG/LiveLoop.app"
OUT="dist"

if [ ! -d "$APP" ]; then
  echo "x $APP not found - run scripts/build.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
[ -n "$VERSION" ] || VERSION="1.0.0"
DMG="$OUT/LiveLoop-$VERSION.dmg"

mkdir -p "$OUT"
rm -f "$DMG"

echo "Building DMG for LiveLoop $VERSION ..."
if create-dmg \
  --volname "LiveLoop $VERSION" \
  --window-pos 200 120 \
  --window-size 560 380 \
  --icon-size 110 \
  --icon "LiveLoop.app" 150 180 \
  --app-drop-link 410 180 \
  --hide-extension "LiveLoop.app" \
  --no-internet-enable \
  "$DMG" "$APP" >/dev/null 2>&1; then
  :
else
  echo "  (custom layout failed; using a simple DMG)"
  rm -f "$DMG"
  create-dmg --volname "LiveLoop $VERSION" --app-drop-link 410 180 "$DMG" "$APP" >/dev/null 2>&1 || true
fi

if [ -f "$DMG" ]; then
  echo "OK Packaged: $DMG ($(du -h "$DMG" | cut -f1))"
else
  echo "x DMG packaging failed." >&2
  exit 1
fi
