// Phase 0 of the end-to-end FFI harness: prove that a `flutter test` can load
// the host-built Rust cdylib and dispatch real FFI calls (no mocks).
//
// Build prereq: (cd ../prism-sync && cargo build --release -p prism_sync_ffi)

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_support.dart';

void main() {
  test('Dart loads and dispatches the real Rust FFI (no mocks)', skip: e2eSkip(), () async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));

    // A real Rust computation ran and returned across the FFI boundary.
    final key = await ffi.generateSecretKey();
    expect(key, isNotEmpty, reason: 'generate_secret_key should return a key');

    // And a second real function dispatched cleanly — no Rust panic recorded.
    expect(await ffi.takeLastPanic(), isNull, reason: 'no panic on a clean init');

    RustLib.dispose();
  });
}
