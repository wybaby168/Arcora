#!/bin/bash
# Credentials stay in the user's local Keychain, not the repository.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity, then rebuild.}"
: "${NOTARY_PROFILE:?Store a notarytool Keychain profile and set NOTARY_PROFILE.}"
[ "$SIGN_IDENTITY" != - ] || { echo 'Ad-hoc signatures cannot be notarized.' >&2; exit 1; }
APP="$ROOT/dist/Arcora.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -q 'Authority=Developer ID Application:' || { echo 'Rebuild with SIGN_IDENTITY before notarization.' >&2; exit 1; }
ditto -c -k --keepParent "$APP" "$ROOT/dist/Arcora-notarization.zip"
xcrun notarytool submit "$ROOT/dist/Arcora-notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
ditto -c -k --keepParent "$APP" "$ROOT/dist/Arcora-macOS.zip"
echo 'Notarized and stapled: dist/Arcora-macOS.zip'
