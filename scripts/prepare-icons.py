#!/usr/bin/env python3
"""Produce explicit iPhone/iPad icon renditions from the approved 1024px artwork."""
from pathlib import Path
import json
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
DEST = ROOT / 'Sources/App/Assets.xcassets/AppIconSlate.appiconset'
def dimensions(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    return struct.unpack('>II', data[16:24])

assert dimensions(SOURCE) == (1024, 1024)
DEST.mkdir(exist_ok=True)
images = []
for idiom, sizes in [
    ('iphone', [(20, [2, 3]), (29, [2, 3]), (40, [2, 3]), (60, [2, 3])]),
    ('ipad', [(20, [1, 2]), (29, [1, 2]), (40, [1, 2]), (76, [1, 2]), (83.5, [2])])
]:
    for size, scales in sizes:
        for scale in scales:
            pixels = int(size * scale)
            name = f'Icon-{pixels}.png'
            target = DEST / name
            if not target.exists() or target.stat().st_mtime < SOURCE.stat().st_mtime:
                subprocess.run(['/usr/bin/sips', '-z', str(pixels), str(pixels), str(SOURCE),
                                '--out', str(target)], check=True, capture_output=True)
            assert dimensions(target) == (pixels, pixels)
            images.append({'idiom': idiom, 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': name})
shutil.copyfile(SOURCE, DEST / 'Icon-1024.png')
images.append({'idiom': 'ios-marketing', 'size': '1024x1024', 'scale': '1x', 'filename': 'Icon-1024.png'})
(DEST / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
assert dimensions(DEST / 'Icon-40.png') == (40, 40)
assert dimensions(DEST / 'Icon-60.png') == (60, 60)
print('PASS: explicit notification icons (20pt @2x/@3x), settings and home-screen icons use approved slate artwork')
