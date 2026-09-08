#!/bin/bash
# Local evaluation only. These assets are never included in an ordinary build.
# RAR's official evaluation/use terms apply: https://www.rarlab.com/license.htm
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
[ "$(uname -s)" = Darwin ] || { echo 'This script fetches macOS engines only.' >&2; exit 1; }
mkdir -p .local/rar/downloads
for ARCH in arm64 x86_64; do
  IFS=' ' read -r NAME HASH URL < <(python3 - "$ARCH" <<'PY'
import json,sys
v=json.load(open('Vendor/engines.lock.json'))['rar'][sys.argv[1]]
print(v['file'],v['sha256'],v['url'])
PY
)
  ASSET="$ROOT/.local/rar/downloads/$NAME"
  if [ ! -f "$ASSET" ]; then
    [ "${OFFLINE:-0}" != 1 ] || { echo "Offline RAR cache is missing $NAME" >&2; exit 1; }
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 300 "$URL" -o "$ASSET.partial"
    mv "$ASSET.partial" "$ASSET"
  fi
  [ "$(shasum -a 256 "$ASSET" | cut -d ' ' -f 1)" = "$HASH" ] || { echo 'RAR archive SHA-256 mismatch.' >&2; exit 1; }
  mkdir -p "$ROOT/.local/rar/$ARCH"
  tar -xzf "$ASSET" --strip-components=1 -C "$ROOT/.local/rar/$ARCH"
  xcrun lipo "$ROOT/.local/rar/$ARCH/rar" -verify_arch "$ARCH"
done
echo 'Local test engines prepared. No redistribution permission or customer license is granted.'
echo 'Run: ARCORA_REQUIRE_7ZZ=1 ARCORA_REQUIRE_RAR=1 ARCORA_RAR="$PWD/.local/rar/arm64/rar" swift test'
