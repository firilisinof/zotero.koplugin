"""Original coordinate fixture: crop offsets, all rotations, inherited page values and UserUnit."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "spec/fixtures/positions"
objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
           b'<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R 9 0 R 11 0 R] /Count 5 /MediaBox [10 20 410 620] /CropBox [30 60 330 560] /Rotate 270 >>']
for index, rotation in enumerate([0, 90, 180, 270, None]):
    content = b'BT /F1 14 Tf 50 500 Td (Highlight coordinate fixture) Tj ET'
    local_rotation = f'/Rotate {rotation}' if rotation is not None else ''
    objects.append(f'<< /Type /Page /Parent 2 0 R {local_rotation} /UserUnit {2 if index == 4 else 1} /Resources << /Font << /F1 13 0 R >> >> /Contents {4 + 2 * index} 0 R >>'.encode())
    objects.append(b'<< /Length ' + str(len(content)).encode() + b' >>\nstream\n' + content + b'\nendstream')
objects.append(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
pdf, offsets = bytearray(b'%PDF-1.7\n'), [0]
for index, obj in enumerate(objects, 1):
    offsets.append(len(pdf)); pdf.extend(f'{index} 0 obj\n'.encode() + obj + b'\nendobj\n')
xref = len(pdf)
pdf.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
for offset in offsets[1:]:
    pdf.extend(f'{offset:010d} 00000 n \n'.encode())
pdf.extend(f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
(root / 'geometry.pdf').write_bytes(pdf)
