# Contributing

## Development

```sh
nix develop
make setup
```

The shell supports Linux (x86-64 and ARM64) and Apple Silicon macOS.
macOS builds require Apple's Command Line Tools.

`make setup` builds KOReader in `../koreader` and links the plugin and specs.
Use `make link` for an existing build, or override `KOREADER_SRC`:

```sh
make setup KOREADER_SRC=~/src/koreader
```

- `make run`: launch the emulator.
- `make build`: rebuild the emulator.
- `make package`: create `dist/zotero.koplugin.zip`.

On macOS, keep GNU binutils off PATH. Its `ar` produces archives Apple's linker
rejects.

## Testing

```sh
nix develop -c make check
nix develop -c make test
```

`make check` runs standalone tests, syntax checks and package validation.
`make test` runs the offline integration suite against a built emulator.
Run both before distributing a package.

Integration specs use `spec/zotero*_spec.lua`, fakes from `spec/support/`, and
fixtures from `spec/fixtures/`. API specs inject `API.http` and reload
`src.zoteroapi` in `before_each`. For retry tests, `spec/support/zotero_env.lua`
records `API.pause` calls.

Run smoke checks from the built emulator's `koreader` directory:

```sh
KO_HOME="$(mktemp -d /tmp/zotero-smoke.XXXXXX)" ./luajit /path/to/zotero.koplugin/tools/smoke-ui.lua
```

`tools/smoke-progress.lua` covers the position lifecycle. Live write tests require
disposable attachments, a temporary profile and cleanup through the fixture manifest.

## Documentation

Keep user help in `docs/` and installation in the README. For compatibility
changes, report the device, KOReader and Zotero versions tested.

## Releases

Push a `vMAJOR.MINOR.PATCH` tag to publish a release:

```sh
git tag v1.0.1
git push origin v1.0.1
```

GitHub Actions runs `make check`, then publishes `zotero.koplugin.zip` with
generated release notes.
