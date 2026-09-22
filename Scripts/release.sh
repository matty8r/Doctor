#!/usr/bin/env bash
#
# Builds, Developer ID-signs, notarizes and staples Doctor, then packages it as
# Doctor-<version>.dmg at the repo root, ready for branchesthreads.com/apps/.
#
# Requires:
#   - The "Developer ID Application: Matthew Silas (CG3Q63736Q)" certificate in
#     the login keychain.
#   - Notarization credentials in the "studio-notary" keychain profile, shared
#     with the studio apps. Set up once:
#       xcrun notarytool store-credentials "studio-notary" \
#           --apple-id "you@example.com" --team-id "CG3Q63736Q"
#
# Publishing is a separate step: ../StudioOrchestrator/scripts/publish-apps.sh
# picks up the newest DMG from here, checks it, and pushes it to the site.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IDENTITY="Developer ID Application: Matthew Silas (CG3Q63736Q)"
NOTARY_PROFILE="studio-notary"
APP="build/Doctor.app"

CONFIG=release SIGN_IDENTITY="$IDENTITY" Scripts/build-app.sh
codesign --verify --strict --verbose=2 "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="Doctor-$VERSION.dmg"

echo "==> Submitting to the notary service (usually a few minutes)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -c -k --keepParent "$APP" "$WORK/Doctor.zip"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$WORK/Doctor.zip" --keychain-profile "$NOTARY_PROFILE" --wait)"
echo "$SUBMIT_OUTPUT"
if ! grep -q "status: Accepted" <<<"$SUBMIT_OUTPUT"; then
	SUBMISSION_ID="$(awk '/id:/{print $2; exit}' <<<"$SUBMIT_OUTPUT")"
	echo "Notarization failed. Log:" >&2
	xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
	exit 1
fi

# Staple the app rather than only the DMG, so it stays trusted offline even
# after someone drags it out of the disk image.
echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Packaging $DMG"
mkdir "$WORK/staging"
cp -R "$APP" "$WORK/staging/"
ln -s /Applications "$WORK/staging/Applications"
rm -f "$DMG"
hdiutil create -volname "Doctor" -srcfolder "$WORK/staging" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

echo "==> Checking Gatekeeper"
spctl --assess --type execute --verbose "$APP"

echo
echo "Built $DMG"
echo "Before publishing, mount it and launch the app from inside it: notarization"
echo "only proves the bundle is signed, not that it runs."
