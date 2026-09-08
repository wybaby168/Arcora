#!/bin/bash
# LOCAL evaluation only. This does not satisfy the customer release authorization gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ "${ARCORA_RAR_LOCAL_EVALUATION:-0}" = 1 ] || { echo 'For local evaluation under RARLAB terms only: set ARCORA_RAR_LOCAL_EVALUATION=1.' >&2; exit 1; }
BASE="$ROOT/dist/Arcora.app"
[ -d "$BASE" ] || { echo 'Build the ordinary app with Scripts/build-app.sh first.' >&2; exit 1; }
codesign --verify --deep --strict "$BASE"
python3 - <<'PY'
import hashlib,json
from pathlib import Path
lock=json.loads(Path('Vendor/engines.lock.json').read_text())['rar']
for arch in ('arm64','x86_64'):
    root=Path('.local/rar')/arch
    for name in ('rar','license.txt','rar.txt','acknow.txt','order.htm','readme.txt','whatsnew.txt','rarfiles.lst'):
        file=root/name
        if file.is_symlink() or not file.is_file():
            raise SystemExit('Run Scripts/prepare-rar-testing.sh: missing regular file '+str(file))
    if hashlib.sha256((root/'rar').read_bytes()).hexdigest()!=lock[arch]['binarySha256']:
        raise SystemExit('Unexpected RAR test binary: '+arch)
    original=Path('.local/rar/downloads')/lock[arch]['file']
    if original.is_symlink() or hashlib.sha256(original.read_bytes()).hexdigest()!=lock[arch]['sha256']:
        raise SystemExit('Unexpected original RAR package: '+arch)
PY
STAGING="$ROOT/.local/.Arcora-RAR-Test-$$.app"
OUTPUT="$ROOT/.local/Arcora-RAR-Test.app"
if [ "${ARCORA_RAR_CODEC_EVALUATION:-0}" = 1 ]; then OUTPUT="$ROOT/.local/Arcora-RAR-Codec-Evaluation.app"; fi
trap 'rm -rf "$STAGING"' EXIT
ditto "$BASE" "$STAGING"
for ARCH in arm64 x86_64; do
  ENGINE="$STAGING/Contents/Helpers/rar/$ARCH"
  NOTICES="$STAGING/Contents/Resources/ThirdParty/RAR/$ARCH"
  mkdir -p "$ENGINE" "$NOTICES"
  cp ".local/rar/$ARCH/rar" "$ENGINE/rar"
  for NAME in license.txt rar.txt acknow.txt order.htm readme.txt whatsnew.txt rarfiles.lst; do cp ".local/rar/$ARCH/$NAME" "$NOTICES/$NAME"; done
  ORIGINAL=$(python3 -c 'import json,sys;print(json.load(open("Vendor/engines.lock.json"))["rar"][sys.argv[1]]["file"])' "$ARCH")
  cp ".local/rar/downloads/$ORIGINAL" "$NOTICES/$ORIGINAL"
  chmod 755 "$ENGINE/rar"
  xcrun lipo "$ENGINE/rar" -verify_arch "$ARCH"
  codesign --force --sign - "$ENGINE/rar"
done
cp Documentation/RAR_LOCAL_EVALUATION.txt "$STAGING/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.arcora.desktop.rar-evaluation' "$STAGING/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Arcora RAR Test' "$STAGING/Contents/Info.plist"
if [ "${ARCORA_RAR_CODEC_EVALUATION:-0}" = 1 ]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.arcora.desktop.rar-codec-evaluation' "$STAGING/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Arcora RAR Codec Evaluation' "$STAGING/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :ArcoraRARLocalEvaluation true' "$STAGING/Contents/Info.plist"
else
  python3 Scripts/assert-distribution-clean.py "$STAGING" --allow-local-test-encoder
fi
codesign --force --sign - "$STAGING"
codesign --verify --deep --strict "$STAGING"
# Only replace this script's known generated test artifact.
if [ -e "$OUTPUT" ]; then mv "$OUTPUT" "${OUTPUT%.app}-previous-$(date +%Y%m%d%H%M%S).app"; fi
mv "$STAGING" "$OUTPUT"
echo "Local evaluation app: $OUTPUT"
echo 'Do not distribute this app. No RAR redistribution grant, customer license, Developer ID or notarization is provided.'
