# Reading-position sharing

This opt-in plugin feature exchanges physical PDF pages and exact supported EPUB content locations through Zotero's own synced settings. It requires no desktop extension or new runtime installation. It does not synchronize annotations.

## Components

| Module | Responsibility |
| --- | --- |
| `zoteroprogress` | Enrollment, debounce, lifecycle, reconciliation and bounded conflict retry |
| `zoteroprogressidentity` | Key owner, active library, attachment key, exact path and full MD5 verification, reused while size, mtime, ctime and inode are unchanged |
| `zoteroprogressstore` | Atomic, flushed JSON outbox with generations and remote acknowledgments |
| `zoteroprogressremote` | Key permissions, attachment verification and conditional setting requests |
| `zoteroprogressworker` | Non-modal subprocess; only the parent writes progress state |
| `zoteroprogresscodec` | Native reader capture/navigation and format selection |
| `zoteroepub`, `zoterocfi`, `zoterounicode`, `zoteroxml` | Source-content resolution, Zotero DOM preparation, CFI, text offsets and XML adapter |

All production network writes are per-setting PUT requests with `If-Unmodified-Since-Version`. The owner is obtained from `/keys/current`. Settings live under `/users/<owner>/settings`, named `lastPageIndex_u_<attachment>` for personal documents and `lastPageIndex_g<groupID>_<attachment>` for group documents. Setting versions never replace the metadata-sync cursor.

The outbox is `zotero/reading-progress.json`, outside document sidecars. Each record identifies the account, library, attachment, exact path and content hash, along with native/encoded points, generation, pending status and acknowledged value/version. A reply can acknowledge only its generation. A 412 returns to the parent for the latest checkpoint, then makes one bounded retry. Authentication failures pause automatic requests until permissions are rechecked. Server Backoff also stops follow-up requests after a successful response.

The initial local-progress check runs before ReaderUI initializes its sidecar. Saved KOReader progress wins enrollment; otherwise a remote point is imported. Once enrolled, pending KOReader progress wins an observed conflict. Clean records import remote changes. Applying a remote point suppresses local change detection, and semantically equivalent EPUB CFIs are canonicalized. An independently active Zotero reader can still publish a later position.

## EPUB support boundary

Point APIs are `EPUB.new(document, dom_version)`, `encode(xpointer)` and `decode(cfi)`. Both conversions validate the mapping against the loaded document and return `nil, reason` for unsupported locations. The intermediate source location is a spine entry, source XML node and character boundary. Range endpoints use these same point conversions; range serialization and annotation reconciliation are outside this release.

The package manifest and spine are read through crengine's document-file API. The resolver uses crengine's native legacy-XPointer normalization, accounts for DOM-version-dependent DocFragment numbering, removes/renames nodes relevant to Zotero's DOM preparation, and converts Unicode code-point offsets to UTF-16. Source sections are cached within the document/DOM-version-specific resolver (maximum two sections); reopening creates a fresh resolver after full fingerprint verification. Whitespace mappings accept only exact text or deterministic ASCII whitespace collapse/trim.

Unsupported cases fail explicitly: non-XHTML target spine entries, MathML/object DOM transformations, CDATA text boundaries, unresolved named entities, ID assertions that do not match the source, invalid UTF-16 boundaries, ambiguous normalization, CFI ranges and media offsets. Sections are limited to 8 MiB and XML depth 256. These are support limits, not percentage-based approximations. The resolver accepts both full `epubcfi(...)` notation and the bare paths saved by Zotero 10.0.1. The settings codec publishes Zotero's bare form.

SLAXML is vendored as `zoteroslaxml.lua`, pinned to commit `756ffad03d2a06271170a0ba82d6eac02cc2a5ca`, behind the project-owned XML adapter. Its MIT notice ships as `LICENSE-SLAXML`. [Upstream source](https://github.com/Phrogz/SLAXML/tree/756ffad03d2a06271170a0ba82d6eac02cc2a5ca).

Interoperability references: [Zotero KOReader importer](https://github.com/zotero/reader/blob/master/src/dom/epub/lib/koreader.ts), [Zotero DOM preparation](https://github.com/zotero/reader/blob/master/src/dom/epub/lib/sanitize-and-render.ts), [CFI character offsets](https://w3c.github.io/epub-specs/epub33/epubcfi/#sec-path-character-offset), and [Zotero settings controller](https://github.com/zotero/dataserver/blob/master/controllers/SettingsController.php). Runtime compatibility is checked against the installed 10.0.1 bundle rather than assuming current upstream master is identical.

## Validation workflow

1. `make test` runs the offline regression suites in the existing built emulator. It does not rebuild native dependencies. `make build` remains the explicit native-build command.
2. `python3 tools/check-position-oracle.py` extracts only the necessary CFI/sanitizer functions from installed Zotero 10.0.1 into `/tmp`, then compares actual DOM nodes, character boundaries and highlight endpoint pairs with real crengine. Set `PLAYWRIGHT_MODULE` to an installed Playwright module if needed; `CHROME_PATH`, `ZOTERO_APP` and `KOREADER_SRC` override defaults. It tests ordinary/mixed-media EPUBs across four native DOM versions. No Zotero application code is shipped in the plugin.
3. From the built emulator's `koreader` directory, run the following against a fresh temporary profile:

   ```sh
   KO_HOME="$(mktemp -d /tmp/zotero-smoke.XXXXXX)" SDL_VIDEODRIVER=dummy ./luajit /absolute/path/to/zotero.koplugin/tools/smoke-progress.lua
   ```

   This uses actual ReaderUI and subprocesses with a named fixture server. It verifies PDF push/pull, offline close/reopen, reconnect, EPUB pull/reload, unchanged file bytes, sidecar settings and an existing highlight. `tools/smoke-ui.lua` separately checks the existing browser/download/navigation flows. To run the position smoke against an extracted ZIP, set `ZOTERO_PLUGIN_ROOT` to that extracted plugin directory; test fixtures still come from the source checkout.
4. Live validation is explicit and separate. `tools/check-position-live.py --phase create --credentials <emulator-meta.lua> --manifest /tmp/<unique-manifest>.json` creates only two original test attachments, uploads them with the documented Zotero file flow, and records their keys without credentials. Never use real reading attachments as fixtures. From the emulator, run `tools/position-live.lua` with temporary `KO_HOME`, `ZOTERO_PLUGIN_ROOT`, `ZOTERO_POSITION_MANIFEST`, and `ZOTERO_TEST_CREDENTIALS`. It reads the existing key without printing or persisting it and writes only fixture positions. Synchronize Zotero, open the fixtures, change their positions, close and sync; repeat with `ZOTERO_POSITION_READ_ONLY=1`. Finally run the Python helper with `--phase cleanup` and the same manifest/credentials to remove those exact fixtures and settings. A WebDAV-configured desktop may need the original fixture files placed in its dedicated test attachment directories before opening; this is not a production storage-setting change.

## Recorded checks and deployment limit

The final gates passed: **254 tests in 14 offline suites**, **40 existing browser/navigation smoke screens**, and **8 position lifecycle stages using the extracted ZIP**, including immediate cancellation of an in-flight request on suspend. The independent oracle checked seven point cases and one highlight endpoint pair for two EPUB structures across four DOM versions (56 point cases with reverse-conversion checks and eight range comparisons). These are fixture-based results, not a claim that every EPUB structure is supported.

The packaged ZIP contains 32 runtime/license files (62,987 bytes). Its SHA-256 is `2991e66910fce4c05acec8c32cd00b816ad7f9b70ddfdc5288ea8d3876fa3ed7`. Archive entries were compared byte-for-byte with the source files and checked to exclude the configured API key.

On 2026-09-11, real crengine and installed Zotero 10.0.1 independently agreed on the tested EPUB passages in both directions, including endpoint pairs. The tested native DOM versions were 20171225, 20200223, 20240114 and 20260812. The extracted reader bundle's SHA-256 was `efcae743e5de2f8a1d47587a76dc2c5a863cf3765f242585f3f187c6b6b6ddf5`.

The controlled live test published PDF physical page 3 and an EPUB location in the second chapter using the plugin's real Lua HTTP transport. After sync, Zotero opened those pages/passages. Zotero then saved PDF page 1 and EPUB `/6/2!/4/2/1:0`; the plugin read these back, and real crengine resolved the latter to `Alpha 😀 beta & gamma.`. The two fixture attachments and their settings were removed afterward. No existing user positions were changed by the test code.

The emulator build was KOReader `v2026.07.2-130-g92bf75f03`. The target is a jailbroken Kindle 10th generation, currently unavailable for connection. Its KOReader version, runtime performance, suspend behavior and packaged installation have **not** been verified on hardware.

## Kindle handoff

1. Close KOReader, extract `dist/zotero.koplugin.zip`, and replace only `<KOReader>/plugins/zotero.koplugin`. Preserve `<KOReader>/zotero`, document paths and all sidecars. No additional runtime dependency is required.
2. Restart, synchronize library metadata, connect using your usual Wi-Fi controls, and enable Zotero → Settings → Share reading position.
3. Start with disposable PDF and EPUB copies whose attachment checksums match. Open through Zotero/Continue reading, navigate, then choose Sync position now and check the status.
4. Sync Zotero on the Mac and open the same attachment. Test the reverse handoff with a new Zotero position, closing/syncing before reopening on Kindle.
5. Verify offline reading across KOReader restart and Kindle suspend/resume, then reconnect and sync. Confirm that browser return, highlights and font/zoom settings remain intact.

If a location is unavailable, keep reading locally and use the reported reason. A content replacement after enrollment pauses that attachment instead of applying an old position to new contents. Disabling sharing retains the outbox. Hardware readiness should be claimed only after these checks pass on the target device.
