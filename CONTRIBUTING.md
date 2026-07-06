# Contributing to Prism

Thanks for helping make Prism better. This guide covers the public workflow for
contributing to the Flutter app in this repository.

If you are reporting or fixing a security issue, do not open a public issue or
pull request. See [SECURITY.md](SECURITY.md) instead.

## Before You Start

- For small bug fixes, accessibility improvements, documentation fixes, and UI
  polish, opening a pull request directly is fine.
- For larger product changes, sync behavior, storage, encryption, or platform
  behavior, please open an issue first so we can agree on the approach.
- Check existing issues and pull requests before starting work.
- Comment on an issue before taking it if you want maintainer confirmation that
  it is still available and scoped correctly.

Good first issues are meant to be ready for contributors who are new to Prism.
They should include the relevant files, expected behavior, and suggested tests.
See [Good First Issues](docs/contributing/good-first-issues.md) for the
maintainer checklist and example issue format.

## Development Setup

You need Flutter with Dart `^3.11.1`, Rust via `rustup`, and the platform
toolchains for the target you want to run. The app builds native Rust code from
both `prism_sync` packages and app-owned packages under `packages/`. A local
`prism-sync` checkout is only needed when modifying sync source locally.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Use build runner watch mode while editing generated models or Drift database
sources:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Generated files include `*.freezed.dart`, `*.g.dart`, and Drift database code.
Commit generated files when your source change requires them.

## Tests And Checks

Run the narrowest useful test while developing, then run broader checks before
opening a pull request.

```bash
flutter analyze
flutter test
flutter test test/path/to/file_test.dart
```

In-memory Drift databases isolate database tests. If you touch sync schema
registration, run:

```bash
flutter test test/core/sync/sync_schema_parity_test.dart
```

For UI changes, include screenshots or a short screen recording when it helps
reviewers understand the behavior.

## Project Shape

The app uses Flutter, Riverpod, `go_router`, Drift, SQLite, Material 3, and the
Rust sync engine from
[prism-sync](https://github.com/prismplural/prism-sync).

```text
lib/
|-- main.dart
|-- app.dart
|-- core/
|-- domain/
|-- data/
|-- features/
|-- shared/
`-- l10n/

test/
integration_test/
packages/prism_media_codec/
android/ ios/ linux/ macos/ windows/
fastlane/ packaging/ scripts/
```

Feature modules usually use `providers/`, `views/`, `widgets/`, and sometimes
`services/` or `models/`.

## Code Guidelines

- Riverpod providers are hand-written. Do not add `@riverpod` codegen.
- Synced entities must be written through repositories so sync operations are
  emitted. Do not write directly to synced Drift tables.
- Domain models and repository interfaces live under `lib/domain/`.
- Repository implementations live under `lib/data/`.
- Modal sheets should use `PrismSheet.show()`.
- App bar icon actions should use `PrismIconButton`.
- Use `NavBarInset.of(context)` for bottom padding around the floating nav bar.
- Accent color comes from `Theme.of(context).colorScheme.primary`, not direct
  settings reads.
- Use the centralized `secureStorage` constant from
  `lib/core/services/secure_storage.dart`; do not instantiate
  `FlutterSecureStorage()` directly.
- Avoid logging secrets, key material, invite secrets, session tokens, or raw
  sync blobs.
- Keep non-sync native helpers in app-owned packages under `packages/`; use
  `prism-sync` only for sync, relay, and sync-owned FFI.

## Working With prism-sync

By default, `pubspec.yaml` depends on the public `prism-sync` git repository.
If you need to work against a sibling local checkout, create a gitignored
`pubspec_overrides.yaml` next to `pubspec.yaml`:

```yaml
dependency_overrides:
  prism_sync:
    path: ../prism-sync/dart/packages/prism_sync
  prism_sync_drift:
    path: ../prism-sync/dart/packages/prism_sync_drift
  prism_sync_flutter:
    path: ../prism-sync/dart/packages/prism_sync_flutter
```

After changing the Rust FFI API in `prism-sync`, regenerate bindings from the
sync repository and commit the generated Dart package changes there:

```bash
cd ../prism-sync
flutter_rust_bridge_codegen generate
```

Then run `flutter pub get`, `flutter analyze`, and the relevant Flutter tests in
this app.

## Working With App-Owned Native Packages

`packages/prism_media_codec` contains Prism's native static-image codec. It is a
Flutter native-assets package backed by Rust and `flutter_rust_bridge`; it lives
in this repository so image normalization does not add non-sync dependencies to
`prism-sync`.

If you change that package, run its Rust tests plus the app media tests:

```bash
(cd packages/prism_media_codec/rust && cargo test)
flutter test test/core/services/media/image_compression_service_test.dart test/shared/utils/profile_header_image_normalizer_test.dart test/e2e/media_codec_native_assets_smoke_test.dart
```

## Pull Requests

Keep pull requests focused. A good pull request includes:

- A clear summary of the user-facing change.
- The issue it fixes, when applicable.
- Tests or checks run locally.
- Screenshots or recordings for UI behavior.
- Generated files committed alongside their source changes.

By submitting a contribution, you agree to license it under Prism's project
license. You also confirm that you have the right to submit the contribution
and that it is your own work or is based on work you are allowed to contribute.
