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
#   - A *Developer ID* provisioning profile for com.matty8r.Doctor that carries
#     the iCloud.com.matty8r.Doctor container, for the synced library. It has to
#     be made by hand on the developer portal — see the preflight message, which
#     says exactly how. Doctor is built by SwiftPM and signed with plain
#     codesign, so this script embeds the profile and signs with
#     Resources/Doctor.entitlements itself. Three things must line up (the same
#     three that break Sidetable's release silently): the profile carries the
#     container; the push entitlement is production, in the macOS spelling
#     (com.apple.developer.aps-environment); and the container environment is
#     Production. The CloudKit schema must also be deployed to Production in the
#     CloudKit console — nothing here can check that, and the symptom is an app
#     that notarizes, launches, and syncs nothing.
#
# Publishing is a separate step: ../StudioOrchestrator/scripts/publish-apps.sh
# picks up the newest DMG from here, checks it, and pushes it to the site.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEAM_ID="CG3Q63736Q"
IDENTITY="Developer ID Application: Matthew Silas (${TEAM_ID})"
NOTARY_PROFILE="studio-notary"
BUNDLE_ID="com.matty8r.Doctor"
CONTAINER="iCloud.${BUNDLE_ID}"
ENTITLEMENTS="$ROOT/Resources/Doctor.entitlements"
APP="build/Doctor.app"
PROFILE_DIRS=("${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles" "${HOME}/Library/MobileDevice/Provisioning Profiles")

die() { echo "" >&2; echo "$@" >&2; exit 1; }
plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

# ---------------------------------------------------------------- preflight

echo "==> Preflight for ${BUNDLE_ID}"

# Capture output before grepping: under pipefail, `grep -q` exits at its first
# match, the writer takes SIGPIPE, and the pipeline reports failure on success.
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -qF "${IDENTITY}" <<<"${IDENTITIES}" || die "Missing signing certificate: ${IDENTITY}"
echo "    certificate ....... ${IDENTITY}"

# Notary credentials: the shared keychain profile if it works on this Mac,
# otherwise the App Store Connect API key the iOS release script already uses
# (Xcode updates have dropped the keychain profile before).
NOTARY_AUTH=()
if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE}")
    echo "    notary ............ keychain profile ${NOTARY_PROFILE}"
else
    API_KEY_ID="$(grep -E '^API_KEY_ID=' "$ROOT/iOS/release.sh" | head -1 | cut -d'"' -f2)"
    API_ISSUER_ID="$(grep -E '^API_ISSUER_ID=' "$ROOT/iOS/release.sh" | head -1 | cut -d'"' -f2)"
    API_KEY_FILE="${HOME}/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"
    [ -n "${API_KEY_ID}" ] && [ -f "${API_KEY_FILE}" ] \
        || die "No usable notary credentials: the \"${NOTARY_PROFILE}\" keychain profile is missing and the App Store Connect API key isn't on this Mac.
Create the profile with:
  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id \"you@example.com\" --team-id \"${TEAM_ID}\""
    NOTARY_AUTH=(--key "${API_KEY_FILE}" --key-id "${API_KEY_ID}" --issuer "${API_ISSUER_ID}")
    xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 \
        || die "The App Store Connect API key ${API_KEY_ID} was rejected by the notary service."
    echo "    notary ............ App Store Connect API key ${API_KEY_ID}"
fi

# SHA-1s of the Developer ID certificate(s) whose private key is on this Mac.
# Matthew has two certificates with the same name and expiry; a profile made
# against the one without a local key installs fine and then fails at signing.
IDENTITY_HASHES="$(awk -v id="${IDENTITY}" 'index($0, id) { print toupper($2) }' <<<"${IDENTITIES}")"

profile_cert_hashes() { # $1 = decoded profile plist
    local i=0 hash
    while hash="$(plutil -extract "DeveloperCertificates.${i}" raw -o - "$1" 2>/dev/null)"; do
        base64 -D <<<"${hash}" | shasum | awk '{ print toupper($1) }'
        i=$((i + 1))
    done
}

PROFILE_PATH=""
PROFILE_NAME=""
PROFILE_HAS_ENV_KEY="no"
WRONG_CERT_PROFILE=""
for dir in "${PROFILE_DIRS[@]}"; do
    [ -d "${dir}" ] || continue
    while IFS= read -r -d '' profile; do
        plist="$(mktemp)"
        security cms -D -i "${profile}" >"${plist}" 2>/dev/null || { rm -f "${plist}"; continue; }

        app_id="$(plist_get "${plist}" 'Entitlements:com.apple.application-identifier')"
        aps="$(plist_get "${plist}" 'Entitlements:com.apple.developer.aps-environment')"
        containers="$(plist_get "${plist}" 'Entitlements:com.apple.developer.icloud-container-identifiers')"
        managed="$(plist_get "${plist}" 'IsXcodeManaged')"
        expires="$(plist_get "${plist}" 'ExpirationDate')"

        if [ "${app_id}" = "${TEAM_ID}.${BUNDLE_ID}" ] && [ "${aps}" = "production" ] \
           && [ "${managed}" != "true" ] && grep -qF "${CONTAINER}" <<<"${containers}"; then
            cert_ok="no"
            for h in $(profile_cert_hashes "${plist}"); do
                if grep -qxF "${h}" <<<"${IDENTITY_HASHES}"; then cert_ok="yes"; fi
            done
            if [ "${cert_ok}" = "yes" ]; then
                PROFILE_PATH="${profile}"
                PROFILE_NAME="$(plist_get "${plist}" 'Name') (expires ${expires})"
                if /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-environment' "${plist}" >/dev/null 2>&1; then
                    PROFILE_HAS_ENV_KEY="yes"
                fi
                rm -f "${plist}"
                break 2
            fi
            WRONG_CERT_PROFILE="${profile}"
        fi
        rm -f "${plist}"
    done < <(find "${dir}" -name '*.provisionprofile' -print0 2>/dev/null)
done

if [ -z "${PROFILE_PATH}" ] && [ -n "${WRONG_CERT_PROFILE}" ]; then
    die "A Developer ID profile for ${BUNDLE_ID} exists (${WRONG_CERT_PROFILE})
but it was made against a certificate whose private key isn't on this Mac.
Make a new one and pick the Developer ID Application certificate that is in this
Mac's login keychain (compare SHA-1s: security find-identity -v -p codesigning)."
fi

[ -n "${PROFILE_PATH}" ] || die "No manually managed Developer ID provisioning profile for ${BUNDLE_ID}
with the ${CONTAINER} container.

Create one at developer.apple.com/account/resources/profiles > + > Developer ID:
  1. Pick the ${BUNDLE_ID} App ID (the iPhone app's — one App ID covers both).
     Make sure iCloud is on, with ${CONTAINER} selected, and Push Notifications on.
  2. Pick the Developer ID Application certificate that lives on this Mac.
  3. Download it and double-click to install, then run this script again.
The CloudKit schema must also be deployed to Production in the CloudKit console."

echo "    profile ........... ${PROFILE_NAME}"
echo "    iCloud container .. ${CONTAINER}"
[ "${PROFILE_HAS_ENV_KEY}" = "yes" ] \
    || echo "    note: the profile doesn't list icloud-container-environment; the signed app is checked below."

# ------------------------------------------------------------------ build

CONFIG=release SIGN_IDENTITY="$IDENTITY" PROVISIONING_PROFILE="${PROFILE_PATH}" ENTITLEMENTS="${ENTITLEMENTS}" \
    Scripts/build-app.sh
codesign --verify --strict --verbose=2 "$APP"

# ------------------------------------------------------------------ verify

echo "==> Verifying the signature and the iCloud entitlements"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"${SIGNATURE}" || die "The app is not Developer ID-signed."
grep -q "flags=.*runtime" <<<"${SIGNATURE}" || die "Hardened runtime is off; notarization would reject this."
[ -f "$APP/Contents/embedded.provisionprofile" ] || die "No embedded provisioning profile — iCloud would fail at runtime."

BUILT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - -)"
grep -qF "${CONTAINER}" <<<"${BUILT}" || die "The signed app is missing the ${CONTAINER} entitlement."
grep -A1 'com.apple.developer.aps-environment' <<<"${BUILT}" | grep -q production \
    || die "No com.apple.developer.aps-environment = production (the macOS spelling of the push entitlement)."
grep -A1 'com.apple.developer.icloud-container-environment' <<<"${BUILT}" | grep -q Production \
    || die "The container environment isn't Production; the app would read the development CloudKit database."
echo "    Developer ID signed, ${CONTAINER} present, push production, environment Production"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="Doctor-$VERSION.dmg"

echo "==> Submitting to the notary service (usually a few minutes)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -c -k --keepParent "$APP" "$WORK/Doctor.zip"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$WORK/Doctor.zip" "${NOTARY_AUTH[@]}" --wait)"
echo "$SUBMIT_OUTPUT"
if ! grep -q "status: Accepted" <<<"$SUBMIT_OUTPUT"; then
	SUBMISSION_ID="$(awk '/id:/{print $2; exit}' <<<"$SUBMIT_OUTPUT")"
	echo "Notarization failed. Log:" >&2
	xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH[@]}" >&2 || true
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
echo "only proves the bundle is signed, not that it runs — and it won't tell you whether"
echo "the CloudKit schema is deployed to Production. Add a library document and check it"
echo "reaches the iPhone."
