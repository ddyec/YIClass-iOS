#!/usr/bin/env python3
"""Validate the actual packaged executable and platform, not just xcodebuild's exit status."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import plistlib
import struct
import sys
import zipfile

def embedded_entitlements(binary):
    # arm64 Mach-O LC_CODE_SIGNATURE → embedded-signature SuperBlob → XML entitlements.
    command_count = struct.unpack_from('<I', binary, 16)[0]
    cursor = 32
    for _ in range(command_count):
        command, size = struct.unpack_from('<II', binary, cursor)
        if command == 0x1D:
            offset, length = struct.unpack_from('<II', binary, cursor + 8)
            signature = binary[offset:offset + length]
            magic, _, count = struct.unpack_from('>III', signature)
            assert magic == 0xFADE0CC0, 'Expected embedded signature'
            for index in range(count):
                _, blob_offset = struct.unpack_from('>II', signature, 12 + index * 8)
                blob_magic, blob_length = struct.unpack_from('>II', signature, blob_offset)
                if blob_magic == 0xFADE7171:
                    return plistlib.loads(signature[blob_offset + 8:blob_offset + blob_length])
        cursor += size
    raise AssertionError('Missing signed App Group entitlements')

kind, target, output = sys.argv[1:]
target = Path(target)
if kind == 'device':
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None, 'Corrupt IPA'
        prefix = 'Payload/YIClass.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        executable = archive.read(prefix + info['CFBundleExecutable'])
        names = archive.namelist()
        extension = prefix + 'PlugIns/YIClassWidget.appex/'
        widget_info = plistlib.loads(archive.read(extension + 'Info.plist'))
        widget_binary = archive.read(extension + widget_info['CFBundleExecutable'])
        assert struct.unpack_from('<II', widget_binary) == (0xFEEDFACF, 0x0100000C), 'Missing arm64 widget executable'
        assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
        assert widget_info['MinimumOSVersion'] == '26.0'
        assert prefix + 'Assets.car' in names, 'Missing app resources'
        assert prefix + 'PrivacyInfo.xcprivacy' in names, 'Missing privacy manifest'
        assert prefix + 'embedded.mobileprovision' not in names, 'Unexpected provisioning profile'
        for bundle, binary in [(prefix, executable), (extension, widget_binary)]:
            groups = embedded_entitlements(binary)['com.apple.security.application-groups']
            assert groups == ['group.com.ddyec.YIClassNative'], 'Signed App Group mismatch'
            assert plistlib.loads(archive.read(bundle + 'AppGroup.entitlements'))['com.apple.security.application-groups'] == groups
            assert bundle + '_CodeSignature/CodeResources' in names, 'Missing resource signature'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'IPA contains a simulator build'
    assert struct.unpack_from('<II', executable) == (0xFEEDFACF, 0x0100000C), 'Expected an arm64 Mach-O executable'
    size = target.stat().st_size
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
elif kind == 'simulator':
    info = plistlib.loads((target / 'Info.plist').read_bytes())
    widget_info = plistlib.loads((target / 'PlugIns/YIClassWidget.appex/Info.plist').read_bytes())
    assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    binary = target / info['CFBundleExecutable']
    executable = binary.read_bytes()
    assert 'iPhoneSimulator' in info['CFBundleSupportedPlatforms'], 'Expected a simulator app'
    assert os.access(binary, os.X_OK), 'App executable lost its execute permission'
    assert executable[:4] in (bytes.fromhex('cafebabe'), bytes.fromhex('bebafeca'), bytes.fromhex('cffaedfe')), 'Not a Mach-O executable'
    size = sum(path.stat().st_size for path in target.rglob('*') if path.is_file())
    digest = hashlib.sha256(executable).hexdigest()
else:
    raise SystemExit('Expected device or simulator')

assert info['CFBundleIdentifier'] == 'com.ddyec.YIClassNative'
assert info['MinimumOSVersion'] == '26.0'
assert size > 100_000, 'Build artifact is unexpectedly small'
manifest = {
    'platform': kind,
    'bundleIdentifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'minimumOS': info['MinimumOSVersion'],
    'supportedPlatforms': info['CFBundleSupportedPlatforms'],
    'widgetExtension': widget_info['CFBundleIdentifier'],
    'sourceCommit': os.environ.get('GITHUB_SHA', 'local'),
    'createdUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'sizeBytes': size,
    'sha256': digest,
    'appGroup': 'group.com.ddyec.YIClassNative',
    'signing': 'ad-hoc signed with matching App Group entitlements; requires Apple-authorized re-signing and matching App Group profiles before iPhone installation' if kind == 'device' else 'simulator-only; no Apple developer certificate required',
}
Path(output).write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
print(json.dumps(manifest, ensure_ascii=False))
