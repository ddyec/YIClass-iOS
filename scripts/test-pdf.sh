#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_TARGET="$(uname -m)-apple-macosx15.0"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -target "$TEST_TARGET" -emit-library -emit-module -module-name YIClassCore Sources/Core/*.swift -o "$BUILD_DIR/libYIClassCore.dylib" -emit-module-path "$BUILD_DIR/YIClassCore.swiftmodule"
swiftc -target "$TEST_TARGET" -I "$BUILD_DIR" -L "$BUILD_DIR" -lYIClassCore -Xlinker -rpath -Xlinker "$BUILD_DIR" Sources/App/PDFGridReader.swift Tests/Core/PDFAudit.swift scripts/pdf-integration/main.swift -o "$BUILD_DIR/test-pdf"
"$BUILD_DIR/test-pdf" "${1:-Tests/Fixtures/timetable-grid.pdf}"
