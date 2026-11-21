#!/usr/bin/env bash
#
# Assembles build/Doctor.app from the SwiftPM binary. No Xcode project needed —
# just the command line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Doctor.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "Doctor is a macOS app; this script needs to run on macOS." >&2
	exit 1
fi

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Doctor" "$APP/Contents/MacOS/Doctor"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# A Developer ID provisioning profile and entitlements, passed by release.sh
# for the iCloud-enabled build. Plain local builds leave both unset: iCloud
# entitlements are restricted, and an ad-hoc binary claiming them won't launch.
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
ENTITLEMENTS="${ENTITLEMENTS:-}"
if [[ -n "$PROVISIONING_PROFILE" ]]; then
	cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

echo "==> Drawing icon"
swift "$ROOT/Scripts/GenerateIcon.swift" "$APP/Contents/Resources/AppIcon.icns" || \
	echo "    (icon generation failed; continuing without one)"

# Ad-hoc by default, which is all a local build needs. Scripts/release.sh sets
# SIGN_IDENTITY to the Developer ID certificate, which also needs the hardened
# runtime and a secure timestamp before Apple will notarize it.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
	if [[ -n "$ENTITLEMENTS" ]]; then
		echo "iCloud entitlements need a Developer ID signature and profile; ad-hoc can't carry them." >&2
		exit 1
	fi
	echo "==> Signing (ad-hoc)"
	codesign --force --sign - --identifier com.matty8r.Doctor "$APP"
else
	echo "==> Signing ($SIGN_IDENTITY)"
	sign_args=(--force --sign "$SIGN_IDENTITY" --identifier com.matty8r.Doctor --options runtime --timestamp)
	if [[ -n "$ENTITLEMENTS" ]]; then
		sign_args+=(--entitlements "$ENTITLEMENTS")
	fi
	codesign "${sign_args[@]}" "$APP"
fi

echo "==> Registering with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-f "$APP" 2>/dev/null || true

echo
echo "Built $APP"
