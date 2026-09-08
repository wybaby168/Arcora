#!/bin/bash
# Universal native macOS app. Run bootstrap-engines.sh once before this script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ "$(uname -s)" = Darwin ] || { echo 'Building the app requires a Mac with Xcode 26+.' >&2; exit 1; }
xcrun --find swift >/dev/null
ICON_XCODE_MAJOR="$(xcodebuild -version | awk 'NR==1 { split($2, version, "."); print version[1] }')"
[[ "$ICON_XCODE_MAJOR" =~ ^[0-9]+$ ]] && [ "$ICON_XCODE_MAJOR" -ge 26 ] || { echo 'Select Xcode 26+ to compile the native macOS icon. The app still runs on macOS 14+.' >&2; exit 1; }
python3 Scripts/check-icon-assets.py
[ -x Vendor/7zip/7zz ] || { echo 'Run Scripts/bootstrap-engines.sh first.' >&2; exit 1; }
[ "$(cat Vendor/7zip/platform.txt)" = mac ] || { echo 'The cached engine is not a macOS binary. Bootstrap on this Mac first.' >&2; exit 1; }
[ -f Vendor/UpstreamSource/7z2603-src.tar.xz ] || { echo 'Corresponding upstream source is required; run bootstrap-engines.sh.' >&2; exit 1; }
xcrun lipo Vendor/7zip/7zz -verify_arch arm64 x86_64
xcrun lipo Vendor/libarchive/lib/libarchive.a -verify_arch arm64 x86_64
xcrun lipo Vendor/libarchive/lib/liblzma.a -verify_arch arm64 x86_64
if [ -n "${ARCORA_RAR_DISTRIBUTION_DIR:-}" ]; then
  echo 'This edition does not distribute the RAR encoder. Use the official browser download and local original-package import.' >&2; exit 1
fi
mkdir -p dist .local
APP="$ROOT/dist/Arcora.app"
TMP_APP="$ROOT/dist/.Arcora-build-$$.app"
trap 'rm -rf "$TMP_APP"' EXIT
mkdir -p "$TMP_APP/Contents/MacOS" "$TMP_APP/Contents/Helpers" "$TMP_APP/Contents/Resources/ThirdParty"
# No undocumented Xcode project generator or third-party Swift packages.
for ARCH in arm64 x86_64; do
  echo "Building native ${ARCH} binaries..."
  xcrun swift build -c release --arch "$ARCH" --scratch-path "$ROOT/.build/macos-$ARCH"
  BIN="$(xcrun swift build -c release --arch "$ARCH" --scratch-path "$ROOT/.build/macos-$ARCH" --show-bin-path)"
  printf '%s' "$BIN" > "$ROOT/dist/.bin-$ARCH"
done
ARM="$(cat dist/.bin-arm64)"
INTEL="$(cat dist/.bin-x86_64)"
xcrun lipo -create "$ARM/Arcora" "$INTEL/Arcora" -output "$TMP_APP/Contents/MacOS/Arcora"
xcrun lipo -create "$ARM/arcora-worker" "$INTEL/arcora-worker" -output "$TMP_APP/Contents/Helpers/arcora-worker"
xcrun lipo -create "$ARM/arcora-cli" "$INTEL/arcora-cli" -output "$TMP_APP/Contents/Helpers/arcora"
cp Vendor/7zip/7zz "$TMP_APP/Contents/Helpers/7zz"
# Resource accessor supports this conventional Contents/Resources location.
RESOURCES="$(find "$ARM" -maxdepth 1 -type d \( -name 'Arcora_Arcora.bundle' -o -name 'Arcora_Arcora.resources' \) -print -quit)"
[ -n "$RESOURCES" ] || { echo 'SwiftPM localization bundle is missing.' >&2; exit 1; }
cp -R "$RESOURCES" "$TMP_APP/Contents/Resources/"
cp Configuration/Info.plist "$TMP_APP/Contents/Info.plist"
cp -R Configuration/en.lproj Configuration/zh-Hans.lproj Configuration/ja.lproj "$TMP_APP/Contents/Resources/"
python3 Scripts/check-finder-services.py "$TMP_APP"
printf 'APPL????' > "$TMP_APP/Contents/PkgInfo"
cp LICENSE THIRD_PARTY_NOTICES.md "$TMP_APP/Contents/Resources/ThirdParty/"
cp -R Vendor/7zip/Licenses "$TMP_APP/Contents/Resources/ThirdParty/7-Zip-Licenses"
cp Vendor/UpstreamSource/7z2603-src.tar.xz "$TMP_APP/Contents/Resources/ThirdParty/"
cp Vendor/UpstreamSource/libarchive-3.8.9.tar.xz Vendor/UpstreamSource/xz-5.8.3.tar.gz "$TMP_APP/Contents/Resources/ThirdParty/"
cp Vendor/libarchive/COPYING "$TMP_APP/Contents/Resources/ThirdParty/libarchive-COPYING"
cp Vendor/libarchive/XZ-COPYING "$TMP_APP/Contents/Resources/ThirdParty/XZ-COPYING"
cp Documentation/USER_GUIDE.md "$TMP_APP/Contents/Resources/"
python3 Scripts/assert-distribution-clean.py "$TMP_APP"
xcrun swift Scripts/make-icon.swift "$TMP_APP/Contents/Resources/Arcora.icns"
xcrun swift Scripts/verify-icon.swift "$TMP_APP/Contents/Resources/Arcora.icns"
python3 Scripts/check-icon-assets.py "$TMP_APP"
bash Scripts/verify-brand-icon.sh "$TMP_APP"
chmod 755 "$TMP_APP/Contents/MacOS/Arcora" "$TMP_APP/Contents/Helpers/"*
plutil -lint "$TMP_APP/Contents/Info.plist"
IDENTITY="${SIGN_IDENTITY:--}"  # ad-hoc by default; not Developer ID or notarization
for FILE in "$TMP_APP/Contents/Helpers/7zz" "$TMP_APP/Contents/Helpers/arcora-worker" "$TMP_APP/Contents/Helpers/arcora"; do
  if [ "$IDENTITY" = - ]; then codesign --force --sign - "$FILE"; else codesign --force --options runtime --timestamp --sign "$IDENTITY" "$FILE"; fi
done
if [ -d "$TMP_APP/Contents/Helpers/rar" ]; then
  for ARCH in arm64 x86_64; do
    FILE="$TMP_APP/Contents/Helpers/rar/$ARCH/rar"
    if [ "$IDENTITY" = - ]; then codesign --force --sign - "$FILE"; else codesign --force --options runtime --timestamp --sign "$IDENTITY" "$FILE"; fi
  done
fi
if [ "$IDENTITY" = - ]; then
  codesign --force --sign - "$TMP_APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$TMP_APP"
fi
codesign --verify --deep --strict --verbose=2 "$TMP_APP"
for FILE in "$TMP_APP/Contents/MacOS/Arcora" "$TMP_APP/Contents/Helpers/7zz" "$TMP_APP/Contents/Helpers/arcora-worker" "$TMP_APP/Contents/Helpers/arcora"; do
  xcrun lipo "$FILE" -verify_arch arm64 x86_64
  if otool -L "$FILE" | awk '/^[[:space:]]+/{print $1}' | grep -E '/opt/homebrew|/usr/local|/Users/|/private/tmp|/var/folders'; then
    echo "Nonportable runtime dependency in $FILE" >&2; exit 1
  fi
done
# Replace only the known build output after a complete successful build.
if [ -e "$APP" ]; then mv "$APP" "$ROOT/.local/Arcora-previous-$(date +%Y%m%d%H%M%S).app"; fi
mv "$TMP_APP" "$APP"
rm -f dist/.bin-arm64 dist/.bin-x86_64
printf '\nBuilt: %s\n' "$APP"
if [ "$IDENTITY" = - ]; then echo 'Locally ad-hoc signed. Public distribution still needs Developer ID signing and notarization.'; fi
