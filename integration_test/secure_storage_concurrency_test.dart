import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

/// Real-backend proof for the Windows `flutter_secure_storage.dat` corruption
/// bug (flutter_secure_storage_windows issue #634) and its fix — the
/// process-global serialization lock in `core/services/secure_storage.dart`.
///
/// Unlike the unit test (which drives a mock method channel), this exercises the
/// REAL platform backend, so on Windows it hits the actual single-file `.dat`
/// that races and corrupts under concurrent access — the access pattern that
/// made the initiator pairing drain throw
/// `PathAccessException: ... being used by another process` (errno 32).
///
/// Run on the Windows VM:
///   flutter test integration_test/secure_storage_concurrency_test.dart -d windows
///
/// Expected: PASSES on this branch (the lock serializes every backend call).
/// On `main` (flutter_secure_storage_windows 4.1.0, NO lock) the concurrent
/// writes race the single `.dat` and throw PathAccessException / corrupt the
/// store — reproducing the pairing failure.
///
/// ⚠️  The `main`/before run can corrupt the secure-storage file it touches.
/// Run it on a throwaway Windows profile, NOT a VM holding real Prism data —
/// the `.dat` also stores the local DB encryption key.
///
/// Windows-gated: the macOS Keychain / Linux libsecret backends are
/// transactional and don't exhibit the race, so the test would only add
/// flakiness there.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const keyPrefix = 'prism_sync.__concurrency_probe__';
  const fanout = 40;
  // Windows-only: the macOS Keychain / Linux libsecret backends are
  // transactional and don't exhibit the single-file `.dat` race.
  final skipNonWindows = !Platform.isWindows;

  Future<void> cleanup() async {
    for (var i = 0; i < fanout; i++) {
      await safeSecureDelete('$keyPrefix$i');
    }
  }

  tearDown(cleanup);

  testWidgets(
    'concurrent writes survive the real backend without corruption',
    (_) async {
      // Burst of concurrent writes at the real backend — the pattern that
      // corrupts flutter_secure_storage.dat without serialization.
      final results = await Future.wait(<Future<SecureWriteResult>>[
        for (var i = 0; i < fanout; i++)
          safeSecureWrite('$keyPrefix$i', 'value-$i'),
      ]);
      for (var i = 0; i < fanout; i++) {
        expect(
          results[i].ok,
          isTrue,
          reason: 'write $i failed: code=${results[i].code} '
              'message=${results[i].message}',
        );
      }

      // Read back concurrently and verify integrity. Corruption surfaces as
      // missing/garbled values or a thrown PathAccessException.
      final readResults = await Future.wait(<Future<SecureReadResult>>[
        for (var i = 0; i < fanout; i++) safeSecureRead('$keyPrefix$i'),
      ]);
      for (var i = 0; i < fanout; i++) {
        expect(readResults[i].ok, isTrue, reason: 'read $i failed');
        expect(
          readResults[i].value,
          'value-$i',
          reason: 'read $i returned the wrong value — store corruption',
        );
      }
    },
    skip: skipNonWindows,
  );

  testWidgets(
    'interleaved concurrent write/read/delete never throw on the real backend',
    (_) async {
      // Mixed concurrent mutations are the harshest case for the single-file
      // backend. A PathAccessException here escapes the PlatformException-only
      // wrappers and crashes — exactly what happened during pairing.
      await expectLater(
        Future.wait(<Future<void>>[
          for (var i = 0; i < fanout; i++) ...<Future<void>>[
            safeSecureWrite('$keyPrefix$i', 'v$i'),
            safeSecureRead('$keyPrefix$i'),
            if (i.isEven) safeSecureDelete('$keyPrefix$i'),
          ],
        ]),
        completes,
      );
    },
    skip: skipNonWindows,
  );
}
