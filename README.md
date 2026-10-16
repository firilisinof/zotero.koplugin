<div align="center">

# Zotero for KOReader

**Your Zotero library on your e-reader.** Browse collections, search, download and read PDFs and EPUBs, then sync your highlights and reading position back to Zotero.

[Install](#install) | [Features](#features) | [Configuration](#configuration) | [Compatibility](#compatibility-and-requirements) | [Development](#development)

<br>

<img src="screenshots/home.png" width="23%" alt="Zotero home with Continue reading, Collections, All items, On device and Search">&nbsp;
<img src="screenshots/collection.png" width="23%" alt="A collection listing papers with author, year, format and download status">&nbsp;
<img src="screenshots/search.png" width="23%" alt="Search results for the word learning">&nbsp;
<img src="screenshots/notes.png" width="23%" alt="Zotero notes for a paper, shown offline">

</div>

## Features

| Feature | Description |
| --- | --- |
| **Browse your library** | Collections, subcollections, All items and personal or group libraries |
| **Search** | Titles, first authors and DOIs, with an optional tag filter |
| **Download on demand** | One tap per paper, or a whole collection at once. Zotero storage or WebDAV |
| **Read offline** | Downloaded files open without Wi-Fi or credentials. *On device* lists them |
| **Continue reading** | Jump back into the last document, and return to where you were in the library |
| **Zotero notes** | Read a paper's notes from the last sync, offline |
| **Highlight sync** | Two-way PDF and EPUB highlights, with offline edits and conflict review *(opt-in)* |
| **Reading position** | Pick up on Zotero desktop at the page you left on your e-reader *(opt-in)* |
| **Background sync** | Never blocks reading. Optional sync on startup or when the cache is a day old |
| **Sorting** | Alphabetical, or by date added |

Metadata sync is read-only. The plugin writes to Zotero only when you turn on highlight or reading-position sync.

## Install

1. Download `zotero.koplugin.zip` from the [latest release](https://github.com/firilisinof/zotero.koplugin/releases/latest), or build it with `make package`.
2. Extract it into `<KOReader>/plugins/` and restart KOReader.
3. Create an API key in your [Zotero settings](https://www.zotero.org/settings/keys) and note your user ID.
4. Open **Zotero** from the search tab (magnifying glass) of the top menu, then **Settings → Configure Zotero account**.

When updating, replace the plugin folder. Your downloads, reading progress and settings live in `<KOReader>/zotero` and stay put.

## Configuration

Everything is under **Zotero → Settings**.

| Setting | What it does |
| --- | --- |
| Configure Zotero account | Personal library (user ID) or group library (group ID), plus API key |
| Enable WebDAV storage | Download attachments from your own WebDAV server, e.g. [Nextcloud](https://nextcloud.com). Personal libraries only |
| Filter by tag | Show only items with one exact tag |
| Sort items | Alphabetical, newest first or oldest first |
| Sync on startup / on browse | Automatic sync when already online. Off by default |
| Sync highlights | Two-way annotation sync. Needs write access. |
| Share reading position | Shares the PDF page or EPUB location with Zotero |

**Tips:** hold a collection to download all of it, and hold a paper to read its notes.

<details>
<summary>Configure without typing on the e-reader</summary>

Edit `<KOReader>/zotero/meta.lua`:

```lua
return {
    ["api_key"] = "",
    ["library_type"] = "user",  -- "user" or "group"
    ["user_id"] = "",
    ["group_id"] = "",          -- only for group libraries
    ["webdav_enabled"] = false,
    ["webdav_url"] = "",        -- as entered in Zotero; "/zotero" is added when missing
    ["webdav_user"] = "",
    ["webdav_password"] = "",   -- an app password is safer
}
```

</details>

## Compatibility and requirements

- **Tested software:** KOReader desktop emulator `v2026.07.2-130-g92bf75f03` and Zotero desktop **10.0.1**. These identify the validated combination; a minimum supported KOReader version has not been established. Other builds and versions are unverified.
- **Hardware:** v1.0.0 is released without Kindle hardware testing. Installation, performance and physical suspend/resume on Kindle or other e-readers are unverified.
- **Account and permissions:** a Zotero account, library ID and API key with read access to the selected personal or group library. Enable file access for Zotero-hosted downloads and note access to read notes. Highlight sync requires write access to that library. Reading-position sharing requires personal-library read/write permission for the key owner, including when reading a group attachment.
- **Storage:** PDFs and EPUBs must be available through Zotero storage, or WebDAV for personal libraries. Group downloads use Zotero storage. Linked files cannot be downloaded from Zotero, but an existing local copy can be opened.
- **Runtime and connectivity:** no companion service, desktop extension or extra device runtime is required. Sync and new downloads need network access; existing downloads remain readable offline. Automatic sync only uses an existing connection.

## Known limitations

- **Handoffs:** highlight and position sharing are separate opt-in settings. Open documents through the plugin and synchronize Zotero before switching readers. Both sides must use identical attachment bytes; replacing a document pauses sharing for the old identity. Pending imports into a closed document wait until it is reopened. Conflicting highlight edits require review through **Resolve highlight conflicts**.
- **PDFs:** position sharing uses physical pages. Highlight sync supports one page or two consecutive pages; longer ranges are unsupported. Exact imported rectangles are displayed in ordinary PDF view; reflow uses KOReader's native word-based rendering. Highlight ordering uses page and vertical position rather than an exact character offset.
- **EPUBs:** position and highlight conversion requires an exact mapping to XHTML content. Highlight ranges must stay within one spine entry; cross-spine and collapsed ranges are unsupported. MathML/object transformations, CDATA boundaries, unresolved named entities, ambiguous text normalization and media offsets can prevent conversion. Sections are limited to 8 MiB and XML depth 256. Unsupported locations are reported rather than approximated.
- **Annotations:** text highlights and underlines are supported. Drawings, area annotations, embedded read-only annotations, unsupported remote colors and formatted native comments are preserved rather than rewritten. KOReader invert maps to a highlight, olive maps to green, and other unknown local colors use yellow.
- **Browsing:** search covers titles, first authors and DOIs. The tag filter accepts one exact, case-sensitive tag. Saved searches are not supported. Collection downloads include direct attachments only, subject to the active tag filter. “On device” lists downloaded attachments still present in the active library's filtered metadata cache.

## Development

```sh
make setup   # one time: clone and build KOReader for the desktop emulator
make run     # open the emulator with the plugin loaded
make test    # offline integration suite
make check   # unit tests, syntax and package checks (what CI runs)
```

See [CLAUDE.md](CLAUDE.md) for architecture and test conventions.

## Credits

Forked from [stelzch/zotero.koplugin](https://github.com/stelzch/zotero.koplugin). Licensed under the [GPL-3.0](LICENSE). Bug reports and pull requests are welcome.
