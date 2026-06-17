#!/usr/bin/env bash
# Capture App Store screenshots by driving the real app in the simulator (PalkieTalkieScreenshots UI test).
#
# Output: raw 1320x2868 PNGs (Apple's 6.9" size) under ios/build/screenshots/shots/. Feed them to
# backend/scripts/asc/frame_screenshot.py (caption + device frame) then upload_app_screenshots.py.
#
# The UI test signs in via Clerk dev test-mode, so this needs network + signing (handled by
# -allowProvisioningUpdates). Microphone/location are pre-granted so no permission dialog blocks the run.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$IOS_DIR"

SIM="${SCREENSHOT_SIM:-iPhone 17 Pro Max}"
BUNDLE_ID="com.palkietalkie.app"
DERIVED="$IOS_DIR/build/screenshots"
RESULT="$DERIVED/result.xcresult"
SHOTS="$DERIVED/shots"
DEST="platform=iOS Simulator,name=$SIM"

# xcodegen reads ios/.env for the Clerk/backend build settings; without it the build ships an empty key.
set -a
# shellcheck source=/dev/null
. ./.env
set +a

echo "[shots] xcodegen + boot $SIM ..."
xcodegen generate >/dev/null
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
# Capture in dark mode — the App Store screenshots are dark-themed.
xcrun simctl ui "$SIM" appearance dark
# The sim's default status bar is noisy (drained battery, no signal); force full battery + bars. `clear` first because overrides persist across runs — without it a stale time/value from a prior run would stick. Time is not overridden, so it shows the real clock.
xcrun simctl status_bar "$SIM" clear
xcrun simctl status_bar "$SIM" override \
	--batteryState charged --batteryLevel 100 \
	--cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3

echo "[shots] build-for-testing (signed) ..."
xcodebuild build-for-testing \
	-project PalkieTalkie.xcodeproj -scheme Screenshots \
	-configuration Debug -destination "$DEST" \
	-derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet

# Clean slate: a leftover Clerk session from a prior run would skip sign-in and land mid-onboarding, making the run non-deterministic. Uninstall clears the app's data + keychain on the simulator.
APP="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'PalkieTalkie.app' | head -1)"
xcrun simctl uninstall "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl privacy "$SIM" grant all "$BUNDLE_ID" 2>/dev/null || true

echo "[shots] run UI test ..."
rm -rf "$RESULT"
xcodebuild test-without-building \
	-project PalkieTalkie.xcodeproj -scheme Screenshots \
	-configuration Debug -destination "$DEST" \
	-derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" \
	-allowProvisioningUpdates -quiet

echo "[shots] extract PNGs ..."
rm -rf "$SHOTS"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$SHOTS"
# xcresulttool names files by a manifest; rename to the test's attachment names for stable downstream paths.
python3 - "$SHOTS" <<'PY'
import json, pathlib, shutil, sys
shots = pathlib.Path(sys.argv[1])
manifest = json.loads((shots / "manifest.json").read_text())
for test in manifest:
    for att in test.get("attachments", []):
        # XCTest names attachments "<our-name>_0_<uuid>.png"; recover the stable name we set in the test.
        name = att["suggestedHumanReadableName"].split("_0_")[0]
        src = shots / att["exportedFileName"]
        if src.exists():
            shutil.move(str(src), str(shots / f"{name}.png"))
print("\n".join(sorted(str(p) for p in shots.glob("*.png"))))
PY
echo "[shots] done — PNGs in $SHOTS"
