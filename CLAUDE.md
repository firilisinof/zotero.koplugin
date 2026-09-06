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

`make setup` creates two symlinks in the KOReader checkout:

- `$KOREADER_SRC/plugins/zotero.koplugin` to this repository
- `$KOREADER_SRC/spec/unit/zoteroapi_spec.lua` to `spec/zoteroapi_spec.lua`

KOReader's own build then symlinks its whole `plugins/` and `spec/` trees into the
emulator output (`Makefile`, the `all:` target). Nothing is copied anywhere, so
**editing a `.lua` file here takes effect on the next `make run` or `make test`
with no rebuild**. Only `make setup` and `make build` compile anything.

The plugin's sources never live in the KOReader checkout. Only the two symlinks do.

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

`spec/zoteroapi_spec.lua` runs entirely offline. `zoteroapi.lua` exposes its HTTP
transport as `API.http`, and each test swaps in a `spec/support/fake_http.lua`
instance serving the canned responses in `spec/fixtures/`:

```lua
fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "150" } })
fake:on("GET",  "/items%?.*start=0$", { body = Fixtures.raw("items_page1.json") })
ZoteroAPI.http = fake
```

`API.http` is the only injection seam. File I/O and `os.execute` stay real, because
each test gets its own temporary Zotero directory under `KO_HOME`, which the test
runner wipes before every session.

Every test calls `package.reload("zoteroapi")` in `before_each`. This is necessary
because `API.init` does not clear the module-level `API.items`, `API.collections` and
`API.modified_items` caches, so a plain re-init would carry the previous test's
library over.

The fixtures are hand-written to match Zotero Web API v3 response shapes. To check
them against a real library, run `tools/fetch-fixtures.sh` with `ZOTERO_USER_ID` and
`ZOTERO_API_KEY` set. It writes to `spec/fixtures/live/`, which is gitignored, so you
can diff before adopting anything.

### Conventions

- Spec files must end in `_spec.lua` or busted will not collect them.
- They are symlinked into KOReader's shared `spec/unit/`, so names have to be unique
  against KOReader's own specs. Prefix new ones with `zotero`.
- Assert on behaviour through the public `API.*` functions rather than on internals.

The WebDAV download specs shell out to the real `unzip` against a real zip fixture
(`spec/fixtures/attachment.zip`), so they cover the unpack step rather than stubbing
it. That makes them a few milliseconds each instead of microseconds.

Under LuaJIT, `os.execute` returns the exit status as a **number** (0 on success,
256 on failure), not a boolean. Every number is truthy, so a shelled-out command must
be checked with `~= 0`.

## Known warts

Left alone deliberately. Worth knowing before touching the surrounding code.

- `API.init` does not reset the module-level caches, as described above.
  `API.resetSyncState` exists partly to work around this.
- `API.displaySearchResults` interpolates the query straight into a Lua pattern, so a
  search containing `%`, `-`, `(` or other pattern characters misbehaves or errors.
- KOReader now warns that the `name` field in `_meta.lua` is deprecated and ignored.
- `API.syncAllItems` stores the library version reported by the *collections* fetch,
  not the items fetch. `spec/zoteroapi_spec.lua` pins this behaviour, so change the
  test deliberately if you change the code.

## Not set up yet

No CI, no linting, no deploy script. Tests are local only for now.
