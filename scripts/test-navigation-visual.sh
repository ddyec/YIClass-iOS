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
# Let Xcode manage simulator startup; a separate bootstatus process can hang
# indefinitely on hosted ARM runners before any UI test starts.
xcodebuild -project YIClass.xcodeproj -scheme YIClass \
  -destination "platform=iOS Simulator,id=$YICLASS_REVIEW_DEVICE" -destination-timeout 120 \
  -derivedDataPath build/NavigationReview -resultBundlePath dist/NavigationReview.xcresult \
  -parallel-testing-enabled NO -only-testing:YIClassUITests/NavigationPolishTests \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 300 \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test 2>&1 | tee dist/navigation-review/test.log
