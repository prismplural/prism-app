import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

/// Regression for the Windows `flutter_secure_storage.dat` corruption bug
/// (flutter_secure_storage_windows issue #634): the single-file Windows backend
/// has no concurrency control, so two backend operations touching it at once
/// corrupt the file, and the corruption-recovery path then fails to delete the
/// locked file ("being used by another process", errno 32) — surfacing as a
/// pairing failure (the initiator credential drain racing background reads).
///
/// The fix serializes every secure-storage backend call behind a process-global
/// lock. These tests prove the `safeSecure*` wrappers never let two backend
/// calls overlap when the lock is engaged. The lock is normally Windows-gated;
/// [debugForceSecureStorageSerialization] forces it on so the behavior is
/// testable on the (non-Windows) test host. Remove the wrapping from any wrapper
/// and `maxConcurrent` jumps above 1 and the test fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late int active;
  late int maxConcurrent;

  setUp(() {
    debugForceSecureStorageSerialization = true;
    active = 0;
    maxConcurrent = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          active++;
          if (active > maxConcurrent) maxConcurrent = active;
          // Yield long enough that a second *unserialized* backend call would
          // overlap here — that's exactly the concurrent access that corrupts
          // the Windows .dat. With the lock, only one call is ever in flight.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          switch (call.method) {
            case 'readAll':
              return <String, String>{};
            case 'containsKey':
              return false;
            case 'read':
            case 'write':
            case 'delete':
            case 'deleteAll':
            default:
              return null;
          }
        });
  });

  tearDown(() {
    debugForceSecureStorageSerialization = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('concurrent safeSecureWrite calls never touch the backend at once',
      () async {
    await Future.wait<void>([
      for (var i = 0; i < 8; i++) safeSecureWrite('key_$i', 'value_$i'),
    ]);

    expect(
      maxConcurrent,
      1,
      reason:
          'secure-storage writes must be serialized so the Windows .dat is '
          'never written concurrently',
    );
  });

  test('mixed concurrent read/write/delete/readAll calls are serialized',
      () async {
    await Future.wait<void>([
      safeSecureWrite('a', '1'),
      safeSecureRead('a'),
      safeSecureWrite('b', '2'),
      safeSecureDelete('a'),
      safeSecureReadAll(),
      safeSecureWrite('c', '3'),
    ]);

    expect(maxConcurrent, 1);
  });
}
