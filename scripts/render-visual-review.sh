#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/visual-review
# Compile the production logo view; only replace asset-catalog lookup with the
# identical PDF file because this review executable has no app resource bundle.
python3 - <<'PY'
from pathlib import Path
s = Path('Sources/App/Design.swift').read_text()
a = s.index('struct AssistantLogo: View {')
b = s.index('\nprivate struct FloatingNavigationScrollKey:', a)
s = s[a:b].replace('Image("AssistantLogo")', 'Image(nsImage: NSImage(contentsOfFile: "Sources/App/Assets.xcassets/AssistantLogo.imageset/AssistantLogo.pdf")!)')
Path('dist/visual-review/AssistantLogo.swift').write_text('import AppKit\nimport SwiftUI\n' + s)
PY
xcrun swiftc -parse-as-library Sources/Widget/LockScreenCourseCard.swift \
  dist/visual-review/AssistantLogo.swift scripts/visual-review/main.swift \
  -o dist/visual-review/render
./dist/visual-review/render
