# Roadmap

The six cheap wins, opt-in PDF/EPUB reading-position sharing, and opt-in bidirectional highlight synchronization are implemented. Metadata browsing remains read-only. Position sharing writes native synced settings; highlight sync conditionally updates attachment annotations. See [position sharing](position-sharing.md) and [highlight sync](highlight-sync.md) for validation and limits.

## Implemented cheap wins

1. **Group libraries.** The account dialog selects a personal or group library and edits its ID and API key. `API.getLibraryPrefix()` supplies every library URL. Changing the active library resets metadata and sync timestamps. Original personal downloads retain their paths and sidecars. Other libraries use separate storage namespaces. Group files use Zotero storage, while saved personal WebDAV settings remain available when switching back.
2. **Download state.** Collection and search rows show a localized status beside separate title, author, year and format fields. “Downloaded” indicates a local file, “Not downloaded” indicates an absent file, and “Unavailable” identifies an absent linked file that Zotero cannot serve. File presence is checked while producing each row, so subprocess downloads and externally removed files are reflected without rebuilding the metadata index. Presence does not imply that the file matches the latest synced attachment version.
3. **Collection downloads.** Hold a collection row and choose “Download collection”. Only direct attachments matching the active tag filter are included. Current files are skipped. Each transfer runs in KOReader's dismissible subprocess helper, allowing progress updates and cancellation. A summary lists completed, current, failed and cancelled files, including each failure. One failure does not stop the remaining files.
4. **Zotero notes.** Hold an attachment row and choose “Show Zotero notes”. The viewer displays the parent publication's non-deleted child notes, with HTML tags removed and entities decoded. Notes stay local and read-only. Standalone notes and annotations are not separate browser rows.
5. **Tag filter.** Settings accepts one exact, case-sensitive tag, with a clear action to disable filtering. Parent tags take precedence over attachment tags. Standalone and orphaned attachments use their own tags. Collection navigation remains visible, and both browsing and search refresh immediately.
6. **Sync convenience.** The menu shows the last successful sync time. Startup sync and sync on browsing when the cache is older than 24 hours are separate opt-in settings. Automatic triggers require credentials and an existing network connection, never enable Wi-Fi, and do not overlap other operations. Startup is attempted once per KOReader process. There is no periodic retry timer.

## Download and cache compatibility

Local reading opens existing PDF and EPUB copies directly without credentials or network access, even when stale or missing a version marker. Explicit downloads retain their update behavior. “On device” lists only present attachments in the active library's filtered metadata cache and keeps searches local. Browser views, pages and back history persist separately for each personal or group library. Clearing credentials retains cache ownership and document paths.

Files still live under their original parent directory, preserving KOReader sidecars and history paths. Version markers are now per attachment, named `.zotero-<attachmentKey>.version`. An old parent-level `version` marker is trusted only when exactly one readable attachment belongs to that directory. Ambiguous old markers cause a fresh download.

Direct transfers and WebDAV extraction write staging files before replacing the attachment. Failed transfers or extraction retain the previous file. A cancelled worker may leave a staging file or archive, which the next attempt overwrites. Metadata resets never remove downloads or sidecars.

The API facade remains `zoteroapi.lua`, with settings, indexing, transport, downloading and sync in focused modules. The browser and settings dialogs are separate from plugin lifecycle code. The HTTP transport remains injectable as `API.http`.

## Verification

`make test` runs the offline API, browser, settings, sync and download regression suites against the local KOReader build. Real temporary files and zip fixtures cover storage and archive behavior. Named UI and task-runner fakes cover scheduling and cancellation deterministically.

`tools/smoke-ui.lua` exercises real emulator widgets and subprocess downloads using fixture data and a fresh temporary `KO_HOME`. It saves screenshots there and checks group selection, notes, filters, download progress, cancellation, cached browsing and sidecar preservation. See README for its invocation.

## Highlight sync

Implemented through the existing attachment identity, transport, operation lock,
background worker and durable store. Full EPUB ranges reuse the exact endpoint
resolver; PDF conversion handles page coordinate transforms. Stable IDs, offline
snapshots, conditional writes, tombstones and reviewed conflicts protect both
sides. See [highlight sync](highlight-sync.md) for supported formats, preservation
contracts, automated tests and controlled live handoffs.
