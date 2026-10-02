# Testing the app

Run commands from the app root after `flutter pub get`. Flutter builds native code, so Rust and your platform's build tools are needed even when the change is mostly Dart. The runners use Bash, Git, and the Flutter/Dart tools; the fast lane also uses ripgrep, and the native lane uses `jq`.

## Start with the affected behavior

```bash
flutter test test/path/to/your_test.dart
flutter test test/core/sync/sync_schema_parity_test.dart
```

The schema parity test matters when changing entity registration. Database tests use in-memory Drift databases.

## Fast lane

```bash
scripts/test_fast.sh
```

This runs analysis and Dart/widget tests outside `test/e2e/`, excluding the integration, slow, fixture-generation, benchmark, and golden tags. Analyzer errors fail the lane; existing warnings and informational diagnostics are reported without failing it. Fix new diagnostics from your change.

Results, logs, and environment information go to `test-results/` by default. Set `PRISM_TEST_RESULTS_DIR` to choose another location.

## Native sync and media

```bash
scripts/test_native.sh
```

The runner finds the sync checkout selected by `flutter pub get`, verifies it against `pubspec.lock`, and builds release FFI and disposable local relay artifacts. It also runs the app-owned media codec's Rust tests and native/E2E coverage. It records the source revisions and artifact provenance.

The sync checkout must be clean, including untracked files; ignored build inputs outside `target/` also cause rejection. With a local path override, commit the sync candidate before running and name its revision explicitly:

```bash
PRISM_EXPECTED_SYNC_REV="$(git -C ../prism-sync rev-parse HEAD)" \
scripts/test_native.sh
```

If you set `PRISM_SYNC_DIR`, it must point to the same checkout that Flutter resolved. It does not select a different dependency on its own. The runner is qualified for macOS and Linux; Windows native E2E is not yet qualified.

Changes to PluralKit import/polling, front recovery, or native delivery must also pass:

```bash
scripts/run_required_native_integration.sh
```

That wrapper resolves dependencies, builds in a fresh temporary target directory, and requires the selected PK/front suites to execute successfully without skipped required tests. The PK HTTP boundary is faked and the relay is local. The report is `build/reports/required-native-integration.jsonl`.

For image codec changes, see the [codec guide](../../packages/prism_media_codec/README.md). Its focused commands are:

```bash
(cd packages/prism_media_codec/rust && cargo test)
flutter test test/core/services/media/image_compression_service_test.dart test/shared/utils/profile_header_image_normalizer_test.dart test/e2e/media_codec_native_assets_smoke_test.dart
```

## Benchmarks and live services

```bash
scripts/test_benchmark.sh
scripts/test_native_benchmark.sh
```

Benchmarks are explicit measurement runs, not ordinary PR timing gates. The native benchmark runner uses the same dependency/provenance requirements as the native lane. The broad native lane keeps the small import-to-peer avatar smoke; full configurable workloads belong to the benchmark lane.

Live PluralKit tests require a dedicated test account and two explicit environment variables: `PRISM_ALLOW_LIVE_TESTS=1` and `PRISM_LIVE_TEST_TOKEN`. After setting them in your local environment, run `scripts/test_live.sh`. An ambient `PK_TOKEN` alone never enables that lane. Keep credentials out of commits, reports, and shell history.

## What CI covers

The [PR workflow](../../.github/workflows/test.yml) runs the fast and native lanes on Linux. It does not establish device coverage on every platform. Device integration, benchmarks, and live-service checks are separate. Include which of those you ran when they matter to your change.
