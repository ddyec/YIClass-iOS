#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -emit-library -emit-module -module-name YIClassCore Sources/Core/*.swift -o "$BUILD_DIR/libYIClassCore.dylib" -emit-module-path "$BUILD_DIR/YIClassCore.swiftmodule"
swiftc -I "$BUILD_DIR" -L "$BUILD_DIR" -lYIClassCore -Xlinker -rpath -Xlinker "$BUILD_DIR" Sources/App/PDFGridReader.swift scripts/pdf-integration/main.swift -o "$BUILD_DIR/test-pdf"
"$BUILD_DIR/test-pdf" "${1:-Tests/Fixtures/timetable-grid.pdf}"
