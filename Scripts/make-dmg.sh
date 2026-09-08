#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
[ "$(uname -s)" = Darwin ] || { echo 'DMG creation requires macOS.' >&2; exit 1; }
[ -d dist/Arcora.app ] || { echo 'Build the app first.' >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ditto dist/Arcora.app "$TMP/Arcora.app"
ln -s /Applications "$TMP/Applications"
hdiutil create -volname Arcora -srcfolder "$TMP" -ov -format UDZO dist/Arcora-macOS.dmg
if [ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != - ]; then
  codesign --timestamp --sign "$SIGN_IDENTITY" dist/Arcora-macOS.dmg
fi
echo 'Created dist/Arcora-macOS.dmg. Public distribution requires notarization of the app and/or DMG.'
