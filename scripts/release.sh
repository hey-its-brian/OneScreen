#!/usr/bin/env bash
# Builds a Developer ID signed, notarized, stapled OneScreen.zip in ./build/release.
#
# One-time setup:
#   1. A "Developer ID Application" certificate for team L6X8U2TQ6F in your login keychain.
#   2. Notary credentials saved under the profile name below:
#        xcrun notarytool store-credentials onescreen-notary --apple-id <you> --team-id L6X8U2TQ6F
#      (it prompts for an app-specific password from account.apple.com)
#   Any profile for the same Apple ID works: NOTARY_PROFILE=claudemeter-notary scripts/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

TEAM=L6X8U2TQ6F
PROFILE="${NOTARY_PROFILE:-onescreen-notary}"
OUT=build/release
ARCHIVE="$OUT/OneScreen.xcarchive"
APP="$OUT/OneScreen.app"
ZIP="$OUT/OneScreen.zip"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application:.*($TEAM)"; then
  echo "error: no 'Developer ID Application' certificate for team $TEAM in the keychain." >&2
  exit 1
fi

rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate --quiet

echo "==> Archiving"
xcodebuild -project OneScreen.xcodeproj -scheme OneScreen -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -quiet archive

echo "==> Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet
codesign --verify --deep --strict "$APP"

echo "==> Notarizing (usually a few minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"

echo "Done: $ZIP"
