#!/usr/bin/env bash
#
# Full release pipeline: archive -> Developer ID export -> notarize -> staple ->
# notarized DMG. Produces a build that installs and activates its camera
# extension on any Mac with SIP on.
#
# Prerequisites (one-time):
#   1. A paid Apple Developer Program membership (team 2TWQF4T93E).
#   2. Notarization credentials stored in the keychain:
#        xcrun notarytool store-credentials "LiveLoop" \
#          --apple-id "you@example.com" --team-id 2TWQF4T93E
#
set -eo pipefail
cd "$(dirname "$0")/.."

TEAM="${LIVELOOP_TEAM_ID:-2TWQF4T93E}"
PROFILE="${LIVELOOP_NOTARY_PROFILE:-LiveLoop}"
ARCHIVE="build/LiveLoop.xcarchive"
EXPORT="build/export"
APP="$EXPORT/LiveLoop.app"

echo "> Generating project..."
xcodegen generate >/dev/null

echo "> Archiving (automatic signing, team $TEAM)..."
rm -rf "$ARCHIVE"
xcodebuild archive -project LiveLoop.xcodeproj -scheme LiveLoop -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates >/dev/null

echo "> Exporting Developer ID build..."
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$EXPORT" \
  -allowProvisioningUpdates >/dev/null

echo "> Notarizing the app..."
rm -f build/LiveLoop.zip
ditto -c -k --keepParent "$APP" build/LiveLoop.zip
xcrun notarytool submit build/LiveLoop.zip --keychain-profile "$PROFILE" --wait
echo "> Stapling the app..."
xcrun stapler staple "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
[ -n "$VERSION" ] || VERSION="1.0.0"
DMG="dist/LiveLoop-$VERSION.dmg"
echo "> Building DMG $DMG ..."
mkdir -p dist
rm -f "$DMG"
create-dmg \
  --volname "LiveLoop $VERSION" \
  --window-pos 200 120 --window-size 560 380 --icon-size 110 \
  --icon "LiveLoop.app" 150 180 --app-drop-link 410 180 \
  --hide-extension "LiveLoop.app" --no-internet-enable \
  "$DMG" "$APP" >/dev/null 2>&1 \
  || create-dmg --volname "LiveLoop $VERSION" --app-drop-link 410 180 "$DMG" "$APP" >/dev/null 2>&1 \
  || true

echo "> Notarizing + stapling the DMG..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "> Verifying..."
codesign --verify --deep --strict "$APP" && echo "OK notarized + stapled app"
spctl -a -vv "$APP" 2>&1 | head -2
echo "DONE: $DMG"
