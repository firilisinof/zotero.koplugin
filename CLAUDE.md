# zotero.koplugin

A KOReader plugin that browses a Zotero library and opens its PDF and EPUB attachments.
Fork of [stelzch/zotero.koplugin](https://github.com/stelzch/zotero.koplugin).

## Layout

| Path | What it is |
| --- | --- |
| `main.lua` | The KOReader widget: menu entries, the browser, the settings dialogs |
| `zoteroapi.lua` | All the logic: sync, local cache, search, attachment download, WebDAV |
| `_meta.lua` | Plugin manifest read by KOReader's plugin loader |
| `spec/` | busted specs, run inside a real KOReader build |
| `tools/` | Development scripts, not shipped to the device |

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

`spec/zoteroapi_spec.lua` covers the API client and `spec/zotero_plugin_spec.lua`
the widget's init guards. Both run entirely offline. `zoteroapi.lua` exposes its HTTP
transport as `API.http`, and each test swaps in a `spec/support/fake_http.lua`
instance serving the canned responses in `spec/fixtures/`:

```lua
fake:on("GET", "/items%?.*start=0$", {
    headers = { ["total-results"] = "150", ["last-modified-version"] = "1214" },
    body = Fixtures.raw("items_page1.json"),
})
ZoteroAPI.http = fake
```

Pagination reads `total-results` off each page, so a stubbed GET needs that header
or the fetch reports that it could not size the collection.

`API.http` is the only injection seam. File I/O and archive unpacking stay real,
because each test gets its own temporary Zotero directory under `KO_HOME`, which the
test runner wipes before every session.

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

`displayCollection` returns copies of the index entries, because `main.lua` inserts
its own rows ("All Items", "No Items") into the returned table.

## Behaviour worth knowing

- An attachment whose `parentItem` is not in the library is hidden from collection
  browsing but still findable by search under its own title. This is odd, and specs
  pin it, so change it deliberately rather than by accident.
- `linked_file` attachments are listed but cannot be opened, since Zotero does not
  serve them. `downloadAndGetPath` returns an explanatory error.
- `API.downloadWebDAV` unpacks through KOReader's `ffi/archiver` (libarchive) rather
  than shelling out. It extracts the archive's first file entry to the filename
  Zotero recorded, so an entry spelled differently still lands where the UI looks.
- `API.setItems` and `API.setCollections` use `assert(io.open(...))`, so a failed
  write raises rather than returning an error.
- If you ever shell out again, note that under LuaJIT `os.execute` returns the exit
  status as a **number** (0 on success, 256 on failure), not a boolean, and that a
  command which prompts will hang the reader. This is what `unzip` used to do.
- Lua patterns are unanchored. Wrapping a search pattern in `.*` matches the same
  strings but makes the matcher retry from every position, which cost about twenty
  times as much on a large library.

## Not set up yet

No CI, no linting, no deploy script. Tests are local only for now.
