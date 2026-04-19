# Prism — Flutter Cross-Platform App

## Overview
Prism is a plural system management app built with Flutter. It provides member management, fronting tracking, internal chat, polls, habits, sleep tracking, and zero-knowledge encrypted sync. Porting the existing SwiftUI (iOS/macOS) app to reach Android, web, and beyond.

**Package name:** `prism_plurality` (avoids Dart `prism` package conflict)

## Sync Engine

The Rust sync engine lives at `../sync` in the monorepo. Prism depends on it via path dependencies in `pubspec.yaml`:

```
prism_sync      → ../sync/dart/packages/prism_sync       # FFI bindings (flutter_rust_bridge)
prism_sync_drift → ../sync/dart/packages/prism_sync_drift # Drift sync adapter
prism_sync_flutter → ../sync/dart/packages/prism_sync_flutter # Flutter platform glue
```

**Rust crates:**
| Crate | Purpose |
|-------|---------|
| `prism-sync-core` | CRDT engine, sync service, pairing, device registry, relay client |
| `prism-sync-crypto` | Key hierarchy (Argon2id, XChaCha20-Poly1305), DeviceSecret, BIP39, HKDF |
| `prism-sync-ffi` | flutter_rust_bridge FFI layer — exposes all APIs to Dart |
| `prism-sync-relay` | Self-hosted relay server (Axum + SQLite + WebSockets) |

**Building Rust side:**
```bash
cd ../sync
cargo check --package prism_sync_ffi          # Check FFI compiles
cargo test --package prism-sync-core          # Run core tests (176+)
cargo test --package prism-sync-crypto        # Run crypto tests (70)
flutter_rust_bridge_codegen generate          # Regenerate Dart bindings after API changes
```

## Encryption & Key Management

### Key Hierarchy
```
PIN (6-digit) + SecretKey (BIP39 mnemonic) → Argon2id (64 MiB, 3 iterations, parallelism=1) → MEK
MEK wraps random DEK via XSalsa20-Poly1305
  DEK → HKDF-SHA256(info="epoch_sync\0", salt=epoch.to_be_bytes()) → Epoch 0 sync key (XChaCha20-Poly1305)
  DEK+DeviceSecret → HKDF-SHA256(IKM=DEK, salt=DeviceSecret, info="prism_local_storage_v2") → Local storage key (DB + media keys)
  DEK → HKDF-SHA256(info="prism_group_invite") → Group invite secret (reserved)
DeviceSecret (32 bytes, per-device CSPRNG — NOT derived from DEK)
  → HKDF-SHA256(info="prism_device_ed25519", salt=device_id) → Ed25519 signing keypair
  → HKDF-SHA256(info="prism_device_x25519", salt=device_id) → X25519 key exchange keypair
  → HKDF-SHA256(info="prism_device_ml_dsa_65", salt=device_id) → ML-DSA-65 PQ signing keypair
  → HKDF-SHA256(info="prism_device_ml_kem_768", salt=device_id, len=64) → ML-KEM-768 PQ KEM keypair
  → HKDF-SHA256(info="prism_device_xwing_rekey", salt=device_id) → X-Wing hybrid KEM keypair
```
- PIN changes = re-wrap DEK only, no data re-encryption
- SecretKey is a BIP39 12-word mnemonic (128-bit entropy)
- Later epoch keys (>0) delivered via X-Wing KEM during device revocation/rekeying
- Batch signatures use hybrid Ed25519 + ML-DSA-65 (protocol V3)

### Signal-Style Key Persistence (IMPORTANT)
On first setup, the raw DEK is cached in the platform keychain (`prism_sync.runtime_dek`) so subsequent app launches bypass the expensive Argon2id derivation. The Rust FFI provides:
- `restoreRuntimeKeys(handle, dek, deviceSecret)` — fast restore from keychain
- `exportDek(handle)` — export raw DEK after first unlock for caching
- `ffi.unlock(handle, pin, secretKey)` — full Argon2id path (fallback only; `pin` is the 6-digit PIN string)

### Secure Storage Configuration
**All sync credentials use a centralized `FlutterSecureStorage` instance** defined in `lib/core/services/secure_storage.dart`:
- iOS: `KeychainAccessibility.first_unlock_this_device` (background sync compatible, device-bound, no iCloud backup)
- Android: default Keystore (`resetOnError: true`)
- **Never use bare `FlutterSecureStorage()`** — always use the `secureStorage` constant from `secure_storage.dart`

**iOS fresh-install guard:** `clearKeychainIfFreshInstall()` in `main.dart` uses `SharedPreferences` to detect reinstalls and wipe stale keychain data (iOS Keychain persists across uninstall/reinstall).

### Keychain Keys (all prefixed `prism_sync.`)
| Key | Content | Written by |
|-----|---------|-----------|
| `sync_id` | base64(sync group ID) | Dart (setup/pairing) + Rust (drain) |
| `relay_url` | base64(relay URL) | Dart (setup/pairing) + Rust (drain) |
| `device_id` | base64(12-char hex node ID) | Rust (drain) |
| `device_secret` | base64(32-byte secret) | Rust (drain) |
| `wrapped_dek` | base64(encrypted DEK) | Rust (drain) |
| `dek_salt` | base64(Argon2id salt) | Rust (drain) |
| `session_token` | base64(auth token) | Rust (drain) |
| `epoch` | base64(epoch counter) | Rust (drain) |
| `runtime_dek` | base64(raw 32-byte DEK) | Dart (`cacheRuntimeKeys`) |
| `biometric_dek` | base64(raw 32-byte DEK, biometric-gated) | Dart (`BiometricService.enroll`) |

### Sync Health System
`SyncHealthState` enum tracks sync credential health:
- `healthy` — sync configured and working (or not paired)
- `needsPassword` — `runtime_dek` missing but `wrapped_dek` exists (shows `SyncPinSheet` PIN prompt via `AppShell` listener)
- `disconnected` — credentials wiped or device revoked (shows reconnect card in sync settings)

`DeviceRevoked` events from the relay WebSocket automatically transition to `disconnected`.

## Sync Architecture
- CRDT with Hybrid Logical Clocks (HLC): `timestamp:counter:nodeId`
- Field-level Last-Write-Wins merge, HLC comparison with nodeId tiebreaker
- Mutation-time op emission into `pending_ops`, grouped by `local_batch_id`
- Snapshot bootstrap for first sync / pairing, then incremental pull / push
- Startup / resume catch-up sync plus WebSocket notifications
- Pluggable relay interface — current implementation: self-hosted Rust relay
- Zero-knowledge: server stores only encrypted blobs, no user accounts
- Pull → decrypt → merge → push → mark clean cycle
- **Session tokens are permanent** (no TTL, no refresh). If lost, device must re-pair.
- `drainRustStore(handle)` persists Rust MemorySecureStore → platform keychain after state-changing ops
- `_seedRustStore(handle)` restores keychain → Rust MemorySecureStore on startup

### Second-Boot Startup Flow
```
main() → clearKeychainIfFreshInstall() → RustLib.init()
  ↓
PrismSyncHandleNotifier.build()
  ├─ Read sync_id + relay_url from keychain
  ├─ If both exist → createHandle(relayUrl)
  │   ├─ createPrismSync(relayUrl, dbPath)
  │   ├─ _seedRustStore(handle) — restore keychain → Rust
  │   ├─ _autoConfigureIfReady(handle) → SyncHealthState
  │   │   ├─ runtime_dek exists? → restoreRuntimeKeys → configureEngine → healthy
  │   │   ├─ wrapped_dek exists? → needsPassword (user prompted)
  │   │   └─ nothing? → disconnected
  │   └─ ref.read(syncHealthProvider.notifier).setState(health)
  └─ If missing → return null (not paired)
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Flutter (iOS, Android, macOS, web) |
| State | Riverpod (hand-written providers, NOT `@riverpod` codegen) |
| Database | Drift + SQLite (`sqlite3_flutter_libs`) |
| Models | freezed + json_serializable |
| Navigation | go_router with StatefulShellRoute |
| Crypto | Rust `prism-sync-crypto` (XChaCha20-Poly1305, X25519, Argon2id, HKDF) |
| Sync | Rust `prism-sync-core` (CRDT, HLC, relay client) via FFI |
| Backend | Self-hosted Rust relay (Axum + SQLite + WebSockets) |
| Background | workmanager |
| Theme | Material 3 with dynamic_color (Material You) |
| Secure Storage | flutter_secure_storage v10 (iOS Keychain / Android Keystore) |

**Dart SDK:** `^3.11.1`

## Build Commands
```bash
flutter pub get                                          # Install deps
dart run build_runner build --delete-conflicting-outputs  # Code gen (freezed, drift, json)
dart run build_runner watch --delete-conflicting-outputs  # Watch mode during dev
flutter build ios / apk / macos                          # Build
flutter analyze                                          # Lint
flutter test                                             # Tests
```

## Feature Plans

Active plans live in `docs/plans/` when present. Completed plans are archived to git history (see
root `CLAUDE.md` "Documentation Lifecycle").

## Performance Docs

- `../docs/guides/flutter-performance-and-size-audit-guide.md`

## Project Structure
```
lib/
├── main.dart                    # Entry point (Rust init, keychain guard, workmanager)
├── app.dart                     # MaterialApp.router with DynamicColorBuilder
├── core/                        # Infrastructure
│   ├── constants/               # AppConstants (default relay URL, etc.)
│   ├── database/                # Drift DB, DAOs (13), tables (17), providers
│   ├── router/                  # go_router config (StatefulShellRoute, 5 tabs)
│   ├── services/                # Notifications, validation, error reporting
│   │   ├── secure_storage.dart  # Centralized FlutterSecureStorage config (USE THIS)
│   │   └── prism_secure_store.dart  # Bridges SecureStore interface → keychain
│   ├── sharing/                 # Friend models, invite system, sharing service
│   └── sync/                    # Dart-side sync integration
│       ├── prism_sync_providers.dart  # Core: handle, health, status, seed/drain, providers
│       ├── sync_event_loop.dart       # SyncEvent stream from Rust FFI
│       ├── drift_sync_adapter.dart    # Applies remote changes to Drift DB
│       └── sync_schema.dart           # Entity schema for CRDT sync
├── domain/                      # Pure Dart (no Flutter imports)
│   ├── models/                  # Freezed immutable models (12+)
│   └── repositories/            # Abstract interfaces (9)
├── data/                        # Repository implementations
│   ├── repositories/            # Drift-backed repos
│   └── mappers/                 # DB row ↔ domain model converters
├── features/                    # Feature modules (11)
│   ├── fronting/                # Home tab: sessions, quick front, sleep, gaps, comments
│   ├── chat/                    # Conversations, messages, reactions
│   ├── habits/                  # Habit tracking with streaks
│   ├── polls/                   # Voting system
│   ├── members/                 # Member CRUD, profiles, notes
│   ├── settings/                # Appearance, sync, privacy, debug, analytics
│   │   ├── widgets/sync_password_sheet.dart   # Password prompt for DEK recovery
│   │   ├── widgets/setup_device_sheet.dart     # Pair another device (createInvite)
│   │   ├── views/sync_settings_screen.dart     # Sync config, status, health states
│   │   └── providers/reset_data_provider.dart  # Full sync/data reset
│   ├── onboarding/              # First-launch setup flow (8 steps + sync device pairing)
│   ├── migration/               # Simply Plural JSON import
│   ├── pluralkit/               # PluralKit API sync
│   ├── data_management/         # Import/export (V3 format)
│   └── sharing/                 # Friend links, permission-scoped sharing
└── shared/                      # Reusable across features
    ├── theme/                   # AppTheme (4 variants), AppColors
    ├── widgets/                 # See "Reusable Widgets" below
    │   └── app_shell.dart       # Nav shell + sync health listener
    ├── extensions/              # DateTime, Duration helpers
    └── utils/                   # Common utilities
```

## Architecture Patterns

### Data Flow
```
Drift Tables → DAOs → Repositories (abstract) → Mappers → Freezed Models → Riverpod Providers → Widgets
```

- **Domain-driven**: `domain/` has pure Dart models + repository interfaces with no Flutter imports
- **Repository pattern**: `data/` implements abstract repos using Drift DAOs
- **Mapper pattern**: `data/mappers/` convert between DB rows and domain models
- **Riverpod providers**: Features expose `StreamProvider` for reactive UI, `Notifier` for mutations
- **CRDT sync**: entity rows track `hlc`/`isDirty`; V2 sync uses `pending_ops`, `applied_ops`, `field_versions`, `sync_metadata`

### Riverpod Conventions
- **Hand-written providers only** — no `@riverpod` codegen, no `riverpod_generator`
- `StreamProvider` for watched/reactive data (members list, active sessions, conversations)
- `AsyncNotifierProvider` / `NotifierProvider` for state with mutations
- `Provider.family` for parameterized queries (member by ID, session by ID)
- `ref.invalidate()` after mutations to refresh dependent providers

### Navigation (go_router)
```
/ (StatefulShellRoute — 5 tabs with IndexedStack)
├── / (Home — Fronting)        ├── /chat           ├── /habits
│   └── session/:id            │   └── :id          │   └── :id
│       └── edit               │       └── info
├── /polls                     └── /settings
│   └── :id                        ├── members, appearance, sync, sleep
                                   ├── notifications, analytics, debug, errors
                                   ├── migration, pluralkit, features
                                   ├── import-export, sharing, data-browser
                                   └── encryption-info, sync-troubleshooting
/onboarding (full-screen)
/secret-key-setup (full-screen)
/sync-setup (full-screen)
```

- 5 navigator keys for tab isolation
- Onboarding redirect notifier watches settings
- Modal sheets for create/edit flows (not push navigation)
- `parentNavigatorKey` for full-screen overlays
- `PrismSheet.show()` for consistent modal bottom sheets

## Theme System

**Two-axis theming:** `ThemeBrightness` (system/light/dark) × `ThemeStyle` (standard/oled/materialYou)

| Style | Description |
|-------|------------|
| Standard | Seed-based Material 3 with custom accent |
| OLED | Pure black (#000000) backgrounds for battery savings |
| Material You | Dynamic system palette via `DynamicColorBuilder` |

- Brand color: `#AF8EE9` (Prism Purple)
- All letter spacing stripped from text styles
- Custom switch, button, input, FAB themes
- When Material You is active, accent color comes from system palette; previous custom color saved/restored on style switch
- Nav bar uses `Theme.of(context).colorScheme.primary` (not settings) so it reflects any active theme

## Reusable Widgets (`shared/widgets/`)

| Widget | Purpose |
|--------|---------|
| `AppShell` | Main nav shell with frosted glass floating bottom bar (5 tabs). Also listens to `syncHealthProvider` to show password sheet. |
| `PrismSheet` | Styled bottom sheet wrapper. Use `PrismSheet.show()` for all modal sheets. |
| `GlassSurface` | Frosted glass effect (BackdropFilter + blur) for circles and rects. Adapts to light/dark/OLED. |
| `MemberAvatar` | Circular avatar — shows image if available, falls back to emoji in `GlassSurface` circle with tinted color |
| `BlurPopupAnchor` | Frosted glass popup overlay with trigger modes: tap, longPress, manual. Used for context menus. |
| `PrismButton` | Styled button with `tone` (filled/subtle/destructive), `isLoading` spinner, theme primary/error colors |
| `PrismIconButton` | Circle icon button with `AnimatedScale` press feedback, supports `onLongPress` and `tooltip` |
| `EmptyState` | Placeholder for empty lists with icon, title, subtitle, optional action button |
| `HeadmatePicker` | Member selection dialog |
| `MemberCard` | Member profile card |
| `InfoBanner` | Info notification banner (not dismissable) |
| `PrismSurface` | Styled surface container |

## Database (Drift)
- 19 tables: app data tables (members, fronting_sessions, conversations, chat_messages, system_settings, polls, poll_options, poll_votes, sleep_sessions, habits, habit_completions, member_groups, member_group_entries, custom_fields, custom_field_values, notes, front_session_comments, pluralkit_sync_state, sync_quarantine)
- 16 DAOs with generated code
- Every entity table has: `id`, `createdAt`, `modifiedAt`, `hlc`, `isDirty`, `isDeleted`
- Stream-based watch methods for reactive UI
- Migrations via `onUpgrade` with version-specific `addColumn`/schema changes

## Key Conventions
- All domain models use `@freezed` with `@JsonSerializable`
- Generated files: `*.g.dart` (json/drift), `*.freezed.dart` (freezed)
- Feature modules follow `/providers/`, `/views/`, `/widgets/` structure
- Modal sheets via `PrismSheet.show()` for create/edit, push navigation for detail views
- `SliverAppBar` with `backgroundColor: Colors.transparent` in all tabs
- `PrismIconButton` for all app bar action buttons (circle + scale feedback)
- `NavBarInset.of(context)` for bottom padding to clear floating nav bar
- Empty states use shared `EmptyState` widget
- `BlurPopupAnchor` for context menus (not PopupMenuButton)
- Accent color from `Theme.of(context).colorScheme.primary` (not from settings directly)
- **Never use bare `FlutterSecureStorage()`** — use `secureStorage` from `core/services/secure_storage.dart`

## Voice Notes
- Voice-note services now live under `lib/features/chat/services/voice/`
- Keep recording and playback split into focused backends:
  - `VoiceRecorderBackend` / `MobileVoiceRecorderBackend`
  - `VoicePlaybackBackend` / `MobileVoicePlaybackBackend`
- New voice notes are validated and stored as `audio/ogg`
- Android records Ogg Opus directly; iOS records CAF Opus, shows a brief preparing state, then remuxes to Ogg before send
- Playback uses decrypted bytes in memory through the SoLoud backend; do not reintroduce the old `.m4a` temp-file playback path
- Current voice-note support is mobile-first: iOS and Android are supported, while unsupported platforms surface a disabled/unsupported recorder state
- `ogg_caf_converter` uses a local path override (`../../ogg_caf_converter`); `flutter_soloud` uses the published package

## Testing
- Crypto tests in `test/` (key hierarchy, encryption, secure storage)
- In-memory database for isolated tests
- `flutter test` to run all tests
- 3 pre-existing flaky widget tests (prism_toast, prism_list_row, prism_top_bar)

## Dependencies (Key)
```
flutter_riverpod, go_router                    # State + nav
drift, sqlite3_flutter_libs                    # Database
freezed_annotation, json_annotation            # Models
flutter_secure_storage, shared_preferences     # Secure storage + fresh-install detection
prism_sync, prism_sync_drift, prism_sync_flutter  # Rust sync engine (path deps)
flutter_rust_bridge                            # FFI bridge to Rust
http, uuid, intl, path_provider, path          # Utils
image_picker, file_picker                      # Media
flutter_local_notifications, workmanager       # Background
dynamic_color, flutter_colorpicker             # Theme
bip39, qr_flutter, share_plus                  # Features
collection, flutter_animate, cupertino_icons   # Misc
```

Dev: `build_runner`, `freezed`, `json_serializable`, `drift_dev`, `flutter_lints`

## Known Issues / Remaining Work
See `TODOS.md` for tracked work. Audit findings from the onboarding/sync audit are all resolved — see `AUDIT_REMAINING.md` in git history for details.
