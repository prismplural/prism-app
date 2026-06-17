# Agent Guide

## Repository Role

Prism is a Flutter app for plural system management. It targets iOS, Android,
macOS, Linux, and Windows, and uses the public
[prism-sync](https://github.com/prismplural/prism-sync) repository for encrypted
CRDT sync through `flutter_rust_bridge`.

This is not a monorepo. Do not assume the sync engine lives inside this checkout.
Public repo instructions should be enough for an outside contributor using a
plain clone. Maintainer-only multi-repo workflow, release coordination, and
private operations notes belong outside this repository.

Package name: `prism_plurality`.

## Related Public Repositories

- `prism-sync`: Rust sync engine, Dart FFI packages, and self-hostable relay.
- `prism-fronters`: public PluralKit fronters dashboard.

If a change spans app and sync, prefer a backward-compatible `prism-sync` change
first, then update this app to consume the new sync revision. Keep PRs and
commits repo-local.

## Build And Test

Use Flutter with Dart `^3.11.1`, Rust via `rustup`, and the platform toolchains
for the target you want to run. The app depends on `prism_sync` packages that
build native Rust code during Flutter builds.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

Use watch mode while editing generated-model or Drift sources:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Generated files include `*.freezed.dart`, `*.g.dart`, and Drift database code.
Commit generated files when the source change requires them.

## Working With prism-sync

`pubspec.yaml` depends on the public `prism-sync` git repo:

```yaml
prism_sync:
  git:
    url: https://github.com/prismplural/prism-sync.git
    path: dart/packages/prism_sync
```

For local development against a sibling `prism-sync` checkout, create a
gitignored `pubspec_overrides.yaml`:

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
sync repo and commit the generated Dart package changes there:

```bash
cd ../prism-sync
flutter_rust_bridge_codegen generate
```

Then run `flutter pub get`, `flutter analyze`, and the relevant Flutter tests in
this app. For published dependency updates, update this repo's resolved
`prism-sync` revision rather than relying on local path overrides.

## Project Shape

```text
lib/
├── main.dart                  # Rust init, keychain guard, workmanager
├── app.dart                   # MaterialApp.router with DynamicColorBuilder
├── core/                      # Database, router, services, sync integration
├── domain/                    # Pure Dart models + repository interfaces
├── data/                      # Drift-backed repositories and mappers
├── features/                  # Feature modules
├── shared/                    # Theme, widgets, extensions, utilities
└── l10n/                      # Localization

test/                              # Unit and widget tests
integration_test/                  # Flutter integration tests
android/ ios/ linux/ macos/        # Platform shells
windows/
fastlane/ packaging/ scripts/      # Release and packaging support
```

Feature modules usually use `providers/`, `views/`, `widgets/`, and sometimes
`services/` or `models/`.

## Architecture Rules

Data flow:

```text
Drift tables -> DAOs -> Repositories -> Mappers -> Freezed models -> Riverpod -> Widgets
```

- Domain models and repository interfaces in `lib/domain/` stay pure Dart.
- Repository implementations live under `lib/data/`.
- Riverpod providers are hand-written. Do not add `@riverpod` codegen.
- Navigation uses `go_router` with a 5-tab `StatefulShellRoute`.
- Modal sheets should use `PrismSheet.show()`.
- App bar icon actions should use `PrismIconButton`.
- Use `NavBarInset.of(context)` for bottom padding around the floating nav bar.
- Accent color comes from `Theme.of(context).colorScheme.primary`, not direct
  settings reads.

## Sync And Storage Rules

- Synced app tables do not own CRDT metadata columns. The Rust sync engine owns
  metadata in Rust-managed tables such as `pending_ops`, `applied_ops`,
  `field_versions`, and `sync_metadata`.
- Never write directly to a synced Drift table. Use repositories so the app
  emits `syncRecordCreate`, `syncRecordUpdate`, or `syncRecordDelete` ops.
- To add a synced entity, update `prismSyncSchema` in
  `lib/core/sync/sync_schema.dart` and register the entity builder in
  `lib/core/sync/drift_sync_adapter.dart`.
- `test/core/sync/sync_schema_parity_test.dart` must stay green when the sync
  schema changes.
- Use the centralized `secureStorage` constant from
  `lib/core/services/secure_storage.dart`. Do not instantiate bare
  `FlutterSecureStorage()`.
- Runtime DEK cache and sync credentials are device-bound secrets. Avoid logging
  key material, wrapped keys, session tokens, invite secrets, or raw sync blobs.

## Useful Checks

```bash
flutter analyze
flutter test
flutter test test/core/sync/sync_schema_parity_test.dart
flutter test test/path/to/file_test.dart
```

If a change touches sync behavior, also run the relevant `prism-sync` tests in
that repository before updating this app to consume it.

## Public Documentation Boundary

Keep public docs focused on building, testing, contributing, self-hosting, and
understanding the app. Do not add internal release checklists, private beta
operations, moderation notes, unpublished product strategy, or agent-specific
private workspace procedures to this repository.
