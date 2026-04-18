# Changelog

All notable changes to Prism will be documented in this file.

## [Unreleased]

### Added
- PluralKit sync now supports linking existing members via a new mapping screen, two-way field sync for `displayName` and `birthday`, proxy tag pull, and switch history push to PluralKit

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
- **Zero-knowledge metadata minimization:** Removed device permissions, enrollment invitations table, epoch numbers from URLs, and X-Epoch headers from the relay protocol. The relay now has zero knowledge of device permission levels and leaks less metadata about key rotation timing.
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
