# Prism

A plural system management app built with Flutter — member management, fronting tracking, internal chat, polls, habits, and zero-knowledge encrypted sync.

Cross-platform rewrite of the existing SwiftUI app, targeting iOS, Android, macOS, and web.

## Features

- **Member Management** — profiles with avatars, emoji, pronouns, custom colors
- **Fronting Tracking** — quick front, co-fronting, session history, gap detection
- **Internal Chat** — conversations, reactions, unread tracking, "speaking as" picker
- **Polls** — anonymous/multi-vote options with expiration
- **Habits** — tracking with streaks, completions, and reminders
- **Sleep Tracking** — sleep/wake sessions with system integration
- **Onboarding** — guided setup flow for new users
- **Simply Plural Migration** — import members, fronting history, and more from SP exports
- **PluralKit Sync** — sync members and fronting data via PK API
- **Data Import/Export** — full system backup and restore
- **Encrypted Sync** — zero-knowledge CRDT sync via a self-hosted Rust relay with snapshots, WebSocket notifications, and local relay E2E coverage
- **Friend Sharing** — permission-scoped system sharing with cryptographic access control

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Flutter |
| State | Riverpod |
| Database | Drift + SQLite |
| Models | freezed + json_serializable |
| Navigation | go_router |
| Crypto | libsodium (XChaCha20-Poly1305, X25519, Argon2id), pqcrypto (ML-DSA-65, ML-KEM-768 via Rust FFI) |
| Sync | Custom CRDT with Hybrid Logical Clocks |

## Getting Started

```bash
# Install dependencies
flutter pub get

# Run code generation (freezed, drift, json_serializable)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Run tests
flutter test

# Optional: run the local relay end-to-end sync test
flutter test --dart-define=PRISM_RUN_LOCAL_RELAY_TESTS=true test/integration/local_relay_e2e_test.dart
```

Requires Dart SDK `^3.11.1`.

## Project Structure

```
lib/
├── core/           # Database, crypto, sync, router, services
├── domain/         # Pure Dart models and repository interfaces
├── data/           # Repository implementations and mappers
├── features/       # Feature modules (fronting, chat, habits, polls, etc.)
└── shared/         # Reusable widgets, theme, extensions
```


## License

MIT
