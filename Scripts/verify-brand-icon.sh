#!/bin/bash
# Render the production SwiftUI view against an actual packaged resource bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ "$#" -ge 1 ] && [ -d "$1/Contents/Resources" ] || {
  echo 'Usage: bash Scripts/verify-brand-icon.sh APP [--snapshots DIRECTORY]' >&2; exit 1
}
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arcora-brand-check.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/Arcora/BrandIcon.swift Scripts/BrandIconValidation.swift -o "$PROBE_DIR/verify-brand-icon"
"$PROBE_DIR/verify-brand-icon" "$@"
"$PROBE_DIR/verify-brand-icon" "$1" --fallback
