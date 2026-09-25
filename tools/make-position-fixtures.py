"""Build small, original fixtures; no user documents or credentials are used."""
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo

root = Path(__file__).resolve().parents[1] / "spec/fixtures/positions"
root.mkdir(exist_ok=True)
chapters = [
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Position fixture</title></head>'
    '<body><style>p { margin: 0 }</style><p id="intro">Alpha 😀 beta &amp; gamma.</p>'
    '<p id="nested">Before <em>nested words</em> after.</p><p id="spaces">A  B\nC</p></body></html>',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Appendix</title></head>'
    '<body><p id="appendix">Another chapter with café and 漢字.</p></body></html>',
]
entries = {
    "mimetype": "application/epub+zip",
    "META-INF/container.xml": '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    "OPS/book.opf": '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">zotero-position-fixture</dc:identifier><dc:title>Position fixture</dc:title><dc:language>en</dc:language></metadata><manifest><item id="chap1" href="one.xhtml" media-type="application/xhtml+xml"/><item id="chap2" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chap1"/><itemref idref="chap2" linear="no"/></spine></package>',
    "OPS/one.xhtml": chapters[0], "OPS/two.xhtml": chapters[1],
}
with ZipFile(root / "sample.epub", "w") as archive:
    for name, content in entries.items():
        info = ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
        archive.writestr(info, content.encode(), compress_type=0 if name == "mimetype" else ZIP_DEFLATED)
# A non-XHTML spine resource changes native DocFragment numbering after DOM 20240114.
mixed = dict(entries)
mixed["OPS/book.opf"] = entries["OPS/book.opf"].replace('</manifest>', '<item id="svg" href="picture.svg" media-type="image/svg+xml"/></manifest>').replace('<itemref idref="chap2"', '<itemref idref="svg"/><itemref idref="chap2"')
mixed["OPS/picture.svg"] = '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100"/></svg>'
with ZipFile(root / "mixed.epub", "w") as archive:
    for name, content in mixed.items():
        archive.writestr(ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0)), content.encode(), compress_type=0 if name == "mimetype" else ZIP_DEFLATED)
unsafe = dict(entries)
unsafe["OPS/one.xhtml"] = chapters[0].replace('<body>', '<body><math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>')
unsafe["OPS/two.xhtml"] = chapters[1].replace('<body>', '<body><object data="picture.svg"/>')
with ZipFile(root / "unsupported.epub", "w") as archive:
    for name, content in unsafe.items():
        archive.writestr(ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0)), content.encode(), compress_type=0 if name == "mimetype" else ZIP_DEFLATED)
cases = [
    {"pointer": "/body/DocFragment[1]/body/p[1]/text().0", "section": 0, "selector": "#intro", "offset": 0},
    {"pointer": "/body/DocFragment[1]/body/p[1]/text().8", "section": 0, "selector": "#intro", "offset": 9},
    {"pointer": "/body/DocFragment[1]/body/p[2]/em/text().3", "section": 0, "selector": "#nested em", "offset": 3},
    {"pointer": "/body/DocFragment[1]/body/p[2]/em/text().10", "section": 0, "selector": "#nested em", "offset": 10},
    {"pointer": "/body/DocFragment[2]/body/p/text().20", "section": 1, "selector": "#appendix", "offset": 20},
    {"pointer": "/body/DocFragment[1]/body/p[3]/text().3", "section": 0, "selector": "#spaces", "offset": 4},
    {"pointer": "/body/DocFragment[1]/body/p[2]/text()[2].3", "section": 0, "selector": "#nested", "child": 2, "offset": 3},
]
(root / "source.json").write_text(json.dumps({"chapters": chapters, "cases": cases}, ensure_ascii=False, indent=2) + "\n")

# Original three-page PDF, including rotation and printed Roman page labels.
objects = [b'<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [0 << /S /r >>] >> >>',
           b'<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>']
for index in range(3):
    content = f'BT /F1 14 Tf 20 200 Td (Position fixture page {index + 1}) Tj ET'.encode()
    objects.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 320] /Rotate {90 if index == 1 else 0} /Resources << /Font << /F1 9 0 R >> >> /Contents {4 + 2 * index} 0 R >>'.encode())
    objects.append(b'<< /Length ' + str(len(content)).encode() + b' >>\nstream\n' + content + b'\nendstream')
objects.append(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
pdf = bytearray(b'%PDF-1.4\n')
offsets = [0]
for index, obj in enumerate(objects, 1):
    offsets.append(len(pdf)); pdf.extend(f'{index} 0 obj\n'.encode() + obj + b'\nendobj\n')
xref = len(pdf)
pdf.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
for offset in offsets[1:]: pdf.extend(f'{offset:010d} 00000 n \n'.encode())
pdf.extend(f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
(root / 'sample.pdf').write_bytes(pdf)
