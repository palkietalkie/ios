#!/usr/bin/env bash
# Build, sign, and upload a prod App Store / TestFlight build of Palkie Talkie.
#
# Usage: ./scripts/release.sh
# The build number is the highest already on App Store Connect + 1 (clean sequential
# +1; Apple just requires it to increase). Derived from ASC, not git, so it never
# jumps when commit count diverges from upload count.
#
# Reads APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD from ios/.env (gitignored).
# Release config bakes prod into the build (api.palkietalkie.com + pk_live Clerk) via project.yml.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$IOS_DIR"

# Apple upload credentials from the gitignored .env.
set -a
# shellcheck source=/dev/null
. ./.env
set +a
: "${APPLE_ID:?APPLE_ID missing in ios/.env}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD missing in ios/.env}"

# Next build number = highest on ASC + 1. Runs in the backend venv (needs httpx/jwt + the asc/ modules); the subshell keeps that activation out of this script's env.
# shellcheck source=/dev/null
BUILD_NUMBER="$(cd "$IOS_DIR/../backend" && source .venv/bin/activate && python -m scripts.asc.next_build_number)"
: "${BUILD_NUMBER:?could not compute next build number from ASC}"
# Build artifacts live under ios/build/ (gitignored, inspectable later) — /tmp gets wiped on reboot, which is why a failed-review build couldn't be examined after the fact.
OUT="$IOS_DIR/build/release"
ARCHIVE="$OUT/PalkieTalkie.xcarchive"
EXPORT_DIR="$OUT/PTExport"
OPTS="$OUT/exportOptions.plist"
mkdir -p "$OUT"

# Gate: a prod build whose social sign-in can't complete locks out the App/TestFlight reviewer (this is exactly how build 1.0(1) failed — Google redirect_uri_mismatch). Verify the live OAuth handshake before wasting an archive+upload. Pure-stdlib, no venv needed.
PK_LIVE="$(grep -oE 'pk_live_[A-Za-z0-9]+' project.yml | head -1)"
echo "[release] verifying prod OAuth handshake ($PK_LIVE) ..."
python3 ../backend/scripts/verify_prod_oauth.py --key "$PK_LIVE"

echo "[release] xcodegen + set build number to $BUILD_NUMBER ..."
xcodegen generate >/dev/null
# Info.plist is generated fresh by xcodegen (build number resets to 1), so stamp the real one here.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" PalkieTalkie/Info.plist

echo "[release] archiving (Release / prod) ..."
rm -rf "$ARCHIVE"
xcodebuild -project PalkieTalkie.xcodeproj -scheme PalkieTalkie \
	-configuration Release -destination 'generic/platform=iOS' \
	-archivePath "$ARCHIVE" -allowProvisioningUpdates archive

echo "[release] exporting distribution-signed .ipa ..."
cat >"$OPTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>7P7YY88H3V</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
	-exportOptionsPlist "$OPTS" -exportPath "$EXPORT_DIR" -allowProvisioningUpdates

echo "[release] uploading to App Store Connect ..."
xcrun altool --upload-app -f "$EXPORT_DIR/PalkieTalkie.ipa" -t ios \
	-u "$APPLE_ID" -p "$APPLE_APP_SPECIFIC_PASSWORD"

echo "[release] done — build 1.0 ($BUILD_NUMBER) uploaded. Appears in App Store Connect > TestFlight after ~5-15 min processing."
