#!/usr/bin/env bash
#
# Packages LiveLoop.app into dist/LiveLoop-<version>.dmg with a
# drag-to-Applications layout. scripts/release.sh runs it on the notarized
# export; pass another .app to package that one instead.
#
#   scripts/make_dmg.sh [path/to/LiveLoop.app]   (default: build/export/LiveLoop.app)
#
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

APP="${1:-build/export/LiveLoop.app}"
[ -d "$APP" ] || fail "$APP not found: run scripts/release.sh first, or pass the app to package."
need create-dmg "brew install create-dmg"

VERSION="$(app_version "$APP")"
DMG="$(dmg_path "$APP")"

step "Packaging $DMG"
mkdir -p dist "$LOG_DIR"
rm -f "$DMG" dist/rw.*.dmg
# The custom window layout is set through Finder, which can fail without a GUI
# session; a plain DMG with the Applications link still installs the same way.
if ! create-dmg \
  --volname "LiveLoop $VERSION" \
  --window-pos 200 120 --window-size 560 380 --icon-size 110 \
  --icon "LiveLoop.app" 150 180 --app-drop-link 410 180 \
  --hide-extension "LiveLoop.app" --no-internet-enable \
  "$DMG" "$APP" >"$LOG_DIR/dmg.log" 2>&1; then
  note "custom layout failed (see $LOG_DIR/dmg.log), making a plain DMG"
  rm -f "$DMG" dist/rw.*.dmg
  run dmg-plain create-dmg --volname "LiveLoop $VERSION" --app-drop-link 410 180 "$DMG" "$APP"
fi
[ -f "$DMG" ] || fail "create-dmg finished but wrote no $DMG"
ok "$DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
