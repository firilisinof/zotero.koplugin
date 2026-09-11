# Highlight synchronization

Enable **Zotero → Settings → Sync highlights** while connected, then open a PDF
or EPUB through the plugin. This is independent of reading-position sharing and
is off by default. Enabling verifies read/write permission for the actual personal
or group library. Automatic exchanges use an existing connection; they never
turn on Wi-Fi. **Sync highlights now** starts an explicit handoff.

Sync the other Zotero client before switching readers. Local changes are saved
immediately on annotation events and on save/close/suspend. Network exchanges
are coalesced, use the existing operation lock and cancellable child worker, and
resume on reopening, reconnecting or a manual trigger. Closed-document uploads
can drain from the queue; imports for closed documents wait in a durable journal
until that document is reopened. Disabling retains annotations and queued state.

## Reconciliation and preservation

- A plugin-owned `zotero_highlight_id` distinguishes annotations even when their
  creation timestamps collide. A Zotero key is generated and saved before the
  first POST. Lost responses and repeated syncs reuse that key.
- `zotero/highlights.json` stores account/library/attachment identity, checksum,
  native snapshots, last-shared values, tombstones, conflicts and pending imports.
  It reuses the position store's flushed atomic writes. No credentials are stored
  in this journal.
- Each exchange checks the attachment checksum and format and reads a complete,
  version-consistent child listing. Missing mapped keys are checked individually.
  Failed pagination, moved items and unsupported annotation types never imply
  deletion. Annotation reads do not advance the metadata-sync cursor.
- An exact preexisting remote match can be adopted without another POST. Duplicate
  local copies and ambiguous remote matches are retained and reported for cleanup.
  Identical desktop-only copies wait for cleanup before import; an extra desktop
  copy of an already mapped highlight stays in Zotero without another local copy.
  The plugin does not delete extra copies to resolve ambiguity.
- The last shared value is the merge baseline. Separate fields can merge, such as
  a KOReader comment and a Zotero color. Competing edits to one field, or an edit
  on one side and deletion on the other, remain unresolved. Use **Resolve highlight
  conflicts** to review both versions and choose one. A new change invalidates a
  previously reviewed choice.
- Updates use version-conditional PATCH requests. Deletion of a mapped local
  highlight moves its Zotero counterpart to Trash. Remote trash/permanent deletion
  removes only the corresponding local highlight. Tombstones prevent accidental
  resurrection; an explicit restore is reconciled as a new change.
- The import journal is written before the sidecar changes. Its native snapshots
  reject stale results and allow replay after interruption. Imports modify only
  mapped annotation fields, preserve bookmarks and other annotation types, and
  refresh native highlight caches. Font, zoom, reading-position settings, document
  paths and original PDF/EPUB bytes are preserved.
- Zotero tags, author metadata and unrelated item fields are not replaced by the
  plugin. Unchanged position extensions are preserved. Requests that fail remain
  pending; rate-limit/backoff headers delay retries, and authentication failures
  pause requests until sharing is disabled and re-enabled.

The protocol uses Zotero's documented [conditional item writes and predetermined
keys](https://www.zotero.org/support/dev/web_api/v3/write_requests), with the same
HTTP injection seam as existing plugin features. No desktop extension, companion
service or extra device runtime is required.

## Format boundaries

EPUB highlights reuse `zoteroepub` endpoint resolution and add full CFI range
serialization. The resolver verifies both endpoints against crengine's loaded
DOM, maps Unicode offsets to UTF-16, and counts section text for Zotero sort
indexes. Supported ranges may cross inline elements and paragraphs within one
spine entry. The existing resolver's MathML/object, CDATA, entity and ambiguous
normalization limitations still apply. Cross-spine and collapsed ranges remain
pending with an explanation, without approximate placement.

PDF rectangles convert between PDF user space and native MuPDF coordinates,
including crop offsets, rotation, inherited page properties and `UserUnit`.
KOReader builds can hide MuPDF's direct transform symbol. The plugin therefore
uses its existing protected API to serialize a known quadrilateral in an isolated
scratch document, reads the resulting PDF-space points, and caches that transform
under the attachment checksum. The reader document is never saved into the PDF.
The parent cleans the scratch file even when the worker is cancelled.

A document-instance hook draws the exact imported rectangles in ordinary PDF
view, avoiding KOReader's word/OCR snapping. Resizing an annotation invalidates
its saved geometry and restores native selection behavior. Reflow view continues
to use KOReader's native word-based rendering. One page and two consecutive pages
are supported; longer native ranges are reported as unsupported. PDF sort indexes
use page and vertical position, without Zotero's full per-character offset index.

Highlight and underline text markup are supported. KOReader invert maps to a
Zotero highlight; olive maps to green. Other unknown local colors use yellow.
Unsupported remote colors, embedded read-only annotations, drawings, area
annotations and formatted native comments are preserved rather than rewritten.

## Validation on 2026-09-11

- `make test`: 322 tests in 16 suites, including 68 new highlight tests.
  Coverage includes creation/import, full ranges, duplicate adoption/ambiguity,
  equal timestamps, offline restart, closed imports, stale responses, lost write
  responses, field merges, reviewed conflicts, both deletion directions, 412s,
  backoff, revoked/group permissions, moved items, checksum changes and preservation.
- The PDF fixture `geometry.pdf` independently pins all four rotations, nonzero
  crop/media origins, inherited properties and a `UserUnit` of 2. Real MuPDF
  conversion matches those expected matrices and round-trips rectangles, including
  persisted two-page ranges.
- `tools/check-position-oracle.py` executes real crengine and CFI/sanitizer code
  from installed Zotero 10.0.1: two EPUB structures × four DOM versions, seven
  exact points and three full ranges per combination. Full-range passage comparison
  ignores whitespace separators that crengine inserts between paragraphs; endpoint
  comparisons remain exact. Both directions pass.
- Dedicated `sample.pdf` and `sample.epub` attachments were created for live tests.
  Real ReaderUI and the plugin's HTTP worker uploaded `Position fixture` and
  `Alpha 😀 beta`. Zotero's reader displayed the correct ranges. New `page 1` and
  `nested words` highlights were created in the Zotero readers and imported back
  into KOReader with their desktop comments. Reopening/repeating the handoff kept
  two highlights per document, preserved sentinel settings, and retained the exact
  source checksums. Screenshots confirmed complete PDF and EPUB ranges.
- The live test attachments, annotations and their test position settings were
  removed after verification. No existing user annotations were edited.

The tested environment is the desktop KOReader emulator
`v2026.07.2-130-g92bf75f03` and Zotero 10.0.1. Kindle installation, performance,
physical suspend/resume and different KOReader builds have not been tested.

## Reproduce controlled handoffs

All live tools require a manifest containing freshly created, original fixture
attachments. Keep the profile in `/tmp`; never point it at a normal reader profile.
Credentials are read from the specified existing settings file and are not printed.

1. Run `tools/check-position-live.py --purpose highlights --phase create
   --credentials <settings-file> --manifest <new-manifest>`.
2. Run `tools/run-highlight-live.py --phase push --profile <temporary-profile>
   --credentials <settings-file> --manifest <manifest>`.
3. Sync Zotero. If the desktop uses WebDAV, locate the identical fixture files in
   the temporary profile when prompted. Inspect the highlighted ranges and create
   a second highlight with a comment containing `Desktop` in each reader.
4. Sync Zotero, then run the same ReaderUI tool with `--phase pull`. It checks
   native ranges, checksums, duplicates and saved settings, and writes screenshots
   plus credential-free JSON evidence under the temporary profile.
5. Close the two test reader tabs. Run the fixture tool with `--purpose highlights
   --phase cleanup` and the same credentials/manifest. Cleanup validates the
   dedicated title, recorded key, account and checksum before removing anything.
