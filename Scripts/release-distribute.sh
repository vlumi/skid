#!/usr/bin/env bash
# Release step 3 (pure): regenerate the project from the checked-out tree,
# then archive, export, and (unless --no-upload) upload the iOS app to App
# Store Connect / TestFlight. Builds straight from the checked-out main,
# which is the tagged release commit after the publish step.
#
# Usage: release-distribute.sh [--no-upload|--upload-only] [--require-tag]
#   --no-upload:   archive/export only, skip the ASC upload
#   --upload-only: upload the already-built dist/ package, skip archive/export
#   --require-tag: verify a git tag exists for project.yml's version+build
#                  (the standalone retry — only re-distribute a real release)
#
# One-time setup (see RELEASING.md):
#   • App Store Connect API key: put the .p8 at
#     ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 and copy
#     Scripts/.asc-config.example → Scripts/.asc-config with its IDs.
#   • Signing is automatic (-allowProvisioningUpdates); no cert/profile to
#     install by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

mode=full
require_tag=0
while [ $# -gt 0 ]; do
    case "$1" in
        --no-upload) mode=no-upload ;;
        --upload-only) mode=upload-only ;;
        --require-tag) require_tag=1 ;;
        *) die "unknown argument '$1'" ;;
    esac
    shift
done

version="$(read_unique MARKETING_VERSION)"
build="$(read_unique CURRENT_PROJECT_VERSION)"
tag="$(tag_name "$version" "$build")"
if [ "$require_tag" -eq 1 ]; then
    git rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
        || die "no ${tag} tag — nothing tagged to re-distribute. Run \`make release\` for a fresh cut."
    echo "✓ ${tag} tag present — re-distributing."
fi

out="dist/ios"
archive="${out}/Skid-ios.xcarchive"

if [ "$mode" != upload-only ]; then
    say "Regenerating project…"
    xcodegen generate >/dev/null
    rm -rf "$out"
    mkdir -p "$out"

    say "Archiving Skid-iOS (${tag})…"
    xcodebuild archive \
        -project Skid.xcodeproj \
        -scheme Skid-iOS \
        -destination "generic/platform=iOS" \
        -archivePath "$archive" \
        -allowProvisioningUpdates

    say "Exporting (.ipa)…"
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportPath "$out" \
        -exportOptionsPlist Scripts/ExportOptions.plist \
        -allowProvisioningUpdates
fi

if [ "$mode" = no-upload ]; then
    echo "✓ built ${tag} — package in ${out}/ (upload skipped)."
    exit 0
fi

pkg="$(ls "${out}"/*.ipa 2>/dev/null | head -1)"
[ -n "$pkg" ] || die "no .ipa in ${out}/ — run without --upload-only first."

# Load the API key IDs (gitignored). The .p8 is auto-discovered by Key ID
# from ~/.appstoreconnect/private_keys/.
config="Scripts/.asc-config"
[ -f "$config" ] || die "$config missing — copy Scripts/.asc-config.example and fill in your ASC API Key ID + Issuer ID."
# shellcheck disable=SC1090
. "$config"
: "${ASC_KEY_ID:?set ASC_KEY_ID in $config}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in $config}"

say "Uploading ${tag} to App Store Connect…"
xcrun altool --upload-app \
    --type ios \
    --file "$pkg" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

echo "✓ uploaded ${tag} — TestFlight processing takes a few minutes."
