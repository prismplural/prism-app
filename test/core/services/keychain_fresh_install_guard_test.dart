import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Behavioral tests for `clearKeychainIfFreshInstall`.
///
/// These exercise the function's decision logic against in-memory mocks of
/// `SharedPreferences` and `FlutterSecureStorage`. They DO NOT prove the
/// real iOS Keychain semantics (survives uninstall) — that has to be
/// verified manually on a device. See
/// `docs/plans/skip-fresh-install-guard-in-non-release-builds.md` Step 5.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('clearKeychainIfFreshInstall', () {
    test('wipes secure storage when has_launched_before is missing', () async {
      FlutterSecureStorage.setMockInitialValues({
        'prism_sync.sync_id': 'aaaa',
        'prism_sync.relay_url': 'https://example',
        'app_lock.pin_hash': 'bbbb',
      });

      await clearKeychainIfFreshInstall();

      final all = await secureStorage.readAll();
      expect(all, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_launched_before'), isTrue);
    });

    test('preserves secure storage when has_launched_before is true', () async {
      SharedPreferences.setMockInitialValues({'has_launched_before': true});
      FlutterSecureStorage.setMockInitialValues({
        'prism_sync.sync_id': 'aaaa',
      });

      await clearKeychainIfFreshInstall();

      final all = await secureStorage.readAll();
      expect(all, containsPair('prism_sync.sync_id', 'aaaa'));
    });

    test(
      'sets has_launched_before on a true fresh install '
      '(empty keychain — wipe is a no-op but flag still flips)',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});

        await clearKeychainIfFreshInstall();

        final all = await secureStorage.readAll();
        expect(all, isEmpty);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('has_launched_before'), isTrue);
      },
    );
  });
}
