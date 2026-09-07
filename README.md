# Prism

Hi. This is the source for the Prism app — a plural system management app built
by a plural system that uses it every day. If you're here to use Prism instead
of hack on it, [prismplural.com](https://prismplural.com) is the place to go.

The app is Flutter. Encrypted sync is Rust, lives in
[prism-sync](https://github.com/prismplural/prism-sync), and is wired in over
`flutter_rust_bridge`. App-owned native helpers live under `packages/`; today
that means the media codec package used for image normalization.

## What's in here

A Flutter app targeting iOS, Android, macOS, Linux, and Windows. Riverpod for
state (hand written — no `@riverpod` codegen), `go_router` with a
`StatefulShellRoute` for navigation, Drift + SQLite for the local database, and
Material 3 with `dynamic_color` for theming. Dart SDK `^3.11.1`. The package
name is `prism_plurality` because the `prism` name was taken on pub.dev.

```
lib/
├── main.dart                  # Rust init, keychain guard, workmanager
├── app.dart                   # MaterialApp.router with DynamicColorBuilder
├── core/                      # Infrastructure
│   ├── database/              # Drift DB, DAOs, tables, providers
│   ├── router/                # go_router config (5-tab StatefulShellRoute)
│   ├── services/              # Secure storage, notifications, validation
│   ├── sync/                  # Dart-side sync integration with prism-sync
│   ├── crypto/                # Dart crypto helpers
│   └── sharing/               # Friend links, permission-scoped sharing
├── domain/                    # Pure Dart models + abstract repositories
├── data/                      # Repository implementations + DB ↔ model mappers
├── features/                  # Feature modules
├── shared/                    # Design system: theme, widgets, extensions
└── l10n/                      # Localization

packages/prism_media_codec/        # App-owned Rust image codec native asset
test/                              # Unit, widget, and integration tests
integration_test/                  # Flutter integration tests
android/  ios/  linux/  macos/    # Platform shells
windows/
fastlane/  packaging/  scripts/   # Release plumbing
```

Each feature module under `lib/features/` has the same shape: `providers/`,
`views/`, `widgets/`, sometimes `services/` and `models/`.

## How data flows

```
Drift tables → DAOs → Repositories → Mappers → Freezed models → Riverpod → Widgets
```

Synced entities go through repositories that emit CRDT ops into `pending_ops`
via the Rust engine. **Writing directly to a synced Drift table produces a row
that never reaches other devices.** Always go through the repository.

To add a synced entity:

1. Add it to `prismSyncSchema` in `lib/core/sync/sync_schema.dart`.
2. Register a builder in `lib/core/sync/drift_sync_adapter.dart`.
3. `test/core/sync/sync_schema_parity_test.dart` fails CI if those two drift apart.

## Build and run

You need Flutter (Dart `^3.11.1`), Rust via `rustup`, and the platform
toolchains for whatever you're targeting. The app builds native Rust code from
both `prism_sync` packages and app-owned packages under `packages/`. A local
`prism-sync` checkout is only needed when modifying sync source locally.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## Test lanes

Fetch dependencies with `flutter pub get` before running a lane. Each lane
writes JSON events and environment details to `test-results/` (or
`PRISM_TEST_RESULTS_DIR`).

```bash
scripts/test_fast.sh          # deterministic Dart/widget/golden coverage for PRs
scripts/test_benchmark.sh     # explicit Drift measurement; not a timing gate
PRISM_SYNC_DIR=/path/to/prism-sync scripts/test_native_benchmark.sh
```

The native lane excludes the assertion-free add-member timing probe and the
full avatar-volume workload, but retains a three-avatar ZIP import-to-peer
smoke. `test_native_benchmark.sh` runs the tagged native workloads with their
full configurable inputs.

The required native lane builds a clean `prism-sync` checkout at the exact git
revision in `pubspec.lock`, builds the app-owned media codec Rust tests, and
then runs the native-asset and two-peer relay tests with a recorded artifact
provenance. It fails when the checkout, revision, or artifacts do not match.

```bash
PRISM_SYNC_DIR=/path/to/prism-sync scripts/test_native.sh
```

When a local path override selects an accepted sync candidate that differs from
the lockfile's git source, state that candidate revision explicitly instead of
letting the runner infer it. The provenance records both revisions:

```bash
PRISM_SYNC_DIR=/path/to/prism-sync \
PRISM_EXPECTED_SYNC_REV="$(git -C /path/to/prism-sync rev-parse HEAD)" \
scripts/test_native.sh
```

PluralKit integration tests are never enabled by an ambient `PK_TOKEN`. They
require an explicit opt-in and a dedicated test-account token:

```bash
PRISM_ALLOW_LIVE_TESTS=1 PRISM_LIVE_TEST_TOKEN=... scripts/test_live.sh
```

`scripts/test_benchmark.sh` discovers tagged non-native benchmark files. It
includes the Drift add-member workload and the two sweep-line analytics timing
cases, while their ordinary analytics correctness cases remain in the fast lane.

The checked-in PR workflow exercises the fast and native Linux lanes. Device
integration, benchmark, and live-service coverage remain deliberate commands;
they are not represented as cross-platform CI proof. The native lane is
qualified on macOS and Linux only; Windows native E2E remains unqualified.
The fast lane reports the current 132 non-error analyzer diagnostics but treats
only analyzer errors as failures; reducing that baseline is separate cleanup.

`build_runner` generates `*.freezed.dart`, `*.g.dart`, and Drift database code.
Swap `build` for `watch` while you're actively making changes.

### Working against a local prism-sync checkout

By default `pubspec.yaml` pulls `prism_sync*` from the public git repo. To
point at a sibling clone, drop a `pubspec_overrides.yaml` next to
`pubspec.yaml`:

```yaml
dependency_overrides:
  prism_sync:
    path: ../prism-sync/dart/packages/prism_sync
  prism_sync_drift:
    path: ../prism-sync/dart/packages/prism_sync_drift
  prism_sync_flutter:
    path: ../prism-sync/dart/packages/prism_sync_flutter
```

That file is gitignored. After changing the Rust FFI surface in
`crates/prism-sync-ffi/src/api.rs`, regenerate bindings from the sync repo:

```bash
cd ../prism-sync
flutter_rust_bridge_codegen generate
```

### App-owned Rust packages

Non-sync native code belongs in this repo under `packages/`, not in
`prism-sync`. `packages/prism_media_codec` owns static image re-encoding for
Prism media paths. See
[packages/prism_media_codec/README.md](packages/prism_media_codec/README.md)
for codec behavior, native-assets notes, and focused test commands.

### Testing

```bash
flutter analyze
flutter test
flutter test test/path/to/file_test.dart
```

In-memory Drift databases isolate DB tests.

For image codec changes, also run:

```bash
(cd packages/prism_media_codec/rust && cargo test)
flutter test test/core/services/media/image_compression_service_test.dart test/shared/utils/profile_header_image_normalizer_test.dart test/e2e/media_codec_native_assets_smoke_test.dart
```

## Contributing

We're glad you're here. Bug reports, accessibility issues, fixes, and feature
ideas are all welcome — direct feedback matters a lot to us.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, tests, pull request
expectations, and code guidelines. If you're thinking about something bigger
than a polish PR, please open an issue first. Sync compatibility, threat model,
and platform parity are the kinds of constraints that aren't obvious from the
code, and we'd rather flag them at the design stage than during review.

Contributions are accepted under Prism's project license. See
[CONTRIBUTING.md](CONTRIBUTING.md) for details.

For security issues, please don't open a public issue. See
[SECURITY.md](SECURITY.md).

## Related repositories

- [prism-sync](https://github.com/prismplural/prism-sync) — the Rust sync
  engine, Dart FFI packages, and self-hostable relay server.
- [prism-fronters](https://github.com/prismplural/prism-fronters) — public
  PluralKit fronters dashboard.

## On AI

We use AI coding tools (local and hosted) heavily while building Prism. The
security architecture, design decisions, and interface are ours; the
encryption is fully auditable regardless of what tools wrote the surrounding
code. We hope the app's quality stands on its own.

## License

[GNU Affero General Public License v3.0](LICENSE).
