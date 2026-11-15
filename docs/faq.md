# Library and settings FAQ

## What permissions does my API key need?

Give it read access to the selected personal or group library, file access for
Zotero-hosted downloads, and note access to read publication notes. Highlight
sync needs write access to that library. Position sharing needs personal-library
read/write permission for the key owner, even for group attachments.

## Can I read offline?

Yes. Choose On device to browse and search downloaded attachments in the active
library.

"Downloaded" means a local file exists. It may be older than the Zotero copy.
Use Download collection to update stale copies.

## How do I download a collection?

Hold its row and choose Download collection. This downloads direct attachments,
excluding subcollections and respecting the tag filter. Tap the progress message
to cancel. Retrying skips files already up to date.

## Where are my notes, filters and sorting options?

Hold an attachment and choose Show Zotero notes to read its parent publication's
cached notes as plain text.

Settings > Filter by tag matches one complete, case-sensitive tag.
Settings > Sort items offers alphabetical or date-added order.
Date-added sorting uses the parent publication's date when available.
Search covers titles, first authors and DOIs. Saved searches are not supported.

## What happens when I switch libraries?

Enter the new library under Settings > Configure Zotero account, then synchronize.
Switching clears the active metadata cache but keeps downloaded files and reader
sidecars. Each library has its own saved browser location and download directory.
Continue reading reopens the last available document opened through the plugin
in that library.

## Does synchronization happen automatically?

Only if you enable Sync on startup or Sync on browse when older than 24 hours.
Both are off by default and require an existing connection. Automatic operations
never ask to turn on Wi-Fi. Manual sync remains available, and tapping its
progress message cancels it. Failed or cancelled library sync keeps the previous
cache.

Position and highlight sharing have their own settings. See the
[position](position-sharing.md) and [highlight](highlight-sync.md) FAQs.

## How do I configure WebDAV?

For a personal library, enter the same WebDAV URL and credentials used in Zotero.
The plugin adds `/zotero` when needed and assumes HTTPS when no scheme is given.
Group libraries use Zotero storage.

See [Zotero's sync documentation](https://www.zotero.org/support/sync) for server
setup.

## Can I enter credentials without typing on the reader?

Close KOReader and edit the existing `zotero/meta.lua` in its data directory.
Set `api_key`, `library_type` (`"user"` or `"group"`), and `user_id` or `group_id`.
