# Prism

Prism helps plural systems track fronting, chat between members, log sleep,
build habits, run polls, and keep shared notes — all encrypted end-to-end,
synced across your devices.

Built by a plural system, for plural systems.

[prismplural.com](https://prismplural.com) · [Discord](https://discord.gg/32Qfhd6jMM) · [Sync engine](https://github.com/prismplural/prism-sync)

## What's in here

- **Fronting** — quick-switch who's in front, co-fronting, session history, gap detection
- **Chat** — conversations between members with reactions, GIFs, voice notes, @mentions
- **Boards** — long-form, email-style posts to a member or to the whole system, with an inbox per fronter
- **Members** — profiles with avatars, pronouns, emoji, custom colors, custom fields
- **Habits** — shared habit tracking with streaks and daily check-ins
- **Polls** — anonymous or open voting with expiration
- **Sleep** — sleep/wake tracking woven into the fronting timeline
- **Notes** — per-member or shared notes with inline markdown
- **Statistics** — fronting stats, activity charts, co-fronting patterns
- **Encrypted sync** — CRDT sync across devices via a self-hosted relay; the relay only ever sees ciphertext
- **Simply Plural import** — migrate from SP exports or the SP API
- **PluralKit sync** — bidirectional sync with PluralKit via their API
- **Languages** — English and Spanish, with more on the way

Everything is local-first. Sync is optional, self-hosted, and end-to-end
encrypted — the relay server stores only encrypted blobs and never sees your data.

## Getting started

Requirements: Flutter SDK (Dart `^3.11.1`) and a Rust toolchain for the sync engine.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

The sync engine is a Rust library
([prism-sync](https://github.com/prismplural/prism-sync)) included via path
dependencies. See the sync repo for build instructions if you need to modify
the Rust side.

### Platforms

iOS, Android, macOS, and Linux. iOS and Android are the primary targets;
desktop builds are usable but rougher around the edges.

There's no browser-based web client today. A direct browser client that
talks to the relay isn't on the roadmap — keeping your keys out of a
browser tab is part of the security model. A phone-paired web client (like
WhatsApp Web used to be, with your phone as the source of truth) is
something we might explore eventually, but it's not a priority.

### Running your own relay

Sync is optional. If you want it, you can use a shared community relay or run
your own — the relay only ever sees encrypted blobs, so self-hosting doesn't
require you to trust the operator with anything. See the
[self-hosting guide](https://github.com/prismplural/prism-sync/blob/main/self-host/SELF-HOSTING.md)
in the sync repo (Docker Compose and Kubernetes manifests included). Once
it's up, point the app at your relay URL in Settings → Sync.

### Tests

```bash
flutter test
```

680+ tests covering database, domain logic, sync integration, and widget behavior.

## Architecture

```
lib/
├── core/           # Database (Drift), sync integration, router, services
├── domain/         # Pure Dart models (freezed) and repository interfaces
├── data/           # Repository implementations and DB↔model mappers
├── features/       # Feature modules (fronting, chat, boards, habits, polls, …)
└── shared/         # Design system widgets, theme, extensions
```

Domain-driven: `domain/` holds pure Dart models and repository interfaces
with no Flutter imports. `data/` implements those interfaces against Drift.
Features consume repositories via Riverpod providers and never touch the
database directly.

### Key libraries

| Layer | Library | Why |
|-------|---------|-----|
| UI | Flutter (Material 3) | Cross-platform: iOS, Android, macOS, Linux |
| Dynamic color | dynamic_color | Material You / system palette on Android 12+ |
| State | Riverpod | Scoped, testable reactive state; hand-written providers only |
| Database | Drift + SQLite | Typesafe queries, codegen DAOs, stream-based reactivity |
| Models | freezed + json_serializable | Immutable value types with copy/equality/JSON |
| Navigation | go_router | Declarative routing, StatefulShellRoute for tab isolation |
| Sync | prism-sync (Rust, via FFI) | CRDT engine, E2E encryption, relay protocol |
| Secure storage | flutter_secure_storage | Platform Keychain (iOS) / Keystore (Android) |
| Background | workmanager | Periodic background sync |

### Data flow

```
Drift Tables → DAOs → Repositories → Mappers → Freezed Models → Riverpod Providers → Widgets
```

Mutations go through repositories, which emit CRDT ops to the sync engine.
The sync engine merges remote changes back into Drift via a diff-based
adapter. The relay server stores only encrypted blobs and is never trusted
with plaintext.

### Sync

Sync is provided by [prism-sync](https://github.com/prismplural/prism-sync),
a Rust library linked via `flutter_rust_bridge` FFI. It handles:

- Field-level Last-Write-Wins CRDTs with Hybrid Logical Clocks
- A 6-digit PIN + 12-word recovery phrase that derive your keys locally
- XChaCha20-Poly1305 encryption keyed from Argon2id + HKDF
- Hybrid post-quantum signatures (Ed25519 + ML-DSA-65) and X-Wing (X25519 + ML-KEM-768) for epoch rekey
- A self-hostable relay server that stores only encrypted blobs

CRDT metadata (pending ops, field versions, HLC timestamps) lives in
Rust-managed tables — the Drift schema never reads or writes them directly.

## Security

For vulnerability reports, see [SECURITY.md](SECURITY.md). For a deeper
walk-through of what the relay can and can't see, see
[prismplural.com/encryption/](https://prismplural.com/encryption/).

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd
like to change. All contributions require a signed Contributor License
Agreement — see [CLA.md](CLA.md).

## License

[GNU Affero General Public License v3.0](LICENSE)
