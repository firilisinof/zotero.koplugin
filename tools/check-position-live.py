"""Opt-in live validation using only newly created test attachments.

The manifest contains no credentials. Cleanup only touches keys recorded by create.
Use --phase create, then tools/position-live.lua, then --phase cleanup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--credentials", type=Path, required=True)
parser.add_argument("--manifest", type=Path, required=True)
parser.add_argument("--phase", choices=["create", "cleanup", "read"], required=True)
args = parser.parse_args()
match = re.search(r'\["api_key"\]\s*=\s*"([^"\\]+)"', args.credentials.read_text())
assert match, "API key missing from the specified settings file"
secret = match.group(1)
origin = "https://api.zotero.org/"


def request(path, method="GET", body=None, form=False, headers=None):
    actual_headers = {"Zotero-API-Key": secret, "Zotero-API-Version": "3", **(headers or {})}
    if body is not None:
        actual_headers["Content-Type"] = "application/x-www-form-urlencoded" if form else "application/json"
        body = (urllib.parse.urlencode(body) if form else json.dumps(body)).encode()
    req = urllib.request.Request(origin + path, data=body, method=method, headers=actual_headers)
    try:
        response = urllib.request.urlopen(req, timeout=30)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Zotero {method} returned HTTP {exc.code}") from None
    with response:
        raw = response.read()
        delay = int(response.headers.get("Backoff", 0))
        if delay:
            time.sleep(delay)
        return json.loads(raw) if raw else None


if args.phase == "create":
    assert not args.manifest.exists(), "Refusing to overwrite a live test manifest"
    owner = str(request("keys/current")["userID"])
    state = {"owner": owner, "items": [], "test_id": str(uuid.uuid4())}
    args.manifest.write_text(json.dumps(state, indent=2))
    fixture = Path(__file__).resolve().parents[1] / "spec/fixtures/positions"
    for filename, content_type in [("sample.pdf", "application/pdf"), ("sample.epub", "application/epub+zip")]:
        path = fixture / filename
        contents = path.read_bytes()
        item = {"itemType": "attachment", "linkMode": "imported_file", "title": "Position sharing test " + filename,
                "filename": filename, "contentType": content_type, "tags": [{"tag": "position-sharing-test"}], "relations": {}}
        created = request(f"users/{owner}/items", "POST", [item], headers={"Zotero-Write-Token": uuid.uuid4().hex})
        assert "0" in created["successful"], "Fixture creation failed"
        attachment = created["successful"]["0"]
        entry = {"key": attachment["key"], "path": str(path), "format": content_type,
                 "md5": hashlib.md5(contents).hexdigest()}
        state["items"].append(entry)
        args.manifest.write_text(json.dumps(state, indent=2))
        file_endpoint = f"users/{owner}/items/{entry['key']}/file"
        upload = request(file_endpoint, "POST", {"md5": entry["md5"], "filename": filename,
                         "filesize": len(contents), "mtime": int(time.time() * 1000)}, form=True,
                         headers={"If-None-Match": "*"})
        if not upload.get("exists"):
            # Credentials go only to api.zotero.org, never to the storage upload URL.
            assert urllib.parse.urlsplit(upload["url"]).scheme == "https", "Upload URL must use HTTPS"
            req = urllib.request.Request(upload["url"], data=upload["prefix"].encode() + contents + upload["suffix"].encode(),
                                         headers={"Content-Type": upload["contentType"]}, method="POST")
            with urllib.request.urlopen(req, timeout=30) as response:
                assert response.status == 201, "Fixture file upload failed"
            request(file_endpoint, "POST", {"upload": upload["uploadKey"]}, form=True, headers={"If-None-Match": "*"})
        verified = request(f"users/{owner}/items/{entry['key']}")
        assert verified["data"]["md5"] == entry["md5"], "Uploaded checksum differs"
        print("Created dedicated", filename, "attachment", entry["key"])
else:
    state = json.loads(args.manifest.read_text())
    assert str(request("keys/current")["userID"]) == state["owner"], "Manifest belongs to another account"
    prefix = f"users/{state['owner']}"
    for entry in state["items"]:
        key = entry["key"]
        setting = f"{prefix}/settings/lastPageIndex_u_{key}"
        if args.phase == "read":
            print(entry["format"], key, json.dumps(request(setting)))
            continue
        attachment = request(f"{prefix}/items/{key}")
        assert attachment["data"]["title"].startswith("Position sharing test "), "Refusing to remove a non-fixture item"
        try:
            value = request(setting)
        except RuntimeError as exc:
            if "HTTP 404" not in str(exc):
                raise
        else:
            request(setting, "DELETE", headers={"If-Unmodified-Since-Version": str(value["version"])})
        request(f"{prefix}/items/{key}", "DELETE", headers={"If-Unmodified-Since-Version": str(attachment["version"])})
        print("Removed dedicated test attachment and setting", key)
    if args.phase == "cleanup":
        state["cleaned"] = True
        args.manifest.write_text(json.dumps(state, indent=2))
