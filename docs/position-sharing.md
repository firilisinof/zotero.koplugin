# Reading-position FAQ

## How do I share my position with Zotero?

1. While connected, enable Zotero > Settings > Share reading position.
   This needs personal-library read/write permission for the key owner, even
   when reading a group attachment.
2. Open the PDF or EPUB through Zotero or Continue reading.
3. Choose Sync position now. Synchronize Zotero on the other device before
   opening the attachment there.

For the reverse direction, close and synchronize the desktop Zotero reader
before reopening the document in KOReader. An already-open desktop tab does not
move live.

## What position is shared?

PDFs share the physical page. Zoom and the view within the page stay local.
EPUBs share an exact supported content location, independent of font size.

Existing KOReader progress takes priority on the first exchange. Otherwise the
plugin imports Zotero's position. Later, pending local changes win conflicts;
when no local change is pending, remote changes can be imported.

## Why is sharing unavailable or pending?

Check the status shown by Sync position now. The local file must match Zotero's
attachment checksum. Changed files and linked files without a synced checksum
cannot share positions, but remain readable.

Some EPUB structures and locations cannot be converted, including MathML,
embedded objects, CDATA boundaries, unresolved named entities, ambiguous text
normalization and media offsets. Sections larger than 8 MiB or XML depth greater
than 256 are unsupported.

Offline changes survive restart and upload when a connection is available.
If write permission was revoked, correct it and disable/re-enable sharing to
check the key again. Another active reader can publish a later position.

## What happens if I turn sharing off?

Local progress and queued changes remain saved.
[Highlight sync](highlight-sync.md) has its own setting.
