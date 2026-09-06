#!/usr/bin/env bash
#
# Refreshes spec/fixtures/ from a real Zotero library.
#
# The checked-in fixtures are hand-written to match the Zotero Web API v3
# response shapes. Run this when you want to confirm they still match what the
# server actually sends, or to capture a shape the fixtures do not cover yet.
#
#   ZOTERO_USER_ID=... ZOTERO_API_KEY=... ./tools/fetch-fixtures.sh
#
# It writes to spec/fixtures/live/ rather than overwriting the curated
# fixtures, so you can diff before adopting anything. Note that the output
# contains your library's real metadata: review it before committing.

set -euo pipefail

: "${ZOTERO_USER_ID:?set ZOTERO_USER_ID}"
: "${ZOTERO_API_KEY:?set ZOTERO_API_KEY}"

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/spec/fixtures/live"
mkdir -p "${OUT_DIR}"

fetch() {
    local endpoint="$1" out="$2"
    echo "GET /${endpoint} -> spec/fixtures/live/${out}"
    curl -sS --fail \
        -H "Zotero-API-Key: ${ZOTERO_API_KEY}" \
        -H "Zotero-API-Version: 3" \
        "https://api.zotero.org/users/${ZOTERO_USER_ID}/${endpoint}?since=0&includeTrashed=true&limit=100&start=0" \
        >"${OUT_DIR}/${out}"
}

fetch items items_page1.json
fetch collections collections.json
