"""Verify the installable archive matches the working tree's runtime files."""
from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parent.parent
sources = [root / "main.lua", root / "_meta.lua"]
sources += list((root / "src").glob("*.lua")) + list(root.glob("LICENSE*"))
expected = {"zotero.koplugin/" + str(p.relative_to(root)): p for p in sources}
with ZipFile(root / "dist/zotero.koplugin.zip") as archive:
    files = [entry.filename for entry in archive.infolist() if not entry.is_dir()]
    assert len(files) == len(set(files)), "Duplicate archive entries"
    assert set(files) == set(expected), "Missing or unexpected runtime files"
    for name, source in expected.items():
        assert archive.read(name) == source.read_bytes(), f"Stale packaged file: {name}"
print(f"Verified {len(expected)} packaged files")
