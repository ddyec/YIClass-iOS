#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/validate_project.py
swift test
if [[ "$(uname -s)" == "Darwin" ]]; then
  xcodebuild -project YIClass.xcodeproj -scheme YIClass \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
    CODE_SIGNING_ALLOWED=NO build
fi
