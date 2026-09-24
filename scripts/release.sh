#!/usr/bin/env bash
#
# Release pipeline: tests -> archive -> Developer ID export -> notarize ->
# staple -> signed, notarized DMG in dist/. The result installs and activates
# its camera extension on any Mac with SIP on.
#
# One-time setup:
#   1. A paid Apple Developer Program team (2TWQF4T93E), signed in to
#      Xcode ▸ Settings ▸ Accounts: automatic signing refreshes the
#      provisioning profiles through that account.
#   2. Notarization credentials in the keychain:
#        xcrun notarytool store-credentials "LiveLoop" \
#          --apple-id "you@example.com" --team-id 2TWQF4T93E
#   3. brew install xcodegen create-dmg
#
# Each step logs to build/logs/; when one fails, its errors are printed.
#
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEAM="${LIVELOOP_TEAM_ID:-2TWQF4T93E}"
PROFILE="${LIVELOOP_NOTARY_PROFILE:-LiveLoop}"
ARCHIVE="build/LiveLoop.xcarchive"
EXPORT="build/export"
APP="$EXPORT/LiveLoop.app"

# notarize NAME FILE : submits FILE, waits, and stops with Apple's report unless accepted.
notarize() {
  local log="$LOG_DIR/$1.log"
  run "$1" xcrun notarytool submit "$2" --keychain-profile "$PROFILE" --wait
  grep -q 'status: Accepted' "$log" && return 0
  local id
  id="$(awk '$1 == "id:" {print $2; exit}' "$log")"
  [ -z "$id" ] || xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
  fail "Apple did not accept $2. Full log: $log"
}

step "Checking prerequisites"
need xcodegen "brew install xcodegen"
need create-dmg "brew install create-dmg"
SIGN_ID="$(security find-identity -v -p codesigning \
  | awk -F'"' -v team="($TEAM)" '/Developer ID Application/ && index($2, team) {print $2; exit}')"
[ -n "$SIGN_ID" ] || fail "no \"Developer ID Application\" certificate for team $TEAM in the keychain."
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null | grep 'identifier =' >/dev/null \
  || fail "no Apple ID in Xcode. Sign in under Xcode ▸ Settings ▸ Accounts (team $TEAM)."
run notary-credentials xcrun notarytool history --keychain-profile "$PROFILE"
MARKETING="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
if git rev-parse -q --verify "refs/tags/v$MARKETING" >/dev/null; then
  note "v$MARKETING is already tagged: bump MARKETING_VERSION in project.yml before publishing."
fi
ok "$SIGN_ID, notary profile \"$PROFILE\""

step "Generating the Xcode project"
run xcodegen xcodegen generate
ok "LiveLoop.xcodeproj"

step "Running the unit tests"
run tests xcodebuild test -project LiveLoop.xcodeproj -scheme LiveLoop -configuration Debug \
  -destination 'platform=macOS' -only-testing:LiveLoopTests CODE_SIGNING_ALLOWED=NO
ok "$(grep -Eo 'Executed [0-9]+ tests, with 0 failures' "$LOG_DIR/tests.log" | tail -1)"

step "Archiving (automatic signing, team $TEAM)"
rm -rf "$ARCHIVE"
run archive xcodebuild archive -project LiveLoop.xcodeproj -scheme LiveLoop -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates
ok "$ARCHIVE"

step "Exporting the Developer ID build"
rm -rf "$EXPORT"
run export xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$EXPORT" -allowProvisioningUpdates
VERSION="$(app_version "$APP")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ok "$APP ($VERSION, build $BUILD)"

step "Notarizing the app (a few minutes)"
rm -f build/LiveLoop.zip
ditto -c -k --keepParent "$APP" build/LiveLoop.zip
notarize notarize-app build/LiveLoop.zip
run staple-app xcrun stapler staple "$APP"
ok "notarized and stapled"

scripts/make_dmg.sh "$APP"
DMG="$(dmg_path "$APP")"

step "Signing and notarizing the DMG"
run sign-dmg codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize notarize-dmg "$DMG"
run staple-dmg xcrun stapler staple "$DMG"
ok "notarized and stapled"

step "Verifying"
run verify-app codesign --verify --deep --strict "$APP"
spctl -a -t exec -vv "$APP" 2>&1 | grep 'source=Notarized Developer ID' >/dev/null \
  || fail "Gatekeeper does not see $APP as notarized: spctl -a -t exec -vv \"$APP\""
run verify-dmg xcrun stapler validate "$DMG"
ok "Gatekeeper accepts the app and the DMG"

printf '\nLiveLoop %s (build %s) is ready in %dm%02ds:\n  %s\n' \
  "$VERSION" "$BUILD" $((SECONDS / 60)) $((SECONDS % 60)) "$DMG"
