#!/usr/bin/env bash
#
# Archives, signs, exports and uploads Doctor to App Store Connect / TestFlight.
#
# Requires (all one-time portal/account setup, not something this script can
# do — see docs/ios.md "Portal work"):
#   - The App ID com.matty8r.Doctor registered with iCloud (CloudKit) and
#     Push Notifications, and the iCloud.com.matty8r.Doctor container
#     actually attached to it (the portal doesn't always save that on the
#     first try — check it stuck before generating a profile from it).
#   - A "Doctor App Store" distribution provisioning profile, generated
#     *after* the container was attached (profiles are a snapshot — a stale
#     one silently omits a container added afterward) and installed into
#     ~/Library/Developer/Xcode/UserData/Provisioning Profiles/.
#   - The "Apple Distribution: Matthew Silas (CG3Q63736Q)" certificate in
#     the login keychain.
#   - An App Store Connect API key at
#     ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8, and its Issuer ID
#     (App Store Connect → Users and Access → Integrations → App Store
#     Connect API) — set both below.
#   - An app record for com.matty8r.Doctor already created in App Store
#     Connect (Apps → + → New App) — altool's upload fails without one.
#
# Manual signing throughout, not automatic: this account has no Apple ID
# signed into Xcode's own Accounts preferences on this machine, so
# `-allowProvisioningUpdates` has nothing to authenticate with and
# automatic signing falls back to a stale wildcard profile that has none of
# the capabilities this app actually needs. Specifying the certificate and
# profile directly sidesteps that entirely.
set -euo pipefail
cd "$(dirname "$0")"

API_KEY_ID="44BG9AWQNS"
API_ISSUER_ID="69a6de7c-549d-47e3-e053-5b8c7c11a4d1"

# --dry-run: archive and export, print the exported app's entitlements, and
# stop before anything is uploaded.
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== Regenerating the Xcode project =="
xcodegen generate

echo "== Archiving =="
xcodebuild archive \
    -project Doctor.xcodeproj -scheme Doctor \
    -archivePath "${WORK}/Doctor.xcarchive" \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=CG3Q63736Q \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="Doctor App Store"

echo "== Exporting =="
cat > "${WORK}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>CG3Q63736Q</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>com.matty8r.Doctor</key>
		<string>Doctor App Store</string>
	</dict>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
    -archivePath "${WORK}/Doctor.xcarchive" \
    -exportPath "${WORK}/export" \
    -exportOptionsPlist "${WORK}/ExportOptions.plist"

echo "== Entitlements of the exported app =="
unzip -q -o "${WORK}/export/Doctor.ipa" -d "${WORK}/ipa"
codesign -d --entitlements - --xml "${WORK}/ipa/Payload/Doctor.app" 2>/dev/null \
    | plutil -convert xml1 -o - - | grep -A1 -E "aps-environment|icloud-container-environment|icloud-container-identifiers|get-task-allow" \
    | grep -E "<string>|<true|<false" | sed 's/^[[:space:]]*//'
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${WORK}/ipa/Payload/Doctor.app/Info.plist")"
echo "Build number in the archive: ${BUILD_NUMBER}"

if [ "$DRY_RUN" = 1 ]; then
    echo "Dry run: stopping before the upload."
    exit 0
fi

echo "== Uploading to App Store Connect =="
xcrun altool --upload-app -f "${WORK}/export/Doctor.ipa" -t ios \
    --apiKey "${API_KEY_ID}" --apiIssuer "${API_ISSUER_ID}"

echo ""
echo "Uploaded. Processing usually takes a few minutes to about an hour —"
echo "check App Store Connect → Doctor → TestFlight for it to clear, then"
echo "add it to a testing group."
