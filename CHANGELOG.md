# Changelog

All notable changes to Prism will be documented in this file.

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

## [Unreleased]

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
