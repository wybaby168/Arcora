#!/bin/bash
# Build a pinned universal static library using only the macOS SDK and make.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ "$(uname -s)" = Darwin ] || { echo 'macOS only; Linux uses its system libarchive.' >&2; exit 1; }
IFS=' ' read -r VERSION NAME HASH URL < <(python3 - <<'PY'
import json
v=json.load(open('Vendor/engines.lock.json'))['libarchive']
print(v['version'],v['file'],v['sha256'],v['url'])
PY
)
CACHE="${ARCORA_DOWNLOAD_CACHE:-$ROOT/.downloads}"
mkdir -p "$CACHE" Vendor/libarchive/include Vendor/libarchive/lib Vendor/UpstreamSource
ASSET="$CACHE/$NAME"
if [ ! -f "$ASSET" ]; then
  [ "${OFFLINE:-0}" != 1 ] || { echo "Offline cache is missing $NAME" >&2; exit 1; }
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 600 "$URL" -o "$ASSET.partial"
  mv "$ASSET.partial" "$ASSET"
fi
[ "$(shasum -a 256 "$ASSET" | cut -d ' ' -f 1)" = "$HASH" ] || { echo 'libarchive SHA-256 mismatch.' >&2; exit 1; }
cp "$ASSET" Vendor/UpstreamSource/
IFS=' ' read -r XZ_VERSION XZ_NAME XZ_HASH XZ_URL < <(python3 - <<'PY'
import json
v=json.load(open('Vendor/engines.lock.json'))['xz']
print(v['version'],v['file'],v['sha256'],v['url'])
PY
)
XZ_ASSET="$CACHE/$XZ_NAME"
if [ ! -f "$XZ_ASSET" ]; then
  [ "${OFFLINE:-0}" != 1 ] || { echo "Offline cache is missing $XZ_NAME" >&2; exit 1; }
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 600 "$XZ_URL" -o "$XZ_ASSET.partial"
  mv "$XZ_ASSET.partial" "$XZ_ASSET"
fi
[ "$(shasum -a 256 "$XZ_ASSET" | cut -d ' ' -f 1)" = "$XZ_HASH" ] || { echo 'XZ SHA-256 mismatch.' >&2; exit 1; }
cp "$XZ_ASSET" Vendor/UpstreamSource/
if [ -f Vendor/libarchive/version.txt ] && [ "$(cat Vendor/libarchive/version.txt)" = "$VERSION" ] &&
   [ -f Vendor/libarchive/include/archive.h ] && [ -f Vendor/libarchive/COPYING ] &&
   [ -f Vendor/libarchive/xz-version.txt ] && [ "$(cat Vendor/libarchive/xz-version.txt)" = "$XZ_VERSION" ] &&
   xcrun lipo Vendor/libarchive/lib/liblzma.a -verify_arch arm64 x86_64 2>/dev/null &&
   xcrun lipo Vendor/libarchive/lib/libarchive.a -verify_arch arm64 x86_64 2>/dev/null; then
  echo "libarchive $VERSION universal library is ready."
  exit 0
fi
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
tar -xJf "$ASSET" -C "$BUILD"
tar -xzf "$XZ_ASSET" -C "$BUILD"
SOURCE="$BUILD/libarchive-$VERSION"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$ROOT/.build/native-logs"
# Do not let pkg-config, Homebrew headers/libraries or developer flags leak in.
for ARCH in arm64 x86_64; do
  mkdir -p "$BUILD/xz-build-$ARCH"
  echo "Building liblzma $XZ_VERSION for ${ARCH}..."
  (
    cd "$BUILD/xz-build-$ARCH"
    env -u CPATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
      PATH=/usr/bin:/bin:/usr/sbin:/sbin PKG_CONFIG=/usr/bin/false \
      CC="$(xcrun --find clang)" CFLAGS="-O2 -arch $ARCH -mmacosx-version-min=14.0" \
      CPPFLAGS="-isysroot $SDK" LDFLAGS="-arch $ARCH -isysroot $SDK -mmacosx-version-min=14.0" \
      "$BUILD/xz-$XZ_VERSION/configure" --host="$ARCH-apple-darwin" --prefix="$BUILD/xz-$ARCH" \
      --disable-shared --enable-static --disable-xz --disable-xzdec --disable-lzmadec \
      --disable-lzmainfo --disable-scripts --disable-nls --disable-doc --disable-dependency-tracking || exit 1
    /usr/bin/make -j "$(sysctl -n hw.ncpu)" install
  ) > "$ROOT/.build/native-logs/xz-$ARCH.txt" 2>&1 || { tail -80 "$ROOT/.build/native-logs/xz-$ARCH.txt"; exit 1; }
  mkdir -p "$BUILD/$ARCH"
  echo "Building libarchive $VERSION for ${ARCH}..."
  (
    cd "$BUILD/$ARCH"
    env -u CPATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
      PATH=/usr/bin:/bin:/usr/sbin:/sbin PKG_CONFIG=/usr/bin/false \
      CC="$(xcrun --find clang)" CFLAGS="-O2 -std=gnu11 -arch $ARCH -isysroot $SDK -mmacosx-version-min=14.0" \
      CPPFLAGS="-isysroot $SDK -I$BUILD/xz-$ARCH/include" LDFLAGS="-L$BUILD/xz-$ARCH/lib -arch $ARCH -isysroot $SDK -mmacosx-version-min=14.0" \
      "$SOURCE/configure" --host="$ARCH-apple-darwin" --disable-shared --enable-static \
      --disable-bsdtar --disable-bsdcat --disable-bsdcpio --disable-bsdunzip \
      --disable-dependency-tracking --disable-acl --disable-xattr \
      --without-libb2 --without-lz4 --without-zstd --without-lzo2 \
      --without-openssl --without-mbedtls --without-nettle --without-xml2 --without-expat \
      --without-libiconv-prefix || { cp config.log "$ROOT/.build/native-logs/config-$ARCH.log"; exit 1; }
    /usr/bin/make -j "$(sysctl -n hw.ncpu)" libarchive.la
  ) > "$ROOT/.build/native-logs/libarchive-$ARCH.txt" 2>&1 || {
    tail -80 "$ROOT/.build/native-logs/libarchive-$ARCH.txt"; exit 1;
  }
done
xcrun lipo -create "$BUILD/arm64/.libs/libarchive.a" "$BUILD/x86_64/.libs/libarchive.a" -output Vendor/libarchive/lib/libarchive.a
xcrun lipo Vendor/libarchive/lib/libarchive.a -verify_arch arm64 x86_64
xcrun lipo -create "$BUILD/xz-arm64/lib/liblzma.a" "$BUILD/xz-x86_64/lib/liblzma.a" -output Vendor/libarchive/lib/liblzma.a
xcrun lipo Vendor/libarchive/lib/liblzma.a -verify_arch arm64 x86_64
cp "$SOURCE/libarchive/archive.h" "$SOURCE/libarchive/archive_entry.h" Vendor/libarchive/include/
cp "$SOURCE/COPYING" Vendor/libarchive/
cp "$BUILD/xz-$XZ_VERSION/COPYING" Vendor/libarchive/XZ-COPYING
printf '%s\n' "$VERSION" > Vendor/libarchive/version.txt
printf '%s\n' "$XZ_VERSION" > Vendor/libarchive/xz-version.txt
echo "libarchive $VERSION is ready (arm64 + x86_64, macOS 14+)."
