#!/bin/bash
# Signs, notarizes, and staples dist/ClipVault.app for distribution outside
# your own machine. This is OPTIONAL — local use works with the ad-hoc signed
# bundle produced by build-app.sh. Notarization requires a paid Apple Developer
# account and a "Developer ID Application" certificate in your keychain.
#
# Required environment variables:
#   DEVELOPER_ID   e.g. "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID       your Apple ID email (for notarytool)
#   TEAM_ID        your 10-character Apple Developer Team ID
#   APP_PASSWORD   an app-specific password (https://appleid.apple.com)
#
# Alternatively, store a notarytool keychain profile once:
#   xcrun notarytool store-credentials clipvault-notary \
#       --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"
# then run this script with NOTARY_PROFILE=clipvault-notary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/dist/ClipVault.app"
ZIP_PATH="$ROOT/dist/ClipVault.zip"

if [[ ! -d "$APP_DIR" ]]; then
    echo "error: $APP_DIR not found. Run ./build-app.sh first." >&2
    exit 1
fi

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application' identity}"

echo "==> Signing with Developer ID (hardened runtime)"
codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP_DIR"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP_DIR"

echo "==> Zipping for submission"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Submitting to Apple notary service"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
    : "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}"
    : "${TEAM_ID:?Set TEAM_ID or NOTARY_PROFILE}"
    : "${APP_PASSWORD:?Set APP_PASSWORD or NOTARY_PROFILE}"
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
fi

echo "==> Stapling the ticket"
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

echo "==> Done: $APP_DIR is signed, notarized, and stapled"
