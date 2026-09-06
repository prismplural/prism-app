# PluralPort import and export

Prism implements the PluralPort v0.1 data model and the ZIP transport proposed in
[PluralPort/spec#15](https://github.com/PluralPort/spec/pull/15).

In Settings → Import & Export → PluralPort, choose a file to preview the import,
then import it. Imports add records; existing records and deletion tombstones
win when their IDs match. Replacing the system profile is a separate, opt-in
choice. Export creates an **unencrypted** `prism.pluralport.zip` containing
`pluralport.json`, `README.txt`, and available media.

## Compatibility

- Write `pluralport_version: "0.1"` and `pluralport.json`.
- Read either `pluralport_version` or `openplural_version`, and either root
  filename. Conflicting version declarations or conflicting JSON roots fail.
- Accept standalone JSON, `.pluralport.zip`, and legacy `.openplural.zip`.
  Contents determine the format; the filename is only a picker hint.
- Resolve `assets[].bundle_path` and the legacy
  `assets[].extensions.sheaf.bundle_path`, with core taking precedence.
  Inline base64/data URI assets are also supported. Remote URLs are retained
  without downloading them.

## Mapping

| Data | Prism behavior |
| --- | --- |
| Members, groups and membership | Native records, including bundled profile images |
| Notes | Native notes |
| Text, markdown, color, date, select and multiselect fields | Native fields and member values |
| Front periods | One native session per assignment; original grouped periods survive unchanged round trips |
| Front comments | Native comments when attached to a period; timestamp-only comments retained |
| Internal chats and direct messages | Native conversations and messages |
| Chat image/audio attachments | Encrypted into Prism's local media cache; decrypted into the export bundle |
| Boards | Native board posts |
| Unsupported field shapes, conversation kinds, taxonomy, event-only histories, relationships and provisional modules | Preserved for export without creating native records |
| Extra system profiles | Preserved; Prism still has one native system profile |

Fields beyond the native mapping, foreign extensions, source references, privacy
metadata and additional bundle files are retained. Editing a supported field
changes its exported projection; unrelated metadata stays intact. Native sleep,
polls, habits, reminders and other data without an implemented portable mapping
are carried under `extensions.prism.native_modules`. These modules are preserved
on import, rather than reconstructed into Prism's corresponding screens.
Member media outside chat includes its Prism association metadata in the asset
extension. It is retained on import, but does not rebuild the native image library.

## Preservation and identity

`PluralPortUnsupported` stores complete source snapshots, native-record bindings,
import baselines and bundle bytes in immutable, SHA-256-verified chunks. The table
participates in sync and native `.prism` backups. Data and preservation chunks
commit in the same import transaction and outbox. An incomplete synced document
blocks export rather than producing an apparently complete file with missing data.

File-local IDs receive deterministic Prism IDs. Re-export adds Prism source
references so a subsequent import keeps those identities. Repeat imports from
one origin use its newest snapshot. Export overlays current native edits onto
that snapshot. Deleted mapped records are omitted and known dependent references
are cleaned up; a retained source copy cannot recreate a deleted native record.
Deleting a native record does **not** erase the source archive from storage.
Uninterpreted modules and files remain archival data, including any references
inside opaque extensions.

Conflicting opaque values from different origins are retained in
`pluralport_preserved_conflicts` alongside the affected object. Conflicting file
bytes at the same path stop portable export; a native Prism backup preserves
both archives. Original producer, capability, warning and README metadata are
retained under `extensions.prism.import_sources`.

## Validation and limits

Imports reject unsafe paths, duplicate ZIP entries, symlinks, encrypted entries,
unsupported compression, integrity mismatches, unresolved core references and
cycles in system/group hierarchies before writing app data. Inflation is bounded
while decoding, including when declared sizes are dishonest.

Limits: 128 MiB input/output ZIP, 256 MiB expanded files, 32 MiB JSON or individual
asset, and 10,000 ZIP entries. The encoded preservation document has its own
384 MiB limit. Media missing from this device is reported in export warnings.
Portable files are not a replacement for encrypted native backups.

The implementation uses the draft contract; no upstream machine-readable schema
or conformance fixtures are available yet. Tests cover aliases, round trips,
local edits/deletions, unknown data, ZIP validation, native backup restoration,
partial sync, migration, transactional rollback, media storage, and the preview
flow. Cross-application interoperability still needs fixtures from other apps.
