# Highlight sync FAQ

## How do I exchange highlights?

1. Enable Zotero > Settings > Sync highlights while connected.
2. Open a PDF or EPUB through the plugin and choose Sync highlights now.
3. Synchronize the other Zotero client before switching readers.

Highlight sync is off by default and independent of
[position sharing](position-sharing.md).

## Which annotations are supported?

Text highlights and underlines in PDF and EPUB files. KOReader invert becomes
a Zotero highlight, and olive becomes green. Unknown local colors become yellow.
Drawings, area annotations, embedded read-only annotations, unsupported remote
colors and formatted native comments are preserved without conversion.

PDF ranges can cover one page or two consecutive pages. EPUB ranges must stay
within one spine section and have exactly convertible endpoints. Collapsed ranges
are unsupported. See also [EPUB limits](position-sharing.md#why-is-sharing-unavailable-or-pending).
Unsupported ranges remain pending with an explanation.
The local attachment must match Zotero's checksum.

## What happens if both readers change a highlight?

Changes to different fields can merge, such as a comment on one reader and a
color on the other. Conflicting edits, including an edit versus a deletion,
wait for Resolve highlight conflicts. Review both versions and choose one.
Duplicate or ambiguous matches are kept for manual cleanup.

## Are deletions synchronized?

Yes. Deleting a mapped KOReader highlight moves its Zotero counterpart to Trash.
Deleting or trashing it in Zotero removes the corresponding local highlight.

## What happens offline or when sync is disabled?

Offline changes stay queued. Uploads can resume while a document is closed;
imports wait until it reopens. Disabling sync keeps annotations and queued state.
After fixing revoked permissions, disable/re-enable sync to check access again.
