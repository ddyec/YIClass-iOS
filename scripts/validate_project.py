#!/usr/bin/env python3
"""Portable checks; these do not claim to replace an Xcode build."""
from pathlib import Path
import json
import plistlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
project = ROOT / 'YIClass.xcodeproj/project.pbxproj'
before = project.read_bytes()
subprocess.run([sys.executable, str(ROOT / 'scripts/generate_project.py')], check=True, capture_output=True)
assert before == project.read_bytes(), 'Project is stale; commit regenerated project'
text = project.read_text()
defined = re.findall(r'^\s*([0-9A-F]{24}) = \{', text, flags=re.M)
assert len(defined) == len(set(defined)), 'Duplicate project object IDs'
referenced = re.findall(r'\b[0-9A-F]{24}\b', text)
assert set(referenced) <= set(defined), 'Dangling project object ID'
assert 'IPHONEOS_DEPLOYMENT_TARGET = "26.0"' in text
assert 'SUPPORTS_MACCATALYST = "NO"' in text
assert not list(ROOT.glob('**/*.dart')), 'Flutter sources must not be included'
for file in (ROOT / 'Sources/App').glob('*.swift'):
    assert file.relative_to(ROOT).as_posix() in text, f'Missing build source: {file}'
for file in ROOT.glob('**/*.json'):
    if '.build' not in file.parts and '.git' not in file.parts:
        json.loads(file.read_text())
with (ROOT / 'Sources/App/PrivacyInfo.xcprivacy').open('rb') as stream:
    privacy = plistlib.load(stream)
assert privacy['NSPrivacyTracking'] is False
for folder in ['App', 'Widget']:
    entitlement = plistlib.loads((ROOT / f'Sources/{folder}/YIClass.entitlements').read_bytes())
    assert entitlement['com.apple.security.application-groups'] == ['group.com.ddyec.YIClassNative']
widget_info = plistlib.loads((ROOT / 'Sources/Widget/Info.plist').read_bytes())
assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
assert 'Embed App Extensions' in text and 'com.apple.product-type.app-extension' in text
app_info = plistlib.loads((ROOT / 'Sources/App/Info.plist').read_bytes())
assert app_info.get('NSSupportsLiveActivities') is True, 'Missing Live Activities capability'
assert 'LastLessonLiveActivity.swift' in text and 'LastLessonActivityAttributes.swift' in text
for folder in ['Widget', 'Shared']:
    for file in (ROOT / f'Sources/{folder}').glob('*.swift'):
        assert file.relative_to(ROOT).as_posix() in text, f'Missing widget/shared source: {file}'
scheme = ET.parse(ROOT / 'YIClass.xcodeproj/xcshareddata/xcschemes/YIClass.xcscheme')
assert scheme.find('.//TestableReference') is not None
png = (ROOT / 'Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
assert png[:8] == b'\x89PNG\r\n\x1a\n'
assert struct.unpack('>II', png[16:24]) == (1024, 1024), 'App icon must be 1024 square'
assert (ROOT / 'Sources/App/Assets.xcassets/Brand.imageset/Brand.png').read_bytes() == png, 'Legacy YC branding must use the normal current app logo'
assistant_logo = (ROOT / 'scripts/artwork/AssistantLogo-original.png').read_bytes()
assert assistant_logo[:8] == b'\x89PNG\r\n\x1a\n' and assistant_logo[25] == 6, 'Assistant line logo must be an RGBA PNG'
assistant_asset = json.loads((ROOT / 'Sources/App/Assets.xcassets/AssistantLogo.imageset/Contents.json').read_text())
assert assistant_asset['images'][0]['filename'] == 'AssistantLogo.pdf'
assert assistant_asset['properties']['preserves-vector-representation'] is True
vector = ROOT / 'Sources/App/Assets.xcassets/AssistantLogo.imageset/AssistantLogo.pdf'
before_vector = vector.read_bytes()
subprocess.run([sys.executable, str(ROOT / 'scripts/prepare-assistant-logo.py')], check=True, capture_output=True)
assert before_vector == vector.read_bytes(), 'Assistant vector is stale'
assert b'/MediaBox [0 0 32 32]' in before_vector
assert (ROOT / 'LICENSE').exists() and (ROOT / 'NOTICE').exists()
print(f'PASS: deterministic Xcode project; {len(defined)} objects; source membership; iOS target; assets; privacy manifest; scheme; attribution')
