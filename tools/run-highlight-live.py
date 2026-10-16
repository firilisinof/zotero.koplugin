"""Run manifest-scoped live ReaderUI handoffs with a persistent temporary profile."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--profile', type=Path, required=True)
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--credentials', type=Path, required=True)
parser.add_argument('--phase', choices=['push', 'pull'], required=True)
args = parser.parse_args()
plugin = Path(__file__).resolve().parents[1]
emulator = next((plugin.parent / 'koreader').glob('koreader-emulator-*/koreader'))
assert str(args.profile).startswith('/tmp/'), 'Use a dedicated temporary profile'
args.profile.mkdir(exist_ok=True)
environment = {**os.environ, 'KO_HOME': str(args.profile), 'SDL_VIDEODRIVER': 'dummy',
               'ZOTERO_PLUGIN_ROOT': str(plugin), 'ZOTERO_HIGHLIGHT_MANIFEST': str(args.manifest.resolve()),
               'ZOTERO_TEST_CREDENTIALS': str(args.credentials.resolve()), 'ZOTERO_HIGHLIGHT_PHASE': args.phase}
result = subprocess.run(['./luajit', str(plugin / 'tools/highlight-live.lua')], cwd=emulator, env=environment)
raise SystemExit(result.returncode)
