#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist

case "${1:-}" in
  device)
    xcodebuild -project YIClass.xcodeproj -scheme YIClass \
      -configuration Release -destination 'generic/platform=iOS' \
      -archivePath build/YIClass.xcarchive -derivedDataPath build/DeviceDerivedData \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
      archive 2>&1 | tee dist/device-build.log
    mkdir -p build/device-package/Payload
    ditto build/YIClass.xcarchive/Products/Applications/YIClass.app build/device-package/Payload/YIClass.app
    # Keep the real entitlement declarations in both bundles and their ad-hoc
    # signatures so re-signing tools can retain them. No Apple identity is used.
    APP_BUNDLE=build/device-package/Payload/YIClass.app
    WIDGET_BUNDLE="$APP_BUNDLE/PlugIns/YIClassWidget.appex"
    cp Sources/App/YIClass.entitlements "$APP_BUNDLE/AppGroup.entitlements"
    cp Sources/Widget/YIClass.entitlements "$WIDGET_BUNDLE/AppGroup.entitlements"
    codesign --force --sign - --entitlements "$WIDGET_BUNDLE/AppGroup.entitlements" --generate-entitlement-der "$WIDGET_BUNDLE"
    codesign --force --sign - --entitlements "$APP_BUNDLE/AppGroup.entitlements" --generate-entitlement-der "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
    (
      cd build/device-package
      ditto -c -k --keepParent Payload ../../dist/YIClass-iOS26-resign.ipa
    )
    python3 scripts/verify_build.py device dist/YIClass-iOS26-resign.ipa dist/device-manifest.json
    (cd dist && shasum -a 256 YIClass-iOS26-resign.ipa device-manifest.json > device-SHA256SUMS.txt)
    ;;
  simulator)
    xcodebuild -project YIClass.xcodeproj -scheme YIClass \
      -configuration Release -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/SimulatorDerivedData \
      CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO \
      build 2>&1 | tee dist/simulator-build.log
    python3 scripts/verify_build.py simulator build/SimulatorDerivedData/Build/Products/Release-iphonesimulator/YIClass.app dist/simulator-manifest.json
    tar -czf dist/YIClass-iOS26-simulator.tar.gz -C build/SimulatorDerivedData/Build/Products/Release-iphonesimulator YIClass.app
    (cd dist && shasum -a 256 YIClass-iOS26-simulator.tar.gz simulator-manifest.json > simulator-SHA256SUMS.txt)
    ;;
  *)
    echo 'Usage: bash scripts/package-build.sh device|simulator' >&2
    exit 2
    ;;
esac
