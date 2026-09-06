# Roadmap

The six cheap wins are implemented. The plugin remains read-only and needs no new Zotero write permissions. Highlight sync is documented below and is not being attempted.

## Implemented cheap wins

1. **Group libraries.** The account dialog selects a personal or group library and edits its ID and API key. `API.getLibraryPrefix()` supplies every library URL. Changing the active library resets metadata and sync timestamps. Original personal downloads retain their paths and sidecars. Other libraries use separate storage namespaces. Group files use Zotero storage, while saved personal WebDAV settings remain available when switching back.
2. **Download state.** Collection and search rows show `[Downloaded]` when their local file exists. File presence is checked while producing each row, so subprocess downloads and externally removed files are reflected without rebuilding the metadata index. Presence does not imply that the file matches the latest synced attachment version.
3. **Collection downloads.** Hold a collection row and choose “Download collection”. Only direct attachments matching the active tag filter are included. Current files are skipped. Each transfer runs in KOReader's dismissible subprocess helper, allowing progress updates and cancellation. A summary lists completed, current, failed and cancelled files, including each failure. One failure does not stop the remaining files.
4. **Zotero notes.** Hold an attachment row and choose “Show Zotero notes”. The viewer displays the parent publication's non-deleted child notes, with HTML tags removed and entities decoded. Notes stay local and read-only. Standalone notes and annotations are not separate browser rows.
5. **Tag filter.** Settings accepts one exact, case-sensitive tag, with a clear action to disable filtering. Parent tags take precedence over attachment tags. Standalone and orphaned attachments use their own tags. Collection navigation remains visible, and both browsing and search refresh immediately.
6. **Sync convenience.** The menu shows the last successful sync time. Startup sync and sync on browsing when the cache is older than 24 hours are separate opt-in settings. Automatic triggers require credentials and an existing network connection, never enable Wi-Fi, and do not overlap other operations. Startup is attempted once per KOReader process. There is no periodic retry timer.

## Download and cache compatibility

Files still live under their original parent directory, preserving KOReader sidecars and history paths. Version markers are now per attachment, named `.zotero-<attachmentKey>.version`. An old parent-level `version` marker is trusted only when exactly one readable attachment belongs to that directory. Ambiguous old markers cause a fresh download.

Direct transfers and WebDAV extraction write staging files before replacing the attachment. Failed transfers or extraction retain the previous file. A cancelled worker may leave a staging file or archive, which the next attempt overwrites. Metadata resets never remove downloads or sidecars.

The API facade remains `zoteroapi.lua`, with settings, indexing, transport, downloading and sync in focused modules. The browser and settings dialogs are separate from plugin lifecycle code. The HTTP transport remains injectable as `API.http`.

## Verification

`make test` runs the offline API, browser, settings, sync and download regression suites against the local KOReader build. Real temporary files and zip fixtures cover storage and archive behavior. Named UI and task-runner fakes cover scheduling and cancellation deterministically.

`tools/smoke-ui.lua` exercises real emulator widgets and subprocess downloads using fixture data and a fresh temporary `KO_HOME`. It saves screenshots there and checks group selection, notes, filters, download progress, cancellation, cached browsing and sidecar preservation. See README for its invocation.

## Highlight sync: documented, not attempted

This is the obvious next ambition and it is deliberately out of scope. The notes
below exist so the decision does not have to be re-derived.

### It is possible

Zotero annotations are ordinary writable items. The template endpoint confirms
the shape:

```
GET https://api.zotero.org/items/new?itemType=annotation&annotationType=highlight

{"itemType":"annotation","parentItem":"","annotationText":"","annotationComment":"",
 "annotationColor":"","annotationPageLabel":"","annotationSortIndex":"00000|000000|00000",
 "annotationPosition":{"pageIndex":0,"rects":[]},"tags":[]}
```

`parentItem` is the **attachment** key, which is exactly the key the browser
already passes to `downloadAndGetPath`. Annotations travel over the Zotero API
even when files travel over WebDAV, so a WebDAV user gets annotation sync too.

On the KOReader side, highlights live in the document's `DocSettings` sidecar
under `annotations`. The entry shape is built in
`frontend/apps/reader/modules/readerannotation.lua:66` and carries `text`,
`note`, `color`, `drawer`, `page`, `pos0`, `pos1`, `datetime`, `chapter` and
`pageno`.

### What makes it expensive for PDF

1. **Coordinates.** KOReader stores `pos0`/`pos1` as `{x, y, page}` in page
   space with a top-left origin, plus `pboxes` for the drawn rectangles. Zotero
   wants `rects` in PDF points with a bottom-left origin. The transform has to
   account for the y flip, the cropbox offset and page rotation. Get it slightly
   wrong and highlights land a few millimetres off in the Zotero reader, which
   is the kind of bug that is easy to ship and tedious to find.
2. **Idempotency.** Pushing twice creates duplicates. This needs a durable map
   from a KOReader annotation to the Zotero key it produced. The annotation
   `datetime` is stable and is the natural local id. The map belongs in
   something like `zotero/annotations/<attachmentKey>.json` rather than the
   sidecar, because sidecars get wiped and Zotero keys are library state.
3. **Write permission.** The configured API key is very likely read-only.
   `GET /keys/current` reports the key's permissions, and the account dialog
   should check it, because a 403 in the middle of a sync is a bad way to find
   out.
4. **Colors.** KOReader has nine named highlight colors
   (`frontend/apps/reader/modules/readerhighlight.lua:29`) and Zotero has eight
   fixed hex values. A static name to hex table with a yellow fallback covers
   it.

Batch writes accept up to 50 objects per POST and return `successful`, `failed`
and `unchanged` maps, so partial failure is reportable rather than fatal.

Pulling annotations the other way, from the Zotero desktop reader into the
sidecar, is the same coordinate work in reverse plus a conflict rule. It should
wait until one-way push works.

### What makes it hard for EPUB

Zotero addresses EPUB annotations with EPUB CFI. KOReader addresses EPUB
positions with crengine XPointers into a single flattened document, of the form
`/body/DocFragment[3]/body/div/p[5]/text().12`. There is no cheap conversion.
It means mapping a `DocFragment` index back to its spine item and a node path to
CFI steps, through crengine's own DOM normalization, and being exact, since a
near miss puts the highlight in the wrong paragraph.

The pragmatic alternative, if EPUB highlights are ever wanted, is to push them
as a child **note** item instead of annotations. One HTML note per book holding
the quotes, comments and chapter titles. It appears in Zotero, it is searchable,
it cannot desync, and it costs a fraction of the effort. It does not produce
highlights in Zotero's reader.

### The ceiling

For PDFs, "highlight on the device, see it in Zotero after a sync" is reachable.
For EPUBs, quotes in Zotero are reachable and real highlights are a separate
project.
