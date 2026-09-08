#!/bin/bash
# Public release: no RAR encoder/key is distributed; test the customer original-import flow privately.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
: "${ARCORA_RELEASE_RAR_PACKAGE:?Provide the original RAR package for this Mac; it is tested privately and never bundled.}"
: "${SIGN_IDENTITY:?A Developer ID Application identity is required.}"
: "${NOTARY_PROFILE:?A notarytool Keychain profile is required.}"
: "${ARCORA_RELEASE_LICENSE_FILE:?Provide your own private test rarreg.key; it is never bundled.}"
case "$SIGN_IDENTITY" in 'Developer ID Application:'*) ;; *) echo 'A Developer ID Application identity is required.' >&2; exit 1;; esac
[ -z "${ARCORA_RAR_DISTRIBUTION_DIR:-}" ] || { echo 'This edition does not distribute RAR components.' >&2; exit 1; }
bash Scripts/bootstrap-engines.sh
export ARCORA_REQUIRE_7ZZ=1
python3 Scripts/check-localization.py
swift test -c release
bash Scripts/build-app.sh
python3 Scripts/verify-app.py dist/Arcora.app --require-rar --rar-package "$ARCORA_RELEASE_RAR_PACKAGE" --license-file "$ARCORA_RELEASE_LICENSE_FILE"
python3 Scripts/assert-distribution-clean.py dist/Arcora.app
bash Scripts/notarize.sh
bash Scripts/make-dmg.sh
xcrun notarytool submit dist/Arcora-macOS.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/Arcora-macOS.dmg
xcrun stapler validate dist/Arcora-macOS.dmg
spctl --assess --type execute --verbose=4 dist/Arcora.app
shasum -a 256 dist/Arcora-macOS.dmg
echo 'RAR-enabled, signed and notarized DMG is ready for clean-machine acceptance.'
