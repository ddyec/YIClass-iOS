#!/usr/bin/env python3
"""Convert the editable stroke artwork into a deterministic vector PDF asset."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
svg = ET.parse(ROOT / 'scripts/artwork/AssistantLogo.svg').getroot()
ops = ['q', '1 0 0 -1 0 32 cm', '0 G', '1 J', '1 j']
for group in svg:
    ops.append(group.attrib['stroke-width'] + ' w')
    for shape in group:
        tokens = re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?', shape.attrib['d'])
        i = 0
        while i < len(tokens):
            cmd = tokens[i]; i += 1
            count = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}[cmd]
            ops.append(' '.join(tokens[i:i+count] + [{'M':'m','L':'l','C':'c','Z':'h'}[cmd]]))
            i += count
        ops.append('S')
ops.append('Q')
stream = ('\n'.join(ops) + '\n').encode()
objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
 b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
 b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 32 32] /Resources << >> /Contents 4 0 R >>',
 b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'endstream']
pdf = bytearray(b'%PDF-1.4\n'); offsets = [0]
for i, obj in enumerate(objects, 1):
    offsets.append(len(pdf)); pdf.extend(f'{i} 0 obj\n'.encode() + obj + b'\nendobj\n')
xref = len(pdf)
pdf.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
for offset in offsets[1:]: pdf.extend(f'{offset:010} 00000 n \n'.encode())
pdf.extend(f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
(ROOT / 'Sources/App/Assets.xcassets/AssistantLogo.imageset/AssistantLogo.pdf').write_bytes(pdf)
print('Generated vector AssistantLogo.pdf from editable stroke paths')
