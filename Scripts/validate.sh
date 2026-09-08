#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 Scripts/check-public-tree.py --self-test
if [ -d .git ] || [ -f .git ]; then
  python3 Scripts/check-public-tree.py
else
  echo 'Source export without Git metadata: run the staged public-tree audit before publishing from a repository.'
fi
python3 Scripts/check-localization.py
for file in Scripts/*.sh; do bash -n "$file"; done
swift build
swift test
# Set ARCORA_REQUIRE_7ZZ=1 after bootstrap to make missing official engine a failure.
