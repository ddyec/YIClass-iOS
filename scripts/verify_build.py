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

kind, target, output = sys.argv[1:]
target = Path(target)
if kind == 'device':
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None, 'Corrupt IPA'
        prefix = 'Payload/YIClass.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        executable = archive.read(prefix + info['CFBundleExecutable'])
        names = archive.namelist()
        assert prefix + 'Assets.car' in names, 'Missing app resources'
        assert prefix + 'PrivacyInfo.xcprivacy' in names, 'Missing privacy manifest'
        assert prefix + 'embedded.mobileprovision' not in names, 'Unexpected provisioning profile'
        assert not any(name.startswith(prefix + '_CodeSignature/') for name in names), 'Expected unsigned IPA'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'IPA contains a simulator build'
    assert struct.unpack_from('<II', executable) == (0xFEEDFACF, 0x0100000C), 'Expected an arm64 Mach-O executable'
    size = target.stat().st_size
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
elif kind == 'simulator':
    info = plistlib.loads((target / 'Info.plist').read_bytes())
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
    'sourceCommit': os.environ.get('GITHUB_SHA', 'local'),
    'createdUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'sizeBytes': size,
    'sha256': digest,
    'signing': 'unsigned; requires your own Apple signing identity before iPhone installation' if kind == 'device' else 'simulator-only; no Apple developer certificate required',
}
Path(output).write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
print(json.dumps(manifest, ensure_ascii=False))
