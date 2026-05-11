import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('screenPrivacyEnabledProvider', () {
    test('defaults to false when no value is persisted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = await container.read(
        screenPrivacyEnabledProvider.future,
      );
      expect(value, isFalse);
    });

    test('returns persisted true value on cold read', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.screen_privacy_enabled': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = await container.read(
        screenPrivacyEnabledProvider.future,
      );
      expect(value, isTrue);
    });

    test('set(true) flips state and persists to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(screenPrivacyEnabledProvider.future);
      await container
          .read(screenPrivacyEnabledProvider.notifier)
          .set(true);

      expect(container.read(screenPrivacyEnabledProvider).value, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.screen_privacy_enabled'), isTrue);
    });

    test('set(false) writes false and the next container reads false',
        () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.screen_privacy_enabled': true,
      });
      final first = ProviderContainer();
      await first.read(screenPrivacyEnabledProvider.future);
      await first.read(screenPrivacyEnabledProvider.notifier).set(false);
      first.dispose();

      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      final value = await fresh.read(
        screenPrivacyEnabledProvider.future,
      );
      expect(value, isFalse);
    });
  });
}
