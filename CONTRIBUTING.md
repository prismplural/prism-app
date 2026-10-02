# Contributing to Prism Plural

You don't need to know the whole app to help. A reproducible bug report, an accessibility problem, or an instruction that didn't work is useful on its own. This guide is for the Flutter app; sync engine and relay changes belong in [prism-sync](https://github.com/prismplural/prism-sync).

## Find a place to start

Check the [issues](https://github.com/prismplural/prism-app/issues) and open pull requests before starting. Small fixes and documentation changes can go straight to a PR. For a larger feature or a change to sync, storage, encryption, or platform behavior, open an issue first so we can work through the approach.

For a bug report, include the app version, device or operating system, steps to reproduce, and what you expected to happen. Remove private member details, messages, tokens, and recovery information from anything you attach. Security reports go through [SECURITY.md](SECURITY.md), not a public issue.

If you're new to the code, look for a small issue you can reproduce. You can comment to check its scope before taking it on. Our [good first issue guide](docs/contributing/good-first-issues.md) describes what those issues should contain.

AI assistance is welcome. Read [AI_POLICY.md](AI_POLICY.md) before submitting assisted work; the same responsibility for correctness applies to all contributions.

## Build the app

Install Flutter, Rust through rustup, Git, and the platform tools for the device you want to run on. The Dart constraint is `^3.11.1`; the checked-in CI workflow uses Flutter **3.44.1**. Native code is built as part of the Flutter build.

Fork this repository on GitHub, then clone your fork:

```bash
git clone https://github.com/YOUR-USERNAME/prism-app.git
cd prism-app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Choose a connected device or desktop target when Flutter asks. You don't need a separate sync checkout for an app-only change: the sync packages come from the public Git revision pinned in `pubspec.yaml`.

For Linux, CI installs the following build prerequisites in addition to Flutter and Rust. Other distributions use different package names:

```bash
sudo apt-get install clang cmake pkg-config libasound2-dev libsqlite3-dev
```

When changing Freezed models or Drift database sources, regenerate their `*.freezed.dart` and `*.g.dart` files and include them with your change. For continuous regeneration:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Find your way around

| Location | What's there |
| --- | --- |
| `lib/features/` | Fronting, members, chat, settings, and other feature screens and providers |
| `lib/domain/` | Pure Dart models and repository interfaces |
| `lib/data/` | Repository implementations and database/model mappers |
| `lib/core/` | Database, routing, services, and the app's sync integration |
| `lib/shared/` | Shared widgets, themes, and utilities |
| `lib/l10n/` | Localization |
| `packages/prism_media_codec/` | App-owned Rust image normalization |
| `test/`, `integration_test/` | Unit, widget, native, and device tests |
| `android/`, `ios/`, `linux/`, `macos/`, `windows/` | Platform projects |

The app uses Riverpod, go_router, Drift/SQLite, and Material 3. Feature modules usually have `providers/`, `views/`, and `widgets/`, with services or models where needed.

Data flows from Drift tables through DAOs, repositories, and mappers into Freezed models, Riverpod providers, and widgets. **Write synced data through repositories.** A direct write to a synced table can appear locally without creating the operation that other devices need.

When adding a synced entity, update [`prismSyncSchema`](lib/core/sync/sync_schema.dart) and the entity builder in [`drift_sync_adapter.dart`](lib/core/sync/drift_sync_adapter.dart). Run the [schema parity test](test/core/sync/sync_schema_parity_test.dart).

A few conventions will save you time during review:

- Keep Riverpod providers handwritten; we don't use `@riverpod` codegen.
- Use `PrismSheet.show()` for modal sheets and `PrismIconButton` for app bar icon actions. See the [component guide](docs/component-guide.md).
- Account for the floating navigation bar with `NavBarInset.of(context)`.
- Read the accent from `Theme.of(context).colorScheme.primary`.
- Use the shared `secureStorage` in `lib/core/services/secure_storage.dart`. Don't construct a separate `FlutterSecureStorage` instance.
- Keep keys, tokens, recovery phrases, invite secrets, and private records out of logs and test fixtures. Use synthetic data.
- Keep non-sync native helpers in this repository under `packages/`.

## Check your change

Run the relevant test while developing, then the fast lane before submitting a code change. The runner also needs ripgrep (`rg`).

```bash
flutter test test/path/to/your_test.dart
scripts/test_fast.sh
```

The fast lane runs analysis and selected Dart/widget tests. Native sync tests need a separate lane; a passing fast lane does not cover that boundary. See [Testing](docs/testing/README.md) for prerequisites, native checks, benchmarks, and the deliberately opt-in live tests.

For PluralKit import or polling, front recovery, or native delivery changes, run the required integration gate:

```bash
scripts/run_required_native_integration.sh
```

For UI changes, exercise the affected flow and include screenshots or a short recording. Say which platform you checked. If you couldn't run a check, say so and include the error or missing prerequisite.

## Work across app and sync

Clone [prism-sync](https://github.com/prismplural/prism-sync) beside this repo when you need to change the engine. Put this in the gitignored `pubspec_overrides.yaml` in the app root:

```yaml
dependency_overrides:
  prism_sync:
    path: ../prism-sync/dart/packages/prism_sync
  prism_sync_drift:
    path: ../prism-sync/dart/packages/prism_sync_drift
  prism_sync_flutter:
    path: ../prism-sync/dart/packages/prism_sync_flutter
```

Run `flutter pub get` after changing the overrides. All three packages must come from the same checkout. The native test lane requires that checkout to be clean and its commit to be named explicitly when using path dependencies; see [Testing](docs/testing/README.md#native-sync-and-media).

FFI changes and regenerated bindings belong together in the sync PR. Follow [its contributor guide](https://github.com/prismplural/prism-sync/blob/main/CONTRIBUTING.md) for code generation. Prefer a compatible sync change first, then update the app's pinned revision and lockfile. Link the two PRs so reviewers can follow the dependency.

## Send a pull request

Use the AI assistance checkbox in the PR template and list the model and harness if applicable. See [AI_POLICY.md](AI_POLICY.md).

Write the PR description yourself. Explain the problem and how the change addresses it. Include the related issue if there is one, checks you actually ran, remaining uncertainty, and UI images where useful. Keep unrelated cleanup separate, and include generated files with their sources.

By submitting a contribution, you agree to license it under the [project license](LICENSE). You confirm that you have the right to contribute it and identify any third-party work and its license.
