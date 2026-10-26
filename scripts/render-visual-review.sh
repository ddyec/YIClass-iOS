#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/visual-review
python3 - <<'PY'
from pathlib import Path
s = Path('Sources/App/Design.swift').read_text()
a = s.index('struct AssistantLogo: View {')
# AssistantLogo is the final declaration; the obsolete custom scroll key is gone.
s = s[a:].replace('Image("AssistantLogo")', 'Image(nsImage: NSImage(contentsOfFile: "Sources/App/Assets.xcassets/AssistantLogo.imageset/AssistantLogo.pdf")!)')
Path('dist/visual-review/AssistantLogo.swift').write_text('import AppKit\nimport SwiftUI\n' + s)
s = Path('Sources/App/Design.swift').read_text()
a = s.index('extension Color {'); b = s.index('\nstruct AppBackdrop:', a)
Path('dist/visual-review/Color.swift').write_text('import SwiftUI\n' + s[a:b])
PY
TEST_TARGET="$(uname -m)-apple-macosx15.0"
xcrun swiftc -target "$TEST_TARGET" -emit-library -emit-module -module-name YIClassCore Sources/Core/*.swift \
  -o dist/visual-review/libYIClassCore.dylib -emit-module-path dist/visual-review/YIClassCore.swiftmodule
xcrun swiftc -target "$TEST_TARGET" -parse-as-library -I dist/visual-review -L dist/visual-review -lYIClassCore \
  -Xlinker -rpath -Xlinker "$(pwd)/dist/visual-review" \
  Sources/Widget/LockScreenCourseCard.swift Sources/Widget/TodoWidgetContent.swift Sources/Widget/AgendaActivityCard.swift \
  Sources/App/AgendaCards.swift dist/visual-review/Color.swift \
  dist/visual-review/AssistantLogo.swift scripts/visual-review/main.swift \
  -o dist/visual-review/render
./dist/visual-review/render
