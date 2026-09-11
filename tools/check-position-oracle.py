"""Run both actual engines; only extracts installed application code into a temp dir."""
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

plugin = Path(__file__).resolve().parents[1]
koreader = Path(os.environ.get("KOREADER_SRC", plugin.parent / "koreader"))
emulator = next(koreader.glob("koreader-emulator-*/koreader"))
app = Path(os.environ.get("ZOTERO_APP", "/Applications/Zotero.app"))
version = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
assert version == "10.0.1", f"Oracle extraction is pinned to Zotero 10.0.1, found {version}"
with zipfile.ZipFile(app / "Contents/Resources/app/omni.ja") as archive:
    bundle = archive.read("resource/reader/reader.js").decode()
start = bundle.index(";// ./epubjs/epub.js/src/epubcfi.js")
cfi = bundle[start:bundle.index("\n;// ", start + 4)]
start = bundle.index("async function sanitizeAndRender")
sanitize = bundle[start:bundle.index("class CSSRewriter", start)]
helpers = []
for name in ["isNumber", "findChildren", "extend", "type"]:
    start = bundle.index("function " + name + "(")
    helpers.append(bundle[start:bundle.index("\n}", start) + 2])
script = "\n".join(helpers) + "\n" + cfi + "\n" + sanitize
script = "const SANITIZER_REPLACE_TAGS = new Set(['html','head','body','base','meta']);\n" + script
# Fixture chapters have no MathML. Do not replace the production math renderer on real content.
script += "\nasync function renderMath(doc) { if(doc.querySelector('math')) throw Error('MathML is outside this oracle fixture'); }\nwindow.Oracle = { EpubCFI, sanitizeAndRender };"
root = Path(tempfile.mkdtemp(prefix="zotero-position-oracle-", dir="/tmp"))
(root / "oracle.js").write_text(script)
environment = {**os.environ, "KO_HOME": str(root), "SDL_VIDEODRIVER": "dummy", "ZOTERO_PLUGIN_ROOT": str(plugin)}
for fixture in ["sample.epub", "mixed.epub"]:
    environment["ZOTERO_ORACLE_FIXTURE"] = fixture
    (root / "incoming.json").unlink(missing_ok=True)
    for dom_version in [20171225, 20200223, 20240114, 20260812]:
        environment["ZOTERO_DOM_VERSION"] = str(dom_version)
        subprocess.run(["./luajit", str(plugin / "tools/position-oracle.lua")], cwd=emulator, env=environment, check=True)
        subprocess.run(["node", str(plugin / "tools/position-oracle.cjs"), str(root / "oracle.js"), str(root / "outgoing.json"), str(root / "incoming.json")], env=environment, check=True)
        subprocess.run(["./luajit", str(plugin / "tools/position-oracle.lua")], cwd=emulator, env=environment, check=True)
print("Oracle bundle SHA-256:", hashlib.sha256(bundle.encode()).hexdigest())
print("Evidence:", root)
