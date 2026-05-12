# Changelog

All notable changes to Prism will be documented in this file.

## [0.8.4] - 2026-05-11

This release focuses on sync recovery, PluralKit visibility, and privacy hardening for the next beta build.

### Added
- Device pairing now recovers when your wrapped device key is missing from the sync chain: Prism prompts you to re-confirm your PIN and recovery phrase before pairing instead of failing silently.
- Sync now surfaces quarantined batch warnings and includes a repair action for recoverable oversized batches.
- PluralKit imports now show per-member progress and post-apply status, with a warning before applying destructive remote changes.
- Settings now include a PluralKit sync debug log and a Screen Privacy toggle for hiding app contents in app switchers and screen capture surfaces.

### Changed
- Simply Plural member imports now use an explicit mapping flow before applying imported members.
- Pull-only PluralKit sync now refreshes member fields while preserving the local-only sync boundary.

### Fixed
- Devices with a missing wrapped device key are marked as needing rewrap, and pairing is blocked until recovery has completed.
- iOS and Android screen privacy handling is more reliable, including stale Activity cases on Android.
- Deleted or tombstoned members are removed from groups and hidden from UI surfaces.
- Always-fronting sessions, PluralKit live-front notices, and PluralKit failure messages behave more predictably.
- Chat keeps keyboard focus after sending and avoids avatar flicker during PluralKit sync.

## [0.8.3] - 2026-05-10

This release focuses on PluralKit control, safer import/sync recovery paths, and a few beta rough edges that could leave the app in a confusing state.

### Added
- PluralKit sync now has a mode picker: Full Sync for regular profile/history sync, or Live Fronts Only for systems that only want Prism to record new PluralKit front changes while leaving older history, profiles, groups, and system data alone.

### Changed
- PluralKit setup now keeps sync mode, sync direction, auto-sync, manual sync, and member mapping controls together in the main setup screen.

### Fixed
- Sync setup no longer treats a partially-saved device identity as paired after an interrupted setup, so affected devices land back in a recoverable unpaired state.
- Android biometric app-lock prompts work again.
- Simply Plural imports no longer collide with Prism's Unknown placeholder member when re-importing or importing over existing local data.
- Add Front no longer shows Prism's persisted Unknown placeholder as a regular selectable member.
- PluralKit imports respect members you chose to skip during mapping.
- Export now only marks a backup complete after the share sheet reports success; dismissing or failing the share keeps the export ready so you can try again.
- Open sheets now follow system light/dark theme changes instead of keeping stale colors until reopened.
- Habit rows, chips, and related surfaces honor angular shape settings more consistently.

## [0.8.2] - 2026-05-09

This release smooths out fronting, chat, navigation, and sync flows after 0.8.1. It adds clearer current-session context, reduces noisy sync feedback, and fixes several edge cases around orphaned chat data, member cleanup, and markdown bios.

### Added
- Fronting history now shows a current-session chip for sessions that are still active.

### Changed
- Quick Front now labels hold actions more clearly and updates its hint when member changes affect who can be fronted.
- Sync setup now allows first-device registration when an attestation proof is not available.

### Fixed
- Retryable sync errors no longer show noisy user-facing toasts.
- Board posts, habit detail, member detail, and fronting history navigation preserve their detail back stacks more reliably.
- Chat restores the Unknown author option where it is needed, including orphaned imports and existing conversations.
- Orphaned direct messages stay visible but read-only instead of allowing edits that cannot be attributed safely.
- Markdown bios preserve indentation and nested formatting more accurately.
- Member deletion cleanup now removes stale references from fronting defaults and related member settings.
- PluralKit imports preserve the remote member name in Prism's local name field while storing PluralKit display names separately.
- Image avatars no longer draw the glass highlight overlay over the saved photo.

## [0.8.1] - 2026-05-09

### Added
- Chat now has separate Direct Messages and Group Chats tabs, and opens to Group Chats by default.
- Chat, Boards, fronting setup, Quick Front, wake-up, post author, and PluralKit mapping flows now use searchable member pickers in more places.
- Habits now let you edit or delete individual completion records from a long-press menu.
- Habit detail now has a Log Missed Completion action that opens the completion sheet on a past date by default.
- Simply Plural import can apply avatars from exported avatar ZIP files after JSON import.
- PluralKit sync can push local group membership additions and removals back to PluralKit when bidirectional group sync is enabled.
- Linked members now have a separate PluralKit Display Name field, so Prism's local Name and Full Name are not overloaded with PluralKit's `display_name`.

### Changed
- The Chat top bar now has a searchable member selector for choosing who is speaking.
- Boards member filtering and post author selection now use the shared member selector and can reach all visible members.
- Group detail actions now live in the overflow menu, leaving more room in the header.
- Chat category assignment now uses a compact dialog instead of a bottom sheet.
- More overflow and popup menus use the shared Prism popup behavior, including automatic dismissal on navigation.
- Light mode contrast, accent rendering, buttons, surfaces, and per-member profile accents have been tightened for readability.
- Sync setup now hides the relay registration token field until a custom relay URL is entered.
- Starting several co-fronters at once now applies the fronting changes in one batch.
- PluralKit co-fronter pushes now send the full active fronter set as a multi-member switch.
- PluralKit member creation now seeds the remote name from Full Name when available, while existing local Name and Full Name stay Prism-local.

### Fixed
- Chat no longer gets stuck behind stale DM overlays or a stale speaking-as selection.
- The speaking-as picker no longer reopens the keyboard when you change who is speaking.
- Chat search is faster and renders mention results as member chips.
- Member picker search is easier to reach from Chat, fronting, Boards, onboarding, wake-up, and PluralKit mapping flows.
- Fronting upgrade prompts no longer appear before Prism has loaded the current migration state.
- Zooming back out on the fronting timeline keeps the visible history in bounds.
- Fronting history periods no longer overlap after long deletions, and sleep gaps stay split in history.
- Add-front discard prompts now appear only when notes would be lost.
- Avatar crops keep their saved resolution instead of being degraded by later saves.
- Member profile accent colors now honor the per-member accent setting more consistently.
- Reminder rescheduling now cancels stale notification IDs when reminders change or disappear.
- Simply Plural chat import now preserves reply quotes from exported reply threads.
- Markdown bios preserve authored line breaks while still rendering links correctly.
- Habit completion edits update only the intended fields, keep past-date schedules and notifications consistent, and preserve all-time best-streak math.
- Dirty sheets now guard swipe dismissal more consistently across edit/create flows.
- Tapping outside inputs dismisses the keyboard in more places.
- Emoji picker search focus and filtering are stable again.
- Manage-groups checkboxes stay hidden until membership data has loaded, and the sheet uses Prism's spinner.
- PluralKit sync respects deleted/tombstoned current switches during polling.
- PluralKit group sync cleans up removed groups more reliably across buckets.
- PluralKit member import, export, local sync, and device sync preserve the new PluralKit Display Name field.

## [0.8.0] - 2026-05-07

### Added
- Expanded onboarding with appearance, terminology, navigation, and fronting-default setup.
- Navigation setup now adapts the default tab layout to the current device before saving.
- Simply Plural custom-front handling is available from onboarding import.
- Per-member fronting history from member detail screens.
- Member folder view settings for choosing how groups display.
- Optional member-list front buttons for adding or replacing current fronters directly from member rows.
- Optional member pronoun visibility in member lists.
- Deeper member group nesting, now up to five levels.
- Ancestor breadcrumbs in group detail headers for nested groups.

### Changed
- Redesigned onboarding welcome and completion screens with Prism branding and clearer finish-state copy.
- Split fronting behavior choices out of generic preferences into a dedicated onboarding step.
- Member reordering is faster on large systems.
- Member view settings copy is clearer and hides unavailable front-button details when the setting is off.
- Removed the internal feedback tracker service.

### Fixed
- Custom field edits on member profiles are saved reliably, including focused fields when saving.
- Reminder notifications no longer schedule duplicate or stale reminder alerts.
- Conversation emoji edits can be preserved and cleared correctly.
- DM participants can delete DMs they are part of.
- Member pickers in note editing respect custom terminology instead of falling back to default wording.
- Crowded fronting history rows adapt instead of overflowing.
- Quick-front names fit the available slot width.
- Per-member fronting history keeps the expected back stack after opening session detail.
- Lazy-loaded fronting history stays stable while older rows load.
- Imported Simply Plural chat features stay locked during onboarding unless explicitly enabled.
- Onboarding ignores third-party navigation config from imports and seeds safe local defaults.
- Onboarding appearance choices update the live preview correctly.
- Onboarding skip and Material You gating no longer leave release builds in the wrong state.
- Ending a fronting session uses the intended exit icon.

## [0.7.6] - 2026-05-06

### Added
- Log a past fronting session — new flow with inline start/end timing on the Fronting tab.
- Auto-promote always-present members as co-fronters on new sessions (Settings → Features → Fronting).

### Changed
- Poll and group-description editors now use the markdown editor (formatting markers dim while typing).
- Disabled feature routes (chat, polls, habits, notes, reminders) redirect to home, matching sleep/boards.
- Refined fronting delete dialog wording.

### Fixed
- @ mentions in group chats now list every active member, not just stored participants. DMs still filter to participants.
- Chat mention picker and rendering reliability.
- Dark-mode styling for markdown task-list checkboxes.
- PluralKit member-link and import identity edge cases.
- Simply Plural migration parity gaps in the API client, parser, and mapper.

### Security
- Markdown image URLs in chat no longer fetch remotely (was an IP-leak vector).
- Unsafe-scheme links in longform markdown render as plain text instead of looking tappable.

## [0.7.5] - 2026-05-05

### Changed
- Replaced the native image cropper with a Flutter-side cropper to fix crashes in the platform plugin (build 7502).

### Fixed
- Fronting migration no longer drops orphaned sessions from older imports — they route to the Unknown sentinel.
- Simply Plural chat import no longer overwrites earlier pages of long histories.
- Material You fallback normalized on non-Android devices with sync enabled.
- Sync preserves fronting replacement order across devices with slight clock drift.
- Sync reconnects trigger an immediate catch-up pass instead of waiting for a later local edit.

## [0.7.4] - 2026-05-04

### Added
- Markdown in custom fields, plus a new Long Text custom field type.

### Fixed
- Fresh-install pairing hang.
- Avatars no longer re-encode on every member save (caused gradual quality loss).
- Unread badges no longer show on DMs you aren't part of.

## [0.7.3] - 2026-05-03

### Added
- 0.5× playback speed for voice messages. Tap the speed button to cycle 1× → 1.5× → 2× → 0.5× → 1×.

### Fixed
- Fronting upgrade now completes for systems whose old multi-member fronting rows contain repeated or blank co-fronter IDs. This could happen after some older Simply Plural imports and caused the upgrade to fail with a duplicate fronting session ID.
- Blank or whitespace-only member IDs in old fronting rows are now treated as unresolved and routed to the Unknown sentinel instead of being preserved as invalid member references.
- Restoring PRISM1 backups with the same duplicate/blank co-fronter shape now imports cleanly through the rescue path.
- PluralKit full re-imports are idempotent again for histories with a currently-open row late in the timeline. A second full import no longer tries to close that current row against older switches.
- Sync no longer asks for your PIN and recovery phrase after a background wake on Android while the device was locked.
- Voice messages played at 1.5× or 2× no longer start at normal speed with the wrong pitch. The speed setting now takes effect on the first playback, including after replaying a finished voice message.

## [0.7.2] - 2026-05-03

### Added
- **Settings → Sync → Sync troubleshooting → Advanced diagnostics → Crypto storage** — new diagnostic screen for sign-in prompt issues. Lists which on-device credential slots are present (no values shown, only presence + size) and snapshots state on every cold start, so you can scroll back to the exact launch where something went missing. Most useful when sharing with support if you've hit unexpected PIN or recovery-phrase prompts.

### Fixed
- Sign-in prompts no longer come back after a transient device-credential hiccup on Android. Pre-fix, the on-device cached unlock key was being discarded any time the system briefly couldn't unwrap it (a lock-screen race after boot, a secure-element flake), forcing a fresh PIN + recovery-phrase entry on the next launch. The cache now retries once and stays put on transient errors, so a passing flake costs at most one re-auth in that session — the next launch reads the cache cleanly.

## [0.7.1] - 2026-05-03

### Fixed
- Fronting upgrade now completes for systems that did a PluralKit file import on an older build. The migration was tripping a database check at the end of the cleanup step on rows from old PK imports where the member couldn't be resolved at import time; those rows are now removed before the constraint is installed. Affected users complete the upgrade on retry after installing this build.
- Importing a PRISM1 backup that contains legacy orphan rows (no resolved member) now succeeds — the rescue importer routes those rows to the Unknown sentinel instead of failing partway through with a database error.

## [0.7.0] - 2026-05-02

### Added
- Per-member fronting sessions — fronting data model rewritten so each member who's up has their own session row instead of a primary-plus-co-fronters tuple. Co-fronters can end independently; analytics reports actual member-minutes; splitting and editing operate on the right members.
- One-time fronting migration on first launch — multi-step modal (PIN → backup builds → durable-save gate → atomic migration). Backup is the standard `.prism` format; migration either completes fully or rolls back to the old shape so it can be retried.
- PRISM1 rescue importer — backups taken before 0.7.0 are converted from the old single-entry shape to per-member sessions on import, automatically.
- Period Detail screen for multi-contributor periods — header with time range and members, brief summary, "always present" section, and range-scoped comments. Supports period-level delete and gracefully handles fully-stale periods (toast + pop).
- Member Message Boards (new feature, opt-in) — per-member boards with public + private posts, Public/Inbox sub-tabs on the Boards tab, compose sheet that pre-targets the member you started from, and a per-member detail screen. Settings → Features and Onboarding both have toggles; auto-enables for systems with previously-imported SP message-board-shaped DMs.
- Sleep tab (top-level) — last-night card (duration + quality), 7-day average card with vs-prior-week trend, paginated history, active sleep card. Long-pressing the Sleep Mode card jumps to the Sleep tab.
- Log past sleep session from the Sleep tab, with overlap warning against existing sessions.
- "Always present" pinned glass header on the Fronting tab — surfaces members flagged as always-fronting plus members whose current session has been open for at least a week.
- Session list view setting — Combined periods (default), Per-member rows, Timeline (Settings → Features → Fronting → Session list view).
- "When adding a new front" + "When using quick front" behavior settings — additive (co-fronter) vs replace.
- Member profile headers (banner image), custom color picker, name style controls, editable proxy tags for PluralKit-linked members.
- PluralKit fronting import from a file token without an API connection (paste a `pk;token` and a file together; file provides history, token drives ongoing sync).
- Image paste in chat via custom clipboard reader (handles platforms that previously dropped pasted images).
- Floating end-session button on the active session detail screen.
- Locale-aware weekday and month names + 12h/24h time on weekday picker (habit/reminder editors), timeline gutter, poll expiration dates, and habit completion timestamps.
- Spanish translations for end-session button, next-fronter dialog, fronting upgrade modal, Period Detail screen, analytics screen, PluralKit mapping flow, secret-key reveal, and biometric onboarding.
- Settings → About: real installed version + working external links (website, GitHub, Discord, Bluesky, Tumblr, privacy, encryption, feedback email).

### Changed
- Quick "front a member" actions on the home screen require a hold instead of a tap (with a progress ring) to prevent accidental sessions.
- Period entries in the fronting history use a long-press menu instead of swipe-to-delete (End / Edit / Delete; Wake Up / Edit / Delete on sleep entries).
- Member actions on the Members tab moved from swipe-to-delete to a long-press menu, with haptic feedback.
- Member archiving now requires a confirmation step.
- Statistics screen reports per-member fronting time correctly when members overlap (a co-fronter who was up for two of four hours is credited with two).
- Custom terminology ("Parts", "Headmates", "Alters", etc.) applied in dialog copy and fronting flow surfaces that were still falling back to "Members".
- Member profile edit sheet polish — fields easier to reach with one hand, save behavior consistent across name, color, avatar, and proxy fields.
- Sleep moved out of the Fronting tab into its own top-level tab (where enabled).
- "Zero-knowledge" terminology replaced with accurate "end-to-end encryption" in the app and on the site (no on-wire change).
- "Third-party audit" line on the encryption page softened until the audit is done and citable.
- Apple App Attest verification migrated from the legacy CBOR library to a maintained one (ciborium); now fails closed if attestation roots are missing.
- First-device sync bootstraps from a snapshot first (faster setup; removes a class of partial-state bugs from interrupted bootstraps).

### Fixed
- Display font toggle — turning off the bundled display font in Settings now actually disables it (previous build silently kept it active).
- Popup menus opened from a text field while the keyboard is up no longer hide behind the keyboard.
- Notification permission status checks no longer prompt for the permission on iOS and macOS (now uses `checkPermissions` instead of `requestPermissions`).
- SP-imported group channels are visible again — they were getting filed as direct messages with empty participant lists when the SP export omitted `members`, and the DM privacy filter then hid them.
- Habit reminders no longer fire for periods that are already completed (notably for already-logged sleep sessions).
- PluralKit push to PluralKit is now source-aware — changes that came from PluralKit don't get pushed back as if they were local edits.
- PluralKit corrective re-import preserves user-side tombstones — members deleted in Prism stay deleted instead of being resurrected by a re-pull. Upgrade sheet reports how many tombstones were kept.
- PluralKit incremental-sync cursor and pagination are stable — long histories no longer occasionally re-fetch the same page or skip a window.
- PluralKit corrective re-imports are idempotent.
- PluralKit re-import from the migration sheet stays in the sheet instead of dropping the user out mid-flow.
- Joiner devices recover from epoch rotations during pairing instead of getting stuck.

### Security
- Encrypted op batches are padded so batch size doesn't leak how much was written.
- Wrapped key material is bound to a versioned context, blocking cross-context replay of wrapped keys.
- Runtime DEK cache is bound to the device — a leaked cache file can't be unwrapped on another machine.
- Pairing SAS hardened; signature floors added so a stale signature can't be replayed.
- Change-PIN flow hardened so a partway failure can't leave PINs out of sync across material.
- Sync error messages and logs no longer leak internal field values — sensitive content redacted before it can reach a clipboard.
- Sync supply-chain check added to CI to catch malicious dependency updates in the sync layer.

## [0.6.2] - 2026-04-25

### Added
- Statistics screen redesign with a single member-ranking chart at the top, tap-to-toggle time/percentage labels, and system-wide median session length
- Remove-photo button on the member avatar editor

### Fixed
- Sunday weekly reminders no longer freeze the app
- Notes detail view updates immediately when a note is edited
- Member name, emoji, color, and avatar edits propagate immediately across chat, fronting timeline/history, and reaction bars
- Importing a Prism backup no longer aborts on tombstone PluralKit-link collisions
- Splitting a PluralKit-linked fronting session no longer fails with a unique-constraint error
- PluralKit sync absorbs duplicate-switch unique-constraint errors instead of surfacing "Sync failed" (the 0.6.1 catch never actually fired)
- Members tab uses custom terminology (Parts, Headmates, etc.) even when the navigation overflow menu is visible
- Export password hint matches the actual 12-character minimum
- Conversation info sheet lets you unarchive a conversation
- Members under a parent group stay visible when the last child subgroup is collapsed

## [0.6.1] - 2026-04-25

### Added
- PluralKit member banner URL is now stored locally (UI to follow in a future release)

### Fixed
- PluralKit groups were silently dropped during file import when no API token was linked — they now always import from the file
- PluralKit concurrent sync (auto-poll firing alongside a manual sync) could crash with a SQLite unique constraint error; fixed with an `isSyncing` guard and a defensive catch at the insert site
- PluralKit member display name (PK alias) is now shown as a subtitle in Prism rather than replacing the member's name
- Android: removed deprecated bar color attributes in the avatar crop screen on SDK 35+
- Android: dropped remaining custom theme attributes on the avatar crop screen for SDK 35+ — the previous strip-down still left `windowBackground` and `colorAccent` on `PrismUCropTheme`, which kept triggering crashes when opening the cropper on Android 16 stable. The activity now inherits a bare `Theme.AppCompat[.Light].NoActionBar` (matching the upstream uCrop sample) and brand colors are applied at call time via `AndroidUiSettings`, including the new `statusBarLight` / `navBarLight` properties for proper edge-to-edge contrast.

## [0.6.0] - 2026-04-24

### Added
- Spoiler support in chat with `||spoiler||` syntax and consistent redaction across previews, replies, search, and Semantics
- Shared member search sheet across the app with `None` / `Unknown` rows where appropriate
- Sync epoch key auto-recovery
- Snapshot bootstrap for faster first sync on new devices
- Graceful handling of ambiguous management-relay failures
- Pairing and registration flow hardening
- Custom relay URL support during onboarding pairing
- Native in-app avatar cropping (image_cropper + TOCropViewController on iOS)
- Voice-note pitch preservation at 1.5× and 2× playback
- Linux desktop runtime and packaging (`.deb`, AUR, Flatpak) with desktop metadata, icons, and emoji/font support
- Accessibility audit pass — chart screen-reader summaries, clearer Semantics on onboarding and note flows, broader screen-reader polish
- PluralKit group sync repair flow with localized surfaces, QR review, and a debug group tester
- Site updates feed and release notes pages

### Changed
- Direct-message privacy tightened — non-participants no longer see DMs in lists or by ID; admins can inspect but not participate; backup/export preserves DM semantics
- Search snippets built from redacted content so spoiler text doesn't leak through results
- Search matching now Unicode-normalized for decorative and fullwidth text
- Adaptive mobile nav-bar layout for narrow screens and large text
- PluralKit group sync identity anchored on stable PK UUIDs (was positional matching)
- PluralKit group sync hardening — alias-delete cascade closed, defers on PK-UUID miss, canonicalization bulk-loaded with composite index, Phase 1 migrations consolidated into v3→v4, emits gated on complete PK-UUID pair
- PluralKit cooldown timer disposal coverage; `dart format` applied across pluralkit/
- Fronting home session row durations no longer show seconds
- Site brand polish — PRISM3 → PRISM1 rename, post-quantum safety flag, outlined social icons, PRISM1 format reference

### Fixed
- Hidden chat spoiler rendering
- Spoiler redaction in reply banner preview, reply-quote Semantics, and search-tile Semantics
- Animated spoiler fade via `InheritedNotifier`
- Member group chip scroll jump
- Quick-front hold controller reset after completed hold
- Fronting timeline sanitization scanning
- Onboarding features list scrollable on small screens / large text
- PluralKit group sync Drift `DateTime` encoding in three raw-SQL sites
- Audit findings closed across batches one through four plus a nit-cleanup pass

### Removed
- Onboarding debug skip shortcut

## [0.5.1] - 2026-04-20

### Added
- Fastlane macOS internal TestFlight lane for distributing macOS builds alongside iOS/Android

### Fixed
- Full device reset now purges all keychain items, including orphaned bare-named keys left over from older app versions that prevented re-onboarding from syncing correctly after an in-app reset
- Sync: fix pairing failure when epoch rotates during initial sync setup and re-setup after reset
- Export: backup file format magic corrected from `PRISM3` to `PRISM1`
- macOS: `LSApplicationCategoryType` (Healthcare & Fitness) now present in all build configurations for correct App Store category display
- Fastlane: resolve build artifact path issues for iOS and macOS lanes; auto-detect App Store Connect API key path; fix Ruby gem environment conflicts with CocoaPods in macOS lane

## [0.3.12] - 2026-04-18

### Added
- PluralKit sync now supports linking existing members via a new mapping screen, two-way field sync for `displayName` and `birthday`, proxy tag pull, and switch history push to PluralKit
- PluralKit onboarding and settings now offer a dual-source picker: connect with an API token for ongoing sync, or import from a `pk;export` JSON file for large systems — mirroring Simply Plural's import pattern
- Standalone `PkFileImportScreen` reuses the shared file-import state machine from both onboarding and PluralKit settings
- Accent color picker is now shared between onboarding and settings, with a legibility warning when low-contrast accents would be hard to read against surface backgrounds

### Changed
- Token-based PK sync now adopts UUIDs in-place for sessions that were previously imported from a `pk;export` file, matching by (timestamp, sorted member IDs) so switches aren't duplicated when the same system is connected via both paths

## [0.3.10] - 2026-04-17

### Added
- Voice note Opus backends: split recording and playback into dedicated chat voice services with shared format detection and focused tests

### Changed
- Voice notes now use a mobile-first Ogg Opus path: Android records Ogg directly, iOS finalizes CAF Opus into Ogg before upload, and playback runs from decrypted bytes in memory through SoLoud
- Voice-note uploads now validate and persist `audio/ogg` metadata instead of carrying the old AAC/M4A assumptions
- Chat compose now shows a preparing state before send when a recorded note is still being finalized
- `FrontingNotifier` migrated from `Notifier<void>` to `AsyncNotifier<void>` so mutation errors surface instead of disappearing
- GIF and image bubbles now pass DPR-aware `cacheWidth`/`cacheHeight` to the Flutter image cache, reducing overdraw on high-density screens
- Chat conversation screen uses `.select()` on the author map provider to avoid unnecessary rebuilds
- Relay WebSocket reconnection now adds random jitter (0–500 ms) to prevent thundering-herd reconnects after a relay restart
- Relay signal handler installation errors are now recoverable (log + pending future) instead of panicking
- Relay `eprintln!` calls replaced with structured `tracing::error!` events
- Relay router now limits concurrent in-flight requests to 512 to prevent connection exhaustion
- Provisioning script prompts operator to save `METRICS_TOKEN` before the session closes

### Fixed
- Importing a backup from a different PluralKit system no longer silently overwrites the current system's connection state — the PK sync state is skipped when the backup's system ID conflicts with the existing one
- Quick-front press now shows an error toast instead of silently dropping failures
- Member detail "Set as Fronter" action now shows an error toast on failure instead of swallowing it
- Chat auto-front on member switch now logs errors instead of discarding them silently
- Post-edit fronting rescan wrapped in explicit `unawaited()` to satisfy the Dart linter

## [0.3.8] - 2026-04-14

### Changed
- Promote `timezone`, `local_auth_platform_interface`, and `plugin_platform_interface` to direct dependencies (were transitive)
- Remove redundant imports: `dart:typed_data` in `database_encryption.dart`, `prism_sync_providers.dart`, and biometric test; `flutter/foundation.dart` in `database_encryption_test.dart`
- `_NavBarItem` in `app_shell.dart`: remove never-used `icon`/`activeIcon`/`label` optional parameters, make `tab` required
- Fix double-underscore wildcard params (`(_, __) → (_, _)`) in `notification_providers.dart`
- Replace closure with tearoff in `permissions_step.dart` (`() => openAppSettings()`)
- Clean up `locale_test.dart`: remove unused helper function, fix unnecessary `?.` on non-nullable receiver, remove unused variable
- Convert `setUp`/`tearDown` closures to tearoffs in `database_encryption_test.dart`
- Fix dangling library doc comment in `migration_step_by_step_test.dart` (`///` → `//`)
- Remove unused local variable in `unread_count_providers_test.dart`
- Promote `local_auth_platform_interface` and `plugin_platform_interface` to dev dependencies

## [0.3.7] - 2026-04-14

### Added
- Stock Material guard test: CI test that fails when agents use stock Material widgets that have Prism replacements, and warns on components without replacements yet

### Changed
- Replaced all stock Material components with Prism design system equivalents across ~35 files:
  - CircularProgressIndicator → PrismSpinner / PrismLoadingState
  - Card → PrismSurface / PrismSectionCard
  - SnackBar / ScaffoldMessenger → PrismToast
  - ListTile → PrismListRow
  - showDialog → PrismDialog.show
  - showModalBottomSheet → PrismSheet.show
  - ExpansionTile → PrismExpandableSection
  - TextButton / FilledButton → PrismButton
  - AppBar → PrismTopBar (allowlisted for image viewer)

## [0.3.6] - 2026-04-14

### Fixed
- Biometric unlock: Face ID / Touch ID button no longer appears on PIN screen when biometric unlock is disabled in settings
- Launch flash: app theme preference now cached in SharedPreferences so the first Flutter frame renders with the correct background color instead of white
- iOS launch screen: added light/dark mode color variants (was hardcoded white for all users)

### Changed
- Secret key reveal: tighter word chip layout, updated copy

## [0.3.4] - 2026-04-13

### Added
- Voice notes settings toggle: disable mic button in chat compose independently of chat feature
- In-app language switcher: override device locale from Appearance settings (English, Spanish, system default)
- Permissions onboarding step: request notification + microphone permissions with rationale during setup
- iOS backup exclusion: sync database and media cache now excluded from iCloud backup

### Fixed
- SystemSettingsMapper missing voiceNotesEnabled and localeOverride fields (silent fallback to defaults on read)
- Migration test expected schema version updated to match v41
- Sync group deletion now cleans up sharing tables, media files, and admin tooling

## [0.3.3] - 2026-04-13

### Improved
- Sync: SyncRelay trait split into 5 focused sub-traits (SyncTransport, DeviceRegistry, EpochManagement, SnapshotExchange, MediaRelay)
- Sync: typed StorageError and CryptoError variants replace stringly-typed error propagation
- Sync: tracing::instrument on sync engine hot paths + conditional JSON log format for relay
- FFI: all Mutex .unwrap() replaced with lock_or_recover() for FFI safety (recovers from poisoned mutex instead of aborting)
- Accessibility: semanticLabel on all MemberAvatar and 6 Image.memory sites; Semantics wrapper on 15 GestureDetectors
- Providers: 12 Notifier<void> migrated to AsyncNotifier<void> with AsyncValue.guard error propagation
- Code dedup: inline duration/datetime formatters replaced with shared extension methods
- l10n: removed 74 unused ARB keys (password-to-PIN leftovers, notes stubs, duplicates)

### Added
- Duration extensions: toVoiceFormat() for M:SS audio display, day support in toRoundedString()
- 24 new tests for duration extensions and AsyncNotifier error paths

## [0.3.2] - 2026-04-12

### Fixed
- Media error feedback: image and voice upload failures now surface a toast instead of silently succeeding
- Download retry: tapping a failed image bubble now invalidates and retries the download (previously showed infinite spinner)
- Media error detection: `mediaFileProvider` throws `StateError` on null bytes so Riverpod correctly surfaces `hasError` (was always `AsyncData(null)`)
- Upload signals: `uploadPreparedOrThrow` / `uploadVoiceOrThrow` use Completer-based callbacks to propagate `UploadQueue` failures to callers
- Reset gaps: biometric DEK (`biometric_dek` keychain entry) now cleared during sync reset alongside main key material
- Reset gaps: `deregisterDevice` 403 (last device) now falls through to `deleteSyncGroup` so relay purges all blobs instead of orphaning them
- Reset gaps: `downloadManager.clearCache()` called during full reset to delete encrypted `.enc` cache files from disk
- Spanish i18n: added translations for `chatImageError`, `chatImageUploadFailed`, `chatVoiceNoteUploadFailed`

## [0.3.1] - 2026-04-12

### Fixed
- Performance: departed member avatars use paint-level opacity instead of compositing ColorFiltered layer
- Performance: archived conversation tiles use simple Opacity instead of ColorFiltered greyscale matrix
- Performance: message highlight animation uses TweenAnimationBuilder child parameter to avoid per-frame widget recreation
- Performance: data import batch-fetches poll options and habit completions instead of N+1 per-entity queries
- Performance: friend detail fingerprint row caches future in state instead of recreating on every build; reacts to key changes via didUpdateWidget
- Accessibility: PrismInlineIconButton default size increased from 32dp to 44dp (iOS HIG minimum)
- Accessibility: PrismCheckboxRow and PrismSwitchRow wrapped in MergeSemantics for single accessible node
- Accessibility: GIF images include contentDescription as semanticLabel for screen readers
- Accessibility: image bubble loading states wrapped in Semantics label
- Security: PIN text field disables keyboard suggestions and autocorrect to prevent cache leaks
- Debug: sync event print() calls replaced with debugPrint() (stripped from release builds)

## [0.3.0] - 2026-04-12

### Added
- PQ local storage encryption: DB encryption keys now derived from DEK+DeviceSecret
  via HKDF (prism_local_storage_v2) — stolen keychain no longer decrypts data without PIN
- PIN auth system: 6-digit PIN replaces freeform password for all Argon2id derivation
- Biometric unlock: iOS Face ID/Touch ID via Secure Enclave-enforced
  `biometry_current_set` keychain items; Android via `AndroidOptions.biometric(enforceBiometrics: true)`
- Recovery phrase onboarding: blurred 12-word BIP39 display with tap-to-reveal,
  copy button, 3-word confirmation step
- `SyncStorage::rekey` trait + `RusqliteSyncStorage` PRAGMA rekey implementation
- `derive_local_storage_key` HKDF function in prism-sync-crypto crate
- FFI: `localStorageKey()` and `rekeyDb()` Dart bindings
- `BiometricService` with real platform biometric binding (not just auth-before-write)
- `AuthPolicyService`: 30-day periodic PIN verification + recovery phrase reminder
- `ChangePinSheet`: full PIN change flow with current PIN verify → warning → new PIN
- `SyncPinSheet`: 6-digit numpad sheet replaces password prompt for sync re-auth
- Media caching: `DownloadManager` caches ciphertext (.enc files) — no plaintext ever written to disk
- In-memory image cache at provider level to avoid re-decryption on widget rebuild
- Self-hosting guide with Docker and Kubernetes deployment configs
- CLA for app/ and sync/ public repo extraction

### Fixed
- Android biometric: `AndroidOptions()` was hardware-backed but not biometric-bound;
  fixed to `AndroidOptions.biometric(enforceBiometrics: true)` so reads require biometric prompt
- Staging key crash recovery: startup now verifies DB opens with staging key before promoting
  (crash before PRAGMA rekey left staging slot stale — blind promotion made DB unopenable)
- Two-DB rotation order: Rust sync DB now rekeyed before Drift DB so crash during rotation
  is safely recoverable on next launch
- PIN length validation: 6-digit guard added to sync setup and change PIN flows before
  submitting to Argon2id path
- SyncPinSheet brute-force lockout: `_failedAttempts` and `_lockedUntil` persisted to
  SharedPreferences so lockout survives sheet dismissal and app restarts
- AuthPolicyService: future timestamp treated as missing (prevents clock-rollback bypass
  of periodic PIN check)
- ChangePinSheet: 5-attempt / 60-second lockout on current PIN verification step
- Relay: default RUST_LOG to info; fix self-hosting documentation

### Changed
- Onboarding flow: welcome → PIN setup → recovery phrase → confirm phrase → biometric setup → …
- Sync setup: PIN from onboarding used for `createSyncGroup`; password entry step removed
- Device pairing: uses PIN via `PinInputScreen` instead of text field password entry
- AppShell: `SyncPinSheet` shown for `needsPassword` state instead of `SyncPasswordSheet`
- `PrismDialog` actions: `Row` → `Wrap` to prevent overflow in narrow viewports
- `PrismButton` loading state: `CircularProgressIndicator` → `PrismSpinner`
- GIF picker error state: "Retry" → "Try Again" (l10n key `tryAgain`)

## [0.2.14] - 2026-04-11

### Added
- Habits: Today container redesign with compact HabitChip widget, split Due/Complete sections, collapsed all-done state with mauve accent wash
- Habits detail: floating glass Complete button with backdrop blur, clamping scroll physics, tighter section header spacing
- Password change UI in sync settings
- Internationalization infrastructure (gen_l10n, AppLocalizations wiring, en/es string extraction)

### Fixed
- Sync: retry loop was dead code — SyncEngine converted network errors into Ok(result) so retries never fired. Now inspects result.error_kind and retries transient errors (3×2s)
- Sync: epoch keys never persisted across app restart — Dart seed allow-list excluded dynamic epoch_key_* entries. Now scans keychain via readAll() and restores all epoch keys on startup
- Sync: push used stored op epoch instead of current group epoch, causing relay rejection after rekey. Now reads sync_metadata.current_epoch at push time
- Sync: drain-after-revoke credential resurrection — defense-in-depth with monotonic generation token, per-write shouldAbort checks, and post-revoke re-cleanup timer
- Sync: device_revoked metadata lost when engine wrapped relay errors — error_code and remote_wipe now propagated through SyncResult end-to-end
- Sync: local engine/storage errors misclassified as retryable Network — now classified as Protocol (non-retryable)
- Chat: missing foundation.dart import for kReleaseMode in GIF picker
- iOS: export compliance declaration, exclude DB from iCloud backup
- Android: explicit minSdk declaration
- Accessibility: habits midnight invalidation on resume, blur popup semantics, popup menu tooltip defaults
- Performance: cached parsed markdown spans in MarkdownEditingController for notes

### Changed
- Sync: reqwest client now uses connect_timeout(10s), pool_idle_timeout(90s), tcp_keepalive(60s)
- Sync: triggerSync() wired to app onResume lifecycle (was defined but never called)
- Sync: event-driven drain on SyncCompleted/EpochRotated events with 500ms trailing debounce
- Sync: SecureStore trait extended with snapshot() method for dynamic key enumeration
- App store submission audit and remediation (privacy manifests, security config)

## [0.2.13] - 2026-04-09

### Added
- GIF search and sharing in chat via Klipy API (ex-Tenor team, free REST API)
- GIF picker sheet with masonry grid, debounced search, trending GIFs, and Klipy attribution
- GIF preview overlay with confirm-before-send to prevent mistaps
- GIF bubble in message bubbles using hardware-decoded MP4 playback (video_player)
- Reduced motion support: static preview with play button overlay for GIF bubbles
- Privacy toggle: disable GIF search in Settings → Chat (syncs via CRDT)
- URL validation allowlist for Klipy/Tenor CDN domains on synced GIF URLs
- Visibility-based lifecycle management: off-screen GIF videos pause automatically
- Schema v38 migration adding `gif_search_enabled` column to system_settings
- 50 new tests covering Klipy service, providers, picker widget, bubble, migration, and settings

### Fixed
- GIF search enabled setting now syncs between devices (was missing from sync adapter)

## [0.2.12] - 2026-04-09

### Added
- Voice note recording and playback in chat — tap mic button to record, send encrypted OGG audio
- Voice recorder widget with live waveform visualization and elapsed time display
- Voice playback with play/pause, seek, and speed cycling (1x/1.5x/2x) in message bubbles
- Microphone permissions for iOS, Android, and macOS (sandbox entitlements included)
- `prepareVoiceNote` and `uploadVoice` methods on MediaService for encrypted voice upload
- 59 new tests covering waveform normalization, recording/playback state machines, and voice bubble widget

### Fixed
- Voice bubbles no longer rebuild all visible bubbles on every playback position tick (uses Riverpod `.select()`)
- Voice playback AudioPlayer and stream subscriptions now clean up via `ref.onDispose`
- Amplitude sample collection during recording no longer creates O(n²) list copies
- Voice note send reorders attachment prep before message creation to prevent orphaned empty bubbles on failure

## [0.2.11] - 2026-04-03

### Changed
- Snapshot encryption now uses AAD binding (sync_id, device_id, epoch, server_seq_at) and Ed25519 signatures, preventing metadata forgery on bootstrap
- Sync database (prism_sync.db) encrypted at rest via SQLCipher with automatic plaintext-to-encrypted migration
- Push, snapshot upload, and ack relay routes now require Ed25519 signed requests (previously bearer token only)
- SignedBatchEnvelope byte fields serialize as base64 strings instead of integer arrays (3x size reduction for snapshots)
- Device ID validation rejects pipe characters to prevent AAD field confusion

### Added
- Secure display protection (FLAG_SECURE on Android, secure text field on iOS) for mnemonic, pairing QR, and approval QR screens
- ScreenSecurityService with ref-counted enable/disable for platform secure display
- SecureScope widget combining secure display + post-capture screenshot warnings
- Snapshot bootstrap verifies sender signature and checks relay-reported epoch matches signed epoch
- Migration backup safety: plaintext DB preserved as .bak until encrypted copy verified

## [0.2.10] - 2026-04-03

### Changed
- Warm parchment/charcoal color palette replacing cool neutral grays across all theme variants (standard light, dark, OLED, Material You unchanged)
- Brand accent shifted from saturated purple (#AF8EE9) to warm desaturated mauve (#B498C2 dark, #A384B0 light)
- Fronting status colors now brightness-aware using muted accent spectrum (purple, rose, sage)
- All ~660 Material Icons replaced with Phosphor Icons via centralized AppIcons mapping
- EmptyState, PrismSection, and onboarding headers now use Unbounded display font
- EmptyState widget accepts Widget icon parameter (was IconData) for duotone icon support

### Added
- Unbounded display font (weights 700, 800) bundled as app assets
- phosphor_flutter package with duotone variant support for feature/display icons
- AppIcons centralized icon mapping with three tiers: navigation (regular), action (regular), feature (duotone)
- Full feature accent spectrum constants (purple, rose, sage, blue, amber, lavender) with dark/light variants
- Semantic warm color constants (warmWhite, warmBlack, warmOffWhite, parchment, charcoal families)
- OLED warm-tinted surface constants (oledSurface1-4)
- Named muted text color constants matching design guide alpha values

### Removed
- cupertino_icons dependency (zero references found)
- All Material Icons references

## [0.2.9] - 2026-04-02

### Changed
- Consolidated animation timing constants into `Anim` with t-shirt sizing (`xs`/`sm`/`md`/`lg`), removed duplicates from `PrismTokens`
- Migrated 11 settings screens from full `systemSettingsProvider` watch to narrow providers, reducing unnecessary widget rebuilds
- Narrowed nav bar tab providers to only watch feature flags and nav item lists
- Refactored `AppShellTab.isEnabled` to accept a feature flags record instead of full `SystemSettings`

### Fixed
- Poll export no longer includes options/votes from soft-deleted polls (was creating orphaned rows on restore)
- PIN lock settings screen shows loading state until settings resolve, preventing false-off toggle on cold start
- SharedPreferences flag ordering preserved so one-time enum migration retries on transient failure

### Added
- 16 narrow Riverpod settings providers for granular rebuild control
- `featureFlagsProvider` grouped record for feature toggle screens and nav bar filtering
- Batch `getAllVotes()` and `getAllVotesGroupedByOption()` poll repository methods
- `getAllOptionsGroupedByPoll()` poll repository method for efficient export

## [0.2.7] - 2026-03-28

### Added
- Prism export import during onboarding — pick a `.json` or encrypted `.prism` file, preview data counts, and restore directly into a fresh install
- Shared `OnboardingDataReadyView` widget used by both device pairing and Prism export import flows
- `completeImportedBootstrap()` fast-path that marks onboarding complete without re-running full setup
- Error handling on import completion with toast feedback

### Changed
- Refactored `_WelcomeBackView` (sync device step) into reusable `OnboardingDataReadyView`

## [0.2.6] - 2026-03-28

### Fixed
- `endSleep()` now validates the session is actually a sleep session before ending it (consistency with `deleteSleep()`)
- Fake repository `getActiveSessions()` now correctly filters by session type to match real DAO behavior
- Data export crash from broken variable reference after sleep session unification
- Member index `idx_sessions_member_deleted_start` updated to include `session_type` for efficient filtered queries
- Export service now uses targeted queries instead of fetching all sessions and filtering in-memory

### Added
- Session type boundary tests: cross-type overlap ignored, trimOverlap no-op across types, mergeAdjacent skip for sleep
- Sleep mutation tests: startSleep ends prior sleep, endSleep/updateSleepQuality/deleteSleep happy + error paths, splitSession preserves sleep fields

## [0.2.5] - 2026-03-27

### Added
- **Documentation site:** Full docs site with Eleventy — getting started, members, fronting, communication, tracking, sync & devices, FAQ, troubleshooting, philosophy, and self-hosting stub pages
- **PIN security upgrade:** PIN hashing migrated from SHA-256 to Argon2id with automatic legacy migration on first unlock
- **Conversation CRDT precision:** Targeted field-level update methods for conversations — archive, mute, participants, and read timestamps now emit single-field CRDT ops instead of full-row writes
- **Chat mutation serialization:** Pool(1) serializes toggleReaction, editMessage, and deleteMessage to prevent read-modify-write race conditions

### Changed
- **Sync performance:** Remote changes now applied in chunked transactions (batches of 20) instead of individual sequential writes, reducing WAL commits
- **Timeline rendering:** Grid lines, alternating columns, now-line, and session bars are viewport-culled — only visible elements are painted
- **Export performance:** Custom field values exported via single batch query instead of O(n*m) individual lookups
- **Router performance:** Onboarding redirect uses COUNT query instead of loading all member objects
- **Migration warnings:** Failed avatar downloads are now surfaced in import result warnings instead of silently skipped
- **Relay deployment:** Migrated from DigitalOcean to Hetzner CAX31 ARM64
- **Site design:** Warmer tone, 3D phone mockup hero, glassmorphic download badges, cursor-tracking specular highlights, responsive navigation

### Fixed
- Habits stuck as completed on day change — date-dependent providers now invalidate at midnight
- Chat edit dialog closing chat screen behind it + double-submit on save
- Poll vote-as defaulting to first member instead of current fronter
- Poll results visible before any system member has voted
- Delete session dialog missing cancel button + 9 raw dialogs migrated to PrismDialog
- Tooltip instant-open on desktop + pill-shaped borders on multi-line text fields
- Notification screen layout + about screen missing back button
- SharedPreferences flag ordering in one-time sync migration
- SP API token not cleared on dispose
- Removed fragile microtask yield before sync auto-configure
- Always-on database encryption at rest (Signal model)

## [0.2.4] - 2026-03-25

### Changed
- **Relay metadata minimization:** Removed device permissions, enrollment invitations table, epoch numbers from URLs, and X-Epoch headers from the relay protocol. The relay no longer stores device permission levels and leaks less metadata about key rotation timing.
- **Wipe status embedded in auth response:** Removed the unauthenticated `/wipe-status` endpoint. Wipe status is now returned in the 401 response body when a revoked device authenticates, eliminating a public information disclosure vector.
- **WebSocket auth hardened:** WebSocket authentication now checks device active status, preventing revoked devices from maintaining connections and receiving notification metadata.
- **Rekey artifact lookup:** Epoch passed as query parameter instead of URL path segment, preserving correctness during concurrent epoch rotations while keeping epoch out of the URL.

### Removed
- Unauthenticated `/wipe-status` endpoint (replaced by 401 response body)
- `Permission` enum and server-side permission enforcement from relay
- `enrollment_invitations` table and related dead code
- `X-Epoch` request/response headers from push, pull, and snapshot endpoints

## [0.2.3] - 2026-03-24

### Changed
- **Features list polish:** Removed subtitle text from feature rows in Settings > Features. Enabled features now show an accent-colored status dot instead. Cleaner, less visual clutter.
- **Feature detail descriptions:** Upgraded description text from `bodyMedium` to `bodyLarge` with more breathing room, so feature descriptions feel intentional rather than cramped.

## [0.2.2] - 2026-03-24

### Changed
- **Features settings rework:** All features now navigate to their own settings subview instead of mixing inline toggles with tappable rows. Removed the "Features with settings" / "Other features" labels — the list is now a single flat view with consistent Enabled/Disabled status on each row.
- **Sleep and Reminders moved to Features:** Sleep settings and Reminders moved from the main Settings > App section into Settings > Features, giving each its own subview with toggle and options.
- **Sleep toggle bug fixed:** The sleep tracking toggle now persists correctly across app restarts (was previously using an ephemeral in-memory provider that reset on every launch).
- **PrismSection empty title:** Section headers no longer render invisible whitespace when given an empty title.

### Added
- **Polls feature settings screen:** Dedicated subview with enable/disable toggle and description.
- **Notes feature settings screen:** Dedicated subview with enable/disable toggle and description.
- **Sleep feature settings screen:** Rebuilt with proper Material pattern — toggle plus radio picker for default quality (matching the Fronting quick switch pattern).
- **Reminders feature settings screen:** Toggle plus "Manage Reminders" link to the existing reminders CRUD screen.

## [0.2.1] - 2026-03-23

### Added
- **Simply Plural API import:** Import data directly from your SP account by pasting an API token — no file export needed. Two-path choice on import screen: API (recommended) or file.
- **Reset & re-import:** "Start Fresh" option for users who imported SP data earlier but kept using SP. Clears existing data atomically within the import transaction, so a failed import rolls back everything.
- **Chat channel import via API:** API import now fetches chat channels and messages (previously only available via file export).

### Fixed
- **SP file import parser bugs:** Fixed key-name mismatches with real SP exports — custom fronts (`frontStatuses`), chat messages (`chatMessages` flat list), automated reminders, and repeated reminders were all silently dropped. Now handles both old and new export formats.
- **Start Fresh transaction safety:** Data clearing now runs inside the same database transaction as the import. If import fails, no data is lost.

## [0.2.0] - 2026-03-23

### Added
- **Epoch key in device pairing (MLS Welcome pattern):** New devices joining after epoch rotation now receive the current epoch key in the invite payload. Follows MLS RFC 9420 Welcome semantics — inviting device wraps the current epoch secret for the joining device. Previously, new devices paired after a key rotation could not sync.
- **Remote wipe request:** When revoking a device, toggle "Request remote data wipe" in the confirmation dialog. If the revoked device is online, it erases its sync data. Explicitly messaged as a request, not a guarantee (matching Apple's Remove vs Erase UX).
- **Epoch state management:** Single `advance_epoch()` helper keeps runtime epoch, storage, secure store, and OpEmitter in sync. Eliminates epoch drift that caused mismatch errors.
- **Epoch key drain through FFI:** Rotated/recovered epoch keys are now exported via `drain_secure_store()` so mobile keychains persist them across restarts.

### Fixed
- **Snapshot targeting for device pairing:** Pre-generate a device ID for the joining device in the invite, so the pairing snapshot is targeted to the correct device. Prevents other devices from consuming the snapshot before the intended device can download it.
- **Atomic epoch rotation (MLS-style):** Epoch only advances during `post_rekey` (with wrapped key distribution), not during `revoke_device`. Fixes double-increment bug causing "Rekey epoch must be current_epoch + 1" errors.
- **Stale epoch fallback removed:** Invite creation fails closed if the sync engine isn't configured, instead of silently using a stale epoch cache.
- **Stale invitation rejection:** Relay now rejects invitations whose signed epoch doesn't match the current group epoch, preventing lagging devices from creating invalid invites.
- **Revoked device background sync:** Revoked devices now properly stop background sync and clear credentials instead of repeatedly hitting the relay with 401 errors.
- **Pairing data race:** Sync event stream listener activated before snapshot bootstrap, ensuring all 123+ bootstrapped entities are written to Drift before the count check runs.

### Changed
- **Compact invite format v0x04:** Adds `current_epoch` (4 bytes) and `epoch_key` (0 or 32 bytes) to the QR/URL payload. Backward-compatible with v0x02/v0x03 invites (parsed as epoch 0).
- **Invitation signing data:** Now includes `current_epoch` and `epoch_key`, preventing epoch tampering in invites.

## [0.1.8] - 2026-03-22

### Added
- **Chat tab badge:** Unread conversation count badge on the Chat nav tab (both mobile floating bar and desktop sidebar), with accessibility label.
- **Per-conversation unread count:** Conversation tiles now show a numbered badge instead of a simple dot for unread messages.
- **@mention system:** Type `@` in the message input to trigger a glassmorphism autocomplete overlay showing conversation participants, filterable by name. Supports keyboard navigation (arrow keys + Enter/Tab) on desktop and tap on mobile.
- **Mention rendering:** `@[uuid]` tokens in messages render as `@Name` with the mentioned member's custom color and bold weight. Conversation tile previews also resolve mentions to names.
- **Badge preference:** Per-member badge preference toggle in the Chat screen header — choose between "all messages" (default) and "mentions only" to reduce notification noise.
- **`chatBadgePreferences`:** New synced field on system_settings (schema v29) storing per-member badge mode as a JSON map.

### Changed
- **Batch unread queries:** All conversation unread counts use a single UNION ALL SQL query instead of one stream per tile, avoiding N re-queries on every message write.
- **Mention trigger detection:** Extracted as a pure `detectMentionTrigger()` function for testability.
- **Shared member name map:** `memberNameMapProvider` computes the member ID → name map once, shared across all conversation tile previews.

## [0.1.7] - 2026-03-21

### Added
- **Inline note editor:** Redesigned the note creation/edit sheet from a form-style layout to an Apple Notes-style inline editor with borderless title and body fields, automatic date, and a save checkmark in the top bar.
- **Inline markdown styling:** Body field renders `**bold**`, `*italic*`, `__underline__`, `# heading`, `## subheading`, and `---` with live syntax highlighting while typing via custom `MarkdownEditingController`.
- **Headmate selector in notes:** Optional member chip in the bottom toolbar lets users associate any note with a headmate, even from the global notes list.
- **Member selection sheet:** New `MemberSelectSheet` widget for compact member selection in bottom sheets.

### Changed
- **Note validation relaxed:** Notes now require title OR body (was: both required), allowing quick body-only notes.
- **Empty-title fallback:** Note cards and detail screen show the first line of the body (italic) when no title is set, or "Untitled" if both are empty.
- **Discard protection:** Swiping down on a dirty note editor now shows a confirmation dialog instead of silently discarding changes.

## [0.1.6] - 2026-03-21

### Added
- **Configurable nav bar:** Users can choose which features appear as top-level tabs via Settings > Navigation. Supports adding Members, Reminders, Notes, and Statistics as first-class tabs.
- **"More" overflow on mobile:** When more than 5 tabs are configured, a compact vertical-dots trigger on the trailing edge expands the pill upward to reveal overflow tabs with staggered entrance animation.
- **System Information screen:** Extracted system name/description/avatar editing from settings home into its own dedicated screen (`/settings/system-info`).
- **Navigation Settings screen:** UI to add, remove, and reorder nav bar items. Home and Settings are locked in position.
- **Notes list screen:** New standalone notes list view so Notes can be promoted to a top-level tab.
- **New router branches:** Members, Reminders, Notes, and Statistics registered as `StatefulShellBranch` entries (indices 5-8) for top-level tab use.

### Changed
- **Settings home screen:** System identity card is now read-only (tappable to navigate to System Information for editing). Navigation link added to App section.
- **`navBarItems` field:** Device-local setting (not synced) — different devices can have different nav configurations.

## [0.1.5] - 2026-03-21

### Added
- **Custom fields in member editor:** `CustomFieldsEditor` widget now integrated into `AddEditMemberSheet` for both create and edit flows. Text, color, and date custom fields are editable inline when creating or editing a member.
- **`deleteValuesForMember` API:** New method through DAO → repository → provider stack for batch-deleting custom field values by member ID.

### Fixed
- **Orphaned custom field values on cancel:** When creating a new member, custom field values are saved on blur. If the user cancels without saving, orphaned values are now cleaned up in `dispose()`.

## [0.1.4] - 2026-03-21

### Added
- **PrismButton `outlined` tone:** Transparent background with visible border, for secondary actions alongside `filled` buttons.
- **PrismButton `expanded` mode:** Full-width buttons without `SizedBox(width: double.infinity)` wrappers.
- **PrismSectionCard `onTap`/`onLongPress`:** Card-level tap handling, enabling full-card highlight including banners.
- 43 new widget tests: PrismButton (all tones, expanded, density, loading, disabled), PrismSurface (ClipRRect, taps, tones), PrismSectionCard (tap forwarding), PrismDialog (custom actions).

### Changed
- **Habit cards:** Tap highlight now covers the entire card including the Task Due banner. Banner uses `TintedGlassSurface` for glass treatment. Tap target moved from inner row to outer card.
- **PrismSurface child clipping:** Children are now clipped to the border radius via `ClipRRect`, fixing overflow on banners and full-bleed content.
- **Material button migration:** Replaced `FilledButton`, `OutlinedButton`, `ElevatedButton`, and `TextButton` with `PrismButton` across 19 screens (migration, data management, PluralKit, settings, onboarding, fronting, chat, polls, sharing). Debug screens intentionally excluded.
- **Chat category picker:** Replaced `DropdownButtonFormField` with `PrismListRow` + `PrismSheet` selection pattern in conversation create and info sheets.
- **Delete dialogs:** Replaced `AlertDialog` with `PrismDialog.confirm` for conversation and message deletion.

## [0.1.3] - 2026-03-20

### Added
- **PIN/biometric lock:** SHA-256 PIN hashing with device-local salt and constant-time comparison. 4-digit numpad with shake animation and haptic feedback. Biometric unlock via local_auth. Auto-lock on app background with configurable delay (0/15/60/300/900s). Brute-force throttling (5-attempt lockout with 30s exponential backoff). Full-screen lock overlay in AppShell above all content. Privacy & Security settings screen.
- **Markdown rendering:** `MarkdownText` widget using flutter_markdown with safe link handling (http/https only), disabled images, and themed code blocks. Integrated in member bios (gated by per-member `markdownEnabled` toggle), notes (always on), group descriptions, and poll descriptions.
- **Font scaling + Open Dyslexic:** System and Open Dyslexic font family selection. Font scale slider 0.8x–1.5x (min 1.0x when Open Dyslexic active). Applied via MediaQuery textScaler and ThemeData fontFamily. Live preview in Appearance settings.
- **Reminders:** Scheduled (repeating interval + time) and front-change triggered reminders. Full data layer (table, DAO, model, mapper, repository). Reminders screen with swipe-to-delete and undo. Create/edit sheet with trigger type segmented button. Reminder scheduler service using flutter_local_notifications. Front-change listener watches active sessions and fires pending reminders. Sync rescheduler watches reminder table for remote changes. SP import mapping (automatedTimers → onFrontChange, repeatedTimers → scheduled). Feature toggle in settings.
- **PluralKit bidirectional sync:** Write endpoints on PK client (POST/PATCH member, POST switch). Rate-limited request queue (2 req/s with exponential backoff on 429). Push service for members and switches. Bidirectional orchestrator with per-member field direction config (pullOnly/pushOnly/bidirectional/disabled). Auto-push provider watching fronting sessions (30s debounce). Sync direction picker and summary card UI. Field sync config persisted in pluralkit_sync_state.fieldSyncConfig JSON column.
- **Conversation categories:** New table with full data layer. Category management sheet (reorderable, inline create/edit/delete). Chat list grouped by category with sticky headers. Category picker in conversation create/edit.
- **Poll enhancements:** Optional description field on polls rendered with markdown. Per-option color picker with 9-color palette popover.
- **System identity:** System description and avatar picker in settings screen.
- **DB schema v24:** 2 new tables (conversation_categories, reminders), 12 new columns on existing tables (polls.description, poll_options.color_hex, conversations.description/category_id/display_order, members.markdown_enabled, system_settings: systemDescription/systemAvatarData/remindersEnabled/fontScale/fontFamily/pinLockEnabled/biometricLockEnabled/autoLockDelaySeconds), pluralkit_sync_state.fieldSyncConfig, 3 new indexes.
- **Sync schema updates:** Dart sync_schema.dart and Rust sync/schema.json updated for all new synced entities and fields. Drift sync adapter handlers for conversation_categories and reminders.
- 130 new tests: PIN lock service crypto, PK request queue rate limiting, PK push service, PK bidirectional service, PK sync config models, reminder scheduler service, SP timer parsing/mapping, drift reminders repository, drift conversation categories repository, migration v24 column verification.

### Fixed
- PK rate-limit detection: replaced fragile `toString().contains('429')` with typed `error is PluralKitRateLimitError`
- N+1 query in PK auto-push and sync: batch-fetch all members instead of per-session getMemberById loop

## [0.1.2] - 2026-03-18

### Added
- Weekly progress pill on habit rows showing days completed vs required for weekly-frequency habits
- "Task Due" banner on due habit cards with inline complete button and loading state
- Weekly completions date-range provider and DAO method for tracking completions across the current week
- Accessibility labels on habit completion circles, star ratings, color picker, and weekly pills
- Empty state widget for habit detail screen when no completions exist
- Startup catch-up sync pull on cold boot to retrieve batches missed while offline
- One-time migration to re-emit enum settings fields as integers (fixes legacy string-encoded sync values)
- Sync error propagation: sync status now tracks and displays errors from completed sync cycles

### Changed
- Migrated habits views to Prism design system: PrismSurface, PrismSectionHeader, PrismButton, PrismIconButton, PrismListRow, PrismGlassIconButton replace bare Material widgets
- Habit detail stat cards use PrismSurface with accent color tinting
- Completion tiles use PrismListRow instead of ListTile
- Section headers across habits list, detail, add/edit, and complete sheets use PrismSectionHeader
- Color picker circles enlarged from 32dp to 44dp for better touch targets
- Interval +/- buttons use PrismIconButton with tooltips
- Complete habit sheet Done button uses PrismGlassIconButton matching add/edit sheet pattern
- Sync status now preserves last successful sync time on error instead of overwriting
- Sync reset reads credentials from keychain directly instead of FFI status queries
- Settings screen gradient fade refined to stay solid through status bar area

### Fixed
- Sync handle published before auto-configure to prevent race where remote changes arrive before event-stream subscription
- Message bubble highlight overlay now uses Positioned.fill to avoid layout interference
- Reply quote bar uses IntrinsicHeight to properly stretch the colored accent bar
- Emoji picker opens with isScrollControlled and keyboard inset handling for search field
