# Prism

A plural system management app built with Flutter. Track who's fronting, chat between
headmates, build habits together, and sync everything across devices with zero-knowledge
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
- **Encrypted Sync** — zero-knowledge CRDT sync across devices via a self-hosted relay
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

### Security

For vulnerability reports, see [SECURITY.md](SECURITY.md).

### Voice notes

New voice notes use a mobile-first Ogg Opus path.

- **Android** records Ogg Opus directly.
- **iOS** records Opus in CAF, may briefly show **Preparing voice note...**, then remuxes to Ogg before upload.
- **Playback** uses decrypted bytes in memory rather than the old `.m4a` temp-file path.
- `pubspec.yaml` currently overrides `flutter_soloud` and `ogg_caf_converter` to local path dependencies while Prism tracks fixes in those forks.

### Test

```bash
flutter test
```

680+ tests covering database operations, domain logic, sync integration, and widget behavior.

## Architecture

```
lib/
├── core/           # Database (Drift), sync integration, router, services
├── domain/         # Pure Dart models (freezed) and repository interfaces
├── data/           # Repository implementations and DB↔model mappers
├── features/       # Feature modules (fronting, chat, habits, polls, ...)
└── shared/         # Design system widgets, theme, extensions
```

| Layer | Tech |
|-------|------|
| UI | Flutter (Material 3, dynamic color) |
| State | Riverpod |
| Database | Drift + SQLite |
| Navigation | go_router |
| Sync | [prism-sync](https://github.com/prismplural/prism-sync) (Rust, via FFI) |

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

## License

[GNU Affero General Public License v3.0](LICENSE)
