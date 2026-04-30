# Prism

A plural system management app built with Flutter. Track who's fronting, chat between
headmates, build habits together, and sync everything across devices with end-to-end
encryption.

Built by a plural system, for plural systems.

## What It Does

- **Fronting** — quick-switch who's in front, co-fronting, session history, gap detection
- **Chat** — conversations between headmates with reactions, GIFs, voice notes, and @mentions
- **Members** — profiles with avatars, pronouns, emoji, custom colors, and custom fields
- **Habits** — shared habit tracking with streaks and daily check-ins
- **Polls** — anonymous or open voting with expiration
- **Sleep** — sleep/wake tracking integrated into the fronting timeline
- **Notes** — per-member or shared notes with inline markdown
- **Analytics** — fronting stats, activity charts, and co-fronting patterns
- **Encrypted Sync** — end-to-end encrypted CRDT sync across devices via a self-hosted relay
- **Simply Plural Import** — migrate your data from SP exports or the SP API
- **PluralKit Sync** — bidirectional sync with PluralKit via their API

Everything is local-first. Sync is optional, self-hosted, and end-to-end encrypted — the
relay server stores only encrypted blobs and never sees your data.

## Screenshots

<!-- TODO: add screenshots -->

## Getting Started

### Requirements

- Flutter SDK (Dart `^3.11.1`)
- Rust toolchain (for the sync engine)

### Build

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

The sync engine is a Rust library ([prism-sync](https://github.com/prismplural/prism-sync))
included via path dependencies. See the sync repo for build instructions if you need to
modify the Rust side.

### Running your own relay

Sync is optional. If you want it, you can use a shared community relay or host your
own — the relay only ever sees encrypted blobs. See the
[self-hosting guide](https://github.com/prismplural/prism-sync/blob/main/self-host/SELF-HOSTING.md)
in the sync repo (Docker Compose and Kubernetes manifests included). Once it's up,
point the app at your relay URL in Settings → Sync.

### Test

```bash
flutter test
```

680+ tests covering database operations, domain logic, sync integration, and widget behavior.

## Architecture

### Structure

```
lib/
├── core/           # Database (Drift), sync integration, router, services
├── domain/         # Pure Dart models (freezed) and repository interfaces
├── data/           # Repository implementations and DB↔model mappers
├── features/       # Feature modules (fronting, chat, habits, polls, ...)
└── shared/         # Design system widgets, theme, extensions
```

Domain-driven: `domain/` holds pure Dart models and repository interfaces with no Flutter
imports. `data/` implements those interfaces against Drift. Features consume repositories
via Riverpod providers and never touch the database directly.

### Key Libraries

| Layer | Library | Why |
|-------|---------|-----|
| UI | Flutter (Material 3) | Cross-platform: iOS, Android, macOS, web |
| Dynamic color | dynamic_color | Material You / system palette on Android 12+ |
| State | Riverpod | Scoped, testable reactive state; hand-written providers only |
| Database | Drift + SQLite | Typesafe queries, codegen DAOs, stream-based reactivity |
| Models | freezed + json_serializable | Immutable value types with copy/equality/JSON |
| Navigation | go_router | Declarative routing, StatefulShellRoute for tab isolation |
| Sync | prism-sync (Rust, via FFI) | CRDT engine, E2E encryption, relay protocol |
| Secure storage | flutter_secure_storage | Platform Keychain (iOS) / Keystore (Android) |
| Background | workmanager | Periodic background sync |

### Data Flow

```
Drift Tables → DAOs → Repositories → Mappers → Freezed Models → Riverpod Providers → Widgets
```

Mutations go through repositories, which emit CRDT ops to the sync engine. The sync engine
merges remote changes back into Drift via a diff-based adapter. The relay server stores only
encrypted blobs and is never trusted with plaintext.

### Sync

Sync is provided by [prism-sync](https://github.com/prismplural/prism-sync), a Rust library
linked via `flutter_rust_bridge` FFI. It handles:

- Field-level Last-Write-Wins CRDTs with Hybrid Logical Clocks
- XChaCha20-Poly1305 encryption keyed from Argon2id + HKDF
- Hybrid post-quantum signatures (Ed25519 + ML-DSA-65)
- A self-hostable relay server that stores only encrypted blobs

CRDT metadata (pending ops, field versions, HLC timestamps) lives in Rust-managed tables —
the Drift schema never reads or writes them directly.

## Security

For vulnerability reports, see [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

## License

[GNU Affero General Public License v3.0](LICENSE)
