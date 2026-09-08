#!/bin/bash
# Fetch only exact, checksum-pinned upstream assets. No Homebrew at runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v python3 >/dev/null || { echo 'Python 3 is required (included with Xcode command line tools).' >&2; exit 1; }
case "$(uname -s)-$(uname -m)" in
  Darwin-*) PLATFORM=mac ;;
  Linux-x86_64) PLATFORM=linux-x64 ;;
  Linux-aarch64|Linux-arm64) PLATFORM=linux-arm64 ;;
  *) echo 'Supported bootstrap platforms: macOS universal, Linux x64/arm64.' >&2; exit 1 ;;
esac
export ARCORA_BOOTSTRAP_PLATFORM="$PLATFORM"
CACHE="${ARCORA_DOWNLOAD_CACHE:-$ROOT/.downloads}"
mkdir -p "$CACHE" Vendor/7zip Vendor/UpstreamSource
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# OFFLINE=1 never accesses the network. Prepopulate CACHE with the pinned files.
for KIND in "$PLATFORM" source; do
  IFS=' ' read -r NAME HASH < <(python3 - "$KIND" <<'PY'
import json,sys
v=json.load(open('Vendor/engines.lock.json'))['7zip'][sys.argv[1]]
print(v['file'],v['sha256'])
PY
)
  TARGET="$CACHE/$NAME"
  if [ ! -f "$TARGET" ]; then
    [ "${OFFLINE:-0}" != 1 ] || { echo "Offline cache is missing $NAME" >&2; exit 1; }
    URL="https://github.com/ip7z/7zip/releases/download/26.03/$NAME"
    echo "Fetching official 7-Zip 26.03: $NAME"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 600 "$URL" -o "$TARGET.partial"
    mv "$TARGET.partial" "$TARGET"
  fi
  python3 - "$TARGET" "$HASH" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
if h.hexdigest()!=sys.argv[2]:
    raise SystemExit('SHA-256 mismatch; refusing to use '+sys.argv[1]+'. Remove the cached file and retry.')
print('Verified:',sys.argv[1])
PY
  if [ "$KIND" = source ]; then
    cp "$TARGET" Vendor/UpstreamSource/
    mkdir -p "$TMP/source"
    tar -xJf "$TARGET" -C "$TMP/source"
    # Original license texts accompany both source and app distributions.
    mkdir -p Vendor/7zip/Licenses
    find "$TMP/source" -type f \( -iname 'license.txt' -o -iname 'copying*' -o -iname '*unrar*license*' \) -exec cp {} Vendor/7zip/Licenses/ \;
  else
    tar -xJf "$TARGET" -C "$TMP"
    [ -f "$TMP/7zz" ] || { echo 'Official binary was not present in the asset.' >&2; exit 1; }
    cp "$TMP/7zz" Vendor/7zip/7zz
    chmod 755 Vendor/7zip/7zz
    [ ! -d "$TMP/Manual" ] || cp -R "$TMP/Manual" Vendor/7zip/
    [ ! -f "$TMP/readme.txt" ] || cp "$TMP/readme.txt" Vendor/7zip/
    [ ! -f "$TMP/License.txt" ] || cp "$TMP/License.txt" Vendor/7zip/
  fi
done
[ -n "$(find Vendor/7zip/Licenses -type f -print -quit)" ] || { echo 'License extraction failed.' >&2; exit 1; }
# A macOS build must contain both native architectures, not rely on Rosetta.
if [ "$PLATFORM" = mac ]; then xcrun lipo Vendor/7zip/7zz -verify_arch arm64 x86_64; fi
printf '%s\n' "$PLATFORM" > Vendor/7zip/platform.txt
Vendor/7zip/7zz i > "$TMP/engine-info.txt"
grep -q "26.03" "$TMP/engine-info.txt" || { echo "Unexpected engine version" >&2; exit 1; }
sed -n '1,8p' "$TMP/engine-info.txt"
echo 'Engines and corresponding upstream source are ready.'
if [ "$PLATFORM" = mac ]; then bash Scripts/bootstrap-libarchive.sh; fi
