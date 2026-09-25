#!/bin/sh
# Run the existing emulator's test runner without rebuilding native dependencies.
set -eu
checkout=$1
shift
for candidate in "$checkout"/koreader-emulator-*/koreader; do
    if [ -x "$candidate/luajit" ] && [ -f "$candidate/spec/runtests" ]; then
        cd "$candidate"
        exec bash ./spec/runtests front "$@"
    fi
done
echo "No built KOReader emulator found in $checkout. Run make build first." >&2
exit 1
