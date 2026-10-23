#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/navigation-review
xcrun simctl list devices available -j > dist/navigation-review/devices.json
YICLASS_REVIEW_DEVICE=$(python3 - <<'PY'
import json
from pathlib import Path
all_devices=json.loads(Path('dist/navigation-review/devices.json').read_text())['devices']
phones=[d for runtime,devices in all_devices.items() if 'iOS-26-' in runtime for d in devices if d['name'].startswith('iPhone') and d['isAvailable']]
assert phones, 'No available iOS 26 iPhone simulator on this runner'
print(phones[0]['udid'])
PY
)
xcrun simctl boot "$YICLASS_REVIEW_DEVICE" || true
xcrun simctl bootstatus "$YICLASS_REVIEW_DEVICE" -b
xcodebuild -project YIClass.xcodeproj -scheme YIClass \
  -destination "platform=iOS Simulator,id=$YICLASS_REVIEW_DEVICE" \
  -derivedDataPath build/NavigationReview -resultBundlePath dist/NavigationReview.xcresult \
  -parallel-testing-enabled NO -only-testing:YIClassUITests/NavigationPolishTests \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test 2>&1 | tee dist/navigation-review/test.log
