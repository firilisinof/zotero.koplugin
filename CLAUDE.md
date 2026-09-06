# zotero.koplugin

A KOReader plugin that browses a Zotero library and opens its PDF and EPUB attachments.
Fork of [stelzch/zotero.koplugin](https://github.com/stelzch/zotero.koplugin).

## Layout

| Path | What it is |
| --- | --- |
| `main.lua` | KOReader plugin lifecycle, dispatcher actions and sync scheduling |
| `zoteroapi.lua` | Public API facade and local cache I/O |
| `zotero{settings,index,transport,download,sync}.lua` | Focused API behavior modules, injected with the facade |
| `zotero{browser,row,dialogs,menu,ui}.lua` | Browser, metadata rows, configuration dialogs, menu and KOReader UI boundary |
| `zotero{util,archive,types}.lua` | Filesystem/archive boundaries and shared Lua annotations |
| `_meta.lua` | Plugin manifest read by KOReader's plugin loader |
| `spec/` | busted specs, run inside a real KOReader build |
| `tools/` | Development scripts, not shipped to the device |
| `docs/roadmap.md` | What to build next, and why highlight sync is not being attempted |

## Development loop

The plugin is developed against a KOReader source checkout built for the desktop
emulator, so changes can be run and tested on the Mac without touching the Kindle.

```
make setup   # one time: brew deps, clone KOReader, build it, create the symlinks
make test    # run the specs
make run     # open the emulator with the plugin loaded
make link    # re-create the symlinks (make run and make test do this for you)
make build   # rebuild the emulator, only needed after pulling KOReader
```

`KOREADER_SRC` defaults to `../koreader` and can point anywhere:

```
make test KOREADER_SRC=~/src/koreader
```

### Why edits are live

`make setup` creates symlinks in the KOReader checkout:

- `$KOREADER_SRC/plugins/zotero.koplugin` to this repository
- one entry under `$KOREADER_SRC/spec/unit/` per `spec/*_spec.lua`

KOReader's own build then symlinks its whole `plugins/` and `spec/` trees into the
emulator output (`Makefile`, the `all:` target). Nothing is copied anywhere, so
**editing a `.lua` file here takes effect on the next `make run` or `make test`
with no rebuild**. Only `make setup` and `make build` compile anything.

The plugin's sources never live in the KOReader checkout. Only the symlinks do.

### GNU tools on PATH

KOReader's build needs Homebrew's GNU findutils, make, getopt and util-linux rather
than the BSD versions macOS ships. `tools/gnu-path.sh` is the single source of truth
for that PATH prefix, and both the `Makefile` and `tools/setup-dev.sh` use it, so no
shell setup is needed.

Do not add `binutils` to that list. Its GNU `ar` writes archives Apple's linker
rejects with "invalid control bits", which breaks the freetype2 link against brotli
partway through the build.

### Credentials in the emulator

The emulator's data directory is the build directory, so your real API key ends up in
`$KOREADER_SRC/koreader-emulator-*/koreader/zotero/meta.lua`. That is outside this
repository and cannot be committed by accident. The specs never read it.

## Specs

`spec/*_spec.lua` covers the API, widget guards, group accounts, indexing, downloads, settings and scheduling. All specs run entirely offline. `zoteroapi.lua` exposes its HTTP transport as `API.http`, and each test swaps in a `spec/support/fake_http.lua` instance serving the canned responses in `spec/fixtures/`:

```lua
fake:on("GET", "/items%?.*start=0$", {
    headers = { ["total-results"] = "150", ["last-modified-version"] = "1214" },
    body = Fixtures.raw("items_page1.json"),
})
ZoteroAPI.http = fake
```

Pagination reads `total-results` off each page, so a stubbed GET needs that header
or the fetch reports that it could not size the collection.

`API.http` is the network injection seam. Browser tests also inject named UI and task-runner fakes. File I/O and archive unpacking stay real, because each test gets its own temporary Zotero directory under `KO_HOME`, which the test runner wipes before every session.

`API` is a singleton module, so every test calls `package.reload("zoteroapi")` in
`before_each` to be sure nothing carries over through module-level state.

The fixtures are hand-written to match Zotero Web API v3 response shapes. To check
them against a real library, run `tools/fetch-fixtures.sh` with `ZOTERO_USER_ID` and
`ZOTERO_API_KEY` set. It writes to `spec/fixtures/live/`, which is gitignored, so you
can diff before adopting anything.

### Conventions

- Spec files must end in `_spec.lua` or busted will not collect them. The Makefile
  links and runs every `spec/*_spec.lua`, so a new one needs no wiring.
- They are symlinked into KOReader's shared `spec/unit/`, so names have to be unique
  against KOReader's own specs. Prefix new ones with `zotero`.
- Assert on behaviour through the public `API.*` functions rather than on internals.

The WebDAV download specs unpack real zip fixtures (`spec/fixtures/attachment.zip`
and `attachment_misnamed.zip`) through libarchive, so they cover the unpack step
rather than stubbing it.

## The item index

`displayCollection` and `displaySearchResults` read from `API.getIndex()`, built
lazily by walking the library once. It holds two lookups:

- `by_collection[collectionKey]` list of readable attachments, sorted by display name
- `searchable` the same attachments with a pre-lowercased haystack, sorted

**If you add anything that mutates the library, drop the index.** `API.index = nil`
is done in `API.init`, `API.setItems` and `API.setCollections`. Mutating the table
returned by `API.getItems()` in place without going through `setItems` leaves the
index stale.

`displayCollection` and `displaySearchResults` return copies because the browser inserts its own rows and adds presentation fields. The `downloaded` flag is computed from file presence while copying, so it stays fresh independently of the cached index. Changing `filter_tag` also drops the index.

Attachment rows also carry `title`, `author`, `year`, `file_format` and `downloadable` for the native metadata layout in `zoterorow.lua`. The legacy `text` remains the sorting and search source. The browser treats items per page as a maximum and reduces capacity to fit two title lines plus secondary metadata at the active font size.

## Behaviour worth knowing

- An attachment whose `parentItem` is not in the library is hidden from collection
  browsing but still findable by search under its own title. This is odd, and specs
  pin it, so change it deliberately rather than by accident.
- `linked_file` attachments open when a copy already exists at the resolved local path. Zotero does not serve linked files, so `downloadAndGetPath` still returns an explanatory error for them.
- `API.downloadWebDAV` unpacks through KOReader's `ffi/archiver` (libarchive) rather
  than shelling out. It extracts the archive's first file entry to the filename
  Zotero recorded, so an entry spelled differently still lands where the UI looks.
- `API.setItems` and `API.setCollections` atomically replace their JSON files and raise on write failure. Failed HTTP sync stages do not mutate the currently indexed item tables.
- If you ever shell out again, note that under LuaJIT `os.execute` returns the exit
  status as a **number** (0 on success, 256 on failure), not a boolean, and that a
  command which prompts will hang the reader. This is what `unzip` used to do.
- Lua patterns are unanchored. Wrapping a search pattern in `.*` matches the same
  strings but makes the matcher retry from every position, which cost about twenty
  times as much on a large library.

## Library and download behavior

- Missing `library_type` means a personal library. `user_id` remains compatible, and groups use `group_id`. Every Zotero URL uses `API.getLibraryPrefix()`.
- `cache_library` identifies the metadata cache owner. `legacy_storage_library` preserves the original personal library's unnamespaced storage paths. Other libraries use `storage/users/<id>` or `storage/groups/<id>`.
- Account changes reset metadata and last-sync time, preserving downloaded documents and sidecars. WebDAV preferences remain saved but are inactive for groups.
- Removing credentials retains the recorded cache owner and storage namespace. `getLocalAttachmentPath` checks real file presence without credentials, HTTP, version checks or writes.
- Selecting a present PDF or EPUB opens it directly, including stale and linked copies. Explicit collection downloads still update stale attachments. “On device” lists present attachments from the active filtered index, with search scoped to local copies.
- Zotero home offers Continue reading, Collections, All items, On device and Search. `zoteroheader.lua` uses native TitleBar and ButtonTable widgets for persistent Home, Back and Search controls. Collection names and search queries appear in the title.
- `zoteroreader.lua` binds return behavior to a successfully opened ReaderUI instance through its after-open callback. Native Home, file-browser menu and end-of-book file-browser actions save/close the reader before restoring the captured library view on the fresh file-manager plugin. Document reloads retain the binding. Ordinary opens, document switches and quit are unaffected.
- `continue_reading` records the last successful plugin-opened document per library. The home entry rechecks the cached attachment and exact local path before opening. KOReader owns all reading progress and sidecars.
- `zoteroposition.lua` stores browser views, pages and back history in `browser_positions`, keyed by library prefix. Browser reopening reloads the latest snapshot because the file manager and reader have separate plugin instances. Empty caches after switching libraries defer destination validation until metadata returns.
- Versions belong to individual attachments in `.zotero-<key>.version`. A legacy parent-level marker is accepted only for a single readable attachment. Transfers and archive extraction are staged before replacing the document.
- Collection downloads use one dismissible subprocess per stale attachment. The subprocess may write files but never changes UI or settings. The parent reports progress and failures and refreshes file-presence indicators.
- `last_sync` is recorded only after full sync success. `sync_on_startup` and `sync_on_open` default to false. Automatic sync needs an existing connection and never prompts to enable Wi-Fi. Browser-open sync uses a fixed 24-hour threshold.
- `tools/smoke-ui.lua` runs real widgets and downloads against fixtures in a temporary profile. It saves screenshots and checks cancellation and sidecar preservation. It must use a fresh temporary `KO_HOME`.

## Not set up yet

No CI, no linting, no deploy script. Tests are local only for now.

## Code style

- Functions: 4-20 lines. Split if longer.
- Files: under 500 lines. Split by responsibility.
- One thing per function, one responsibility per module (SRP).
- Names: specific and unique. Avoid `data`, `handler`, `Manager`.
  Prefer names that return <5 grep hits in the codebase.
- Types: explicit. No `any`, no `Dict`, no untyped functions.
- No code duplication. Extract shared logic into a function/module.
- Early returns over nested ifs. Max 2 levels of indentation.
- Exception messages must include the offending value and expected shape.

## Comments

- Keep your own comments. Don't strip them on refactor — they carry
  intent and provenance.
- Write WHY, not WHAT. Skip `// increment counter` above `i++`.
- Docstrings on public functions: intent + one usage example.
- Reference issue numbers / commit SHAs when a line exists because
  of a specific bug or upstream constraint.

## Tests

- Tests run with a single command: `<project-specific>`.
- Every new function gets a test. Bug fixes get a regression test.
- Mock external I/O (API, DB, filesystem) with named fake classes,
  not inline stubs.
- Tests must be F.I.R.S.T: fast, independent, repeatable,
  self-validating, timely.

## Dependencies

- Inject dependencies through constructor/parameter, not global/import.
- Wrap third-party libs behind a thin interface owned by this project.

## Structure

- Follow the framework's convention (Rails, Django, Next.js, etc.).
- Prefer small focused modules over god files.
- Predictable paths: controller/model/view, src/lib/test, etc.

## Formatting

- Use the language default formatter (`cargo fmt`, `gofmt`, `prettier`,
  `black`, `rubocop -A`). Don't discuss style beyond that.

## Logging

- Structured JSON when logging for debugging / observability.
- Plain text only for user-facing CLI output.
