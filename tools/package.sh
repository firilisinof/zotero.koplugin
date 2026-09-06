#!/bin/sh
# Build an installable ZIP from the current working tree. Usage: make package

set -eu

plugin_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
package_output="$plugin_root/dist"
mkdir -p "$package_output"
package_stage=$(mktemp -d "$package_output/.package.XXXXXX")
trap 'rm -rf "$package_stage"' EXIT
trap 'exit 1' HUP INT TERM

# Select runtime files explicitly so fixtures, credentials and tooling stay out.
mkdir "$package_stage/zotero.koplugin"
cp "$plugin_root"/*.lua "$plugin_root/LICENSE" "$package_stage/zotero.koplugin/"

# A fresh archive cannot retain removed modules. Stage beside the destination
# so a failed build leaves the previous package intact until the final rename.
(
    cd "$package_stage"
    zip -q -X zotero.koplugin.zip zotero.koplugin/*
)
mv "$package_stage/zotero.koplugin.zip" "$package_output/zotero.koplugin.zip"
printf 'Created %s\n' "$package_output/zotero.koplugin.zip"
