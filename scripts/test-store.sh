#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_TARGET="$(uname -m)-apple-macosx15.0"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -target "$TEST_TARGET" -emit-library -emit-module -module-name YIClassCore Sources/Core/*.swift -o "$BUILD_DIR/libYIClassCore.dylib" -emit-module-path "$BUILD_DIR/YIClassCore.swiftmodule"
swiftc -target "$TEST_TARGET" -parse-as-library -I "$BUILD_DIR" -L "$BUILD_DIR" -lYIClassCore -Xlinker -rpath -Xlinker "$BUILD_DIR" Sources/App/ImageAttachment.swift Sources/App/AssistantHistoryModels.swift Sources/App/AppStore.swift Sources/App/DocumentFileReader.swift Sources/Shared/SharedGroup.swift Sources/Shared/SharedLibrary.swift scripts/store-integration/main.swift -o "$BUILD_DIR/test-store"
"$BUILD_DIR/test-store"
