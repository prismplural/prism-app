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
| Chat image/audio attachments and member media | Encrypted into Prism's local media cache; attachment identities, thumbnails, tags, and available bytes round-trip |
| Boards | Native board posts |
| Unsupported field shapes, conversation kinds, taxonomy, event-only histories, relationships and provisional modules | Preserved for export without creating native records |
| Extra system profiles | Preserved; Prism still has one native system profile |

Fields beyond the native mapping, foreign extensions, source references, privacy
metadata and additional bundle files are retained. Editing a supported field
changes its exported projection; unrelated metadata stays intact. Native sleep,
polls, habits, reminders and other data without an implemented portable mapping
are carried under `extensions.prism.native_modules` and restored to native
records when recognized. Unknown modules remain opaque. Cached PluralKit banners
are bundled separately from custom header images; restoring them does not
reconnect a PluralKit account.

Preferences are preserved without applying them in the import UI. The service
also supports explicit restoration of known appearance, navigation, terminology,
and feature preferences. It preserves current device locks and onboarding state
and never activates sharing credentials, PluralKit integration, or consent.
Unknown preference keys remain opaque.

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

When a deletion leaves a declared portable record without a required endpoint,
Prism removes that record from the live portable module and retains its complete
source row at `extensions.prism.detached_records`, with a stable reason and the
missing reference metadata. Optional declared links are cleared in the live row
and their original values are retained at
`extensions.prism.removed_references`. This cleanup applies only to declared
PluralPort graph positions; unknown modules, extensions, and custom taxonomy
subjects remain opaque. In particular, an event that loses every assigned member
is detached rather than rewritten as a switch-out event.

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
flow. The complex fixture can export a ZIP with `PLURALPORT_OUTPUT` or verify
an externally produced ZIP with `PLURALPORT_RETURN` when running
`test/features/pluralport/pluralport_foreign_roundtrip_test.dart`. A no-edit
return compares native records and decrypted media bytes; foreign edits use
separate explicit assertions. These checks do not imply every other app
preserves all portable data.
