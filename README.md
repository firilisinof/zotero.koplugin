# Zotero for KOReader

This addon for [KOReader](https://github.com/koreader/koreader) allows you to view your Zotero collections.

> [!NOTE]
> **Beta version**! Please report bugs, pull requests are welcome.

<div align="center"><img width="600" alt="Screenshot of this plugin displaying a list of papers alongside a search button" src="https://raw.githubusercontent.com/stelzch/screencasts/main/zotero-koplugin-screenshot.png"></div>

## Features

- Read-only sync of a personal or group Zotero library.
- Browse collections and subcollections, with local download indicators.
- Download and open PDF and EPUB attachments, including personal WebDAV storage.
- Hold a collection to download its direct attachments, with progress, cancellation and per-file errors.
- Hold an attachment to read its parent publication's Zotero notes offline.
- Search titles, first authors and DOIs, optionally restricted to one exact tag.
- Show the last successful sync time, with opt-in startup and stale-cache sync.

## Installation Guide

1. Copy the files in this repository to `<KOReader>/plugins/zotero.koplugin`
2. Obtain an API token for your account by generating a new key in your [Zotero Settings](https://www.zotero.org/settings/keys). Note the userID and the private key.
3. Set your credentials for Zotero either directly in KOReader or edit the configuration file as described [below](#manual-configuration).

In KOReader, the Zotero plugin will be visible in the search tab (magnifying glass icon) inside the top menu.

### Differences to previous  versions
In previous versions, you had to copy your entire Zotero directory to your device.
The new version however works with the Zotero Web API and downloads attachments ad-hoc.
If you are not interested in syncing your collection and would rather access your entire collection offline, you can take a look at version [0.1](https://github.com/stelzch/zotero.koplugin/releases/tag/0.1).

## Configuration

### Personal and group libraries

Open Settings → Configure Zotero account, select the library type, then enter its User ID or Group ID and your API key. The key must have read access to that library. A Group ID is the numeric ID from its Zotero group URL, not your personal User ID. The plugin never writes to Zotero.

Switching the active library clears its cached metadata and last-sync timestamp. Synchronize to populate the selected library. Downloaded files and KOReader sidecars remain on disk. The original personal library keeps its existing paths, and other libraries have separate storage directories.

### Offline collections, notes and tags

Hold a collection row and choose “Download collection”. This downloads direct members only, excluding subcollections and respecting the current tag filter. Files already current are skipped. Tap the progress message to cancel. The final summary includes individual failures, and retrying skips successful downloads.

Collection and search rows show a publication title on up to two lines, with available author and year below. Standalone and orphaned attachments use their own title or filename. Format and download status appear on the right. “Downloaded” means a local file exists, while “Not downloaded” means it is absent. Presence does not necessarily mean that its version matches the latest metadata. Unsupported linked files remain visible as “Unavailable” until a local file exists.

The items-per-page preference is a maximum. The browser reduces page capacity when needed to fit the active font size and prevent rows from overlapping.

Hold an attachment row to open “Show Zotero notes”. Notes are read from the last sync and displayed as plain text. Images, rich formatting, standalone notes and annotations are not included.

Settings → Filter by tag matches one full tag exactly, including case. Publication tags are used for child attachments, while standalone and orphaned attachments use their own tags. Clear the field to restore all items. The filter affects browsing, search and collection downloads, but leaves collection navigation visible.

### Automatic sync

“Sync on startup” and “Sync on browse when older than 24 hours” are disabled by default. Both require configured credentials and an existing network connection. Startup is attempted once per KOReader session and is skipped when offline. Browser-open sync runs when no successful sync is recorded or the last one is more than 24 hours old. Manual sync remains available at any time when another operation is not running.

The menu's last-sync time changes only after a successful complete sync. There is no periodic background sync or automatic Wi-Fi prompt.

### WebDAV support

WebDAV is available for personal libraries. Group libraries always download from Zotero file storage, so WebDAV controls are disabled while a group is selected. Your personal WebDAV settings are retained.

If you do not want to pay Zotero for more storage, you can also store the attachments in a WebDAV folder like [Nextcloud](https://nextcloud.com).
You can read more about how to set up WebDAV in the [Zotero manual](https://www.zotero.org/support/sync).

The WebDAV URL should point to a directory named zotero. If you use Nextcloud, it will look similar to this: [http://your-instance.tld/remote.php/dav/files/your-username/zotero](). It is probably a good idea to use an app password instead of your user password, so that you can easily revoke it in the security settings should you ever lose your device.

### Manual configuration

If you do not want to type in the account credentials on your E-Reader, you can also edit the settings file directly.
Edit the `zotero/meta.lua` file inside the koreader directory and supply needed values:

```lua
-- we can read Lua syntax here!
return {
    ["api_key"] = "", -- API secret key
    ["library_type"] = "user", -- "user" or "group", defaults to "user"
    ["user_id"] = "", -- personal User ID, a positive integer
    ["group_id"] = "", -- Group ID used only when library_type is "group"
    ["filter_tag"] = "", -- one exact tag, empty disables filtering
    ["sync_on_startup"] = false,
    ["sync_on_open"] = false, -- sync on browse when older than 24 hours
    ["webdav_enabled"] = false,
    ["webdav_url"] = "", -- URL to WebDAV zotero directory
    ["webdav_user"] = "",
    ["webdav_password"] = "",
}
```

## Development and validation

Run `make test` for all offline specs and `make run` for the emulator. See [CLAUDE.md](CLAUDE.md) for setup and test conventions.

For a fixture-only UI smoke test, run the following from the built emulator's `koreader` directory, adjusting the plugin path if needed:

```sh
KO_HOME="$(mktemp -d /tmp/zotero-smoke.XXXXXX)" ./luajit /absolute/path/to/zotero.koplugin/tools/smoke-ui.lua
```

The script opens the emulator, exercises the real dialogs and subprocess download flow, and exits. Its temporary profile contains screenshots. It never uses your real Zotero credentials or contacts Zotero.
