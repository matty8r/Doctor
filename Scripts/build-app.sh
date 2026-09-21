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

echo "==> Drawing icon"
swift "$ROOT/Scripts/GenerateIcon.swift" "$APP/Contents/Resources/AppIcon.icns" || \
	echo "    (icon generation failed; continuing without one)"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier com.matty8r.Doctor "$APP"

echo "==> Registering with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-f "$APP" 2>/dev/null || true

echo
echo "Built $APP"
