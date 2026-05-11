import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/services/screen_privacy_controller.dart';
import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.prism.prism_plurality/secure_display');
  late List<bool> setCalls;

  setUp(() {
    setCalls = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setSecureDisplay') {
        final args = call.arguments as Map<dynamic, dynamic>;
        setCalls.add(args['enabled'] as bool);
      }
      return null;
    });
    ScreenSecurityService.debugResetForTests();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    ScreenSecurityService.debugResetForTests();
  });

  group('setGlobalEnabled', () {
    test('first call to true issues one setSecureDisplay(true)', () async {
      await ScreenSecurityService.setGlobalEnabled(true);
      expect(setCalls, [true]);
    });

    test('first call to false issues zero calls', () async {
      await ScreenSecurityService.setGlobalEnabled(false);
      expect(setCalls, isEmpty);
    });

    test('redundant true does not re-issue', () async {
      await ScreenSecurityService.setGlobalEnabled(true);
      await ScreenSecurityService.setGlobalEnabled(true);
      expect(setCalls, [true]);
    });

    test('true then false issues on then off', () async {
      await ScreenSecurityService.setGlobalEnabled(true);
      await ScreenSecurityService.setGlobalEnabled(false);
      expect(setCalls, [true, false]);
    });
  });

  group('interaction with ref-counted enable/disable', () {
    test('global true then enable() does not double-on', () async {
      await ScreenSecurityService.setGlobalEnabled(true);
      await ScreenSecurityService.enable();
      expect(setCalls, [true]);
    });

    test('global true holds platform on even after disable()', () async {
      await ScreenSecurityService.setGlobalEnabled(true);
      await ScreenSecurityService.enable();
      await ScreenSecurityService.disable();
      expect(setCalls, [true]);
    });

    test(
        'enable() then global true issues only one on',
        () async {
      await ScreenSecurityService.enable();
      await ScreenSecurityService.setGlobalEnabled(true);
      expect(setCalls, [true]);
    });

    test('global goes false while ref still held keeps platform on', () async {
      await ScreenSecurityService.enable();
      await ScreenSecurityService.setGlobalEnabled(true);
      await ScreenSecurityService.setGlobalEnabled(false);
      expect(setCalls, [true]);
    });

    test('platform turns off only when all refs and global drop to zero',
        () async {
      await ScreenSecurityService.enable();
      await ScreenSecurityService.setGlobalEnabled(true);
      await ScreenSecurityService.setGlobalEnabled(false);
      await ScreenSecurityService.disable();
      expect(setCalls, [true, false]);
    });

    test('retries when the first platform call fails', () async {
      // Simulate the cold-boot race where main.dart calls
      // setGlobalEnabled(true) before the FlutterEngine has registered
      // the secure_display channel handler. The first invocation throws
      // a MissingPluginException; the next attempt should retry.
      var callIndex = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setSecureDisplay') {
          final args = call.arguments as Map<dynamic, dynamic>;
          final enabled = args['enabled'] as bool;
          callIndex++;
          if (callIndex == 1) {
            throw MissingPluginException('not yet registered');
          }
          setCalls.add(enabled);
        }
        return null;
      });

      await ScreenSecurityService.setGlobalEnabled(true);
      expect(setCalls, isEmpty, reason: 'first attempt failed, nothing cached');

      // Controller fires setGlobalEnabled(true) again with the same value
      // (e.g. on first build of the controller-provider after the engine
      // is fully alive). The service must retry.
      await ScreenSecurityService.setGlobalEnabled(true);
      expect(setCalls, [true]);
    });
  });

  group('screenPrivacyControllerProvider integration', () {
    Future<ProviderContainer> makeContainer({required bool initial}) async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.screen_privacy_enabled': initial,
      });
      final container = ProviderContainer();
      // Build the source provider so the controller has a non-loading
      // value to read on first access.
      await container.read(screenPrivacyEnabledProvider.future);
      return container;
    }

    test('reading the controller with toggle ON applies setSecureDisplay(true)',
        () async {
      final container = await makeContainer(initial: true);
      addTearDown(container.dispose);

      container.read(screenPrivacyControllerProvider);
      // Allow the async ref.listen callback to settle.
      await Future<void>.delayed(Duration.zero);

      expect(setCalls, [true]);
    });

    test('flipping the source provider OFF turns the platform OFF',
        () async {
      final container = await makeContainer(initial: true);
      addTearDown(container.dispose);

      container.read(screenPrivacyControllerProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(screenPrivacyEnabledProvider.notifier)
          .set(false);
      await Future<void>.delayed(Duration.zero);

      expect(setCalls, [true, false]);
    });

    test('toggling true -> false -> true issues transitions only',
        () async {
      final container = await makeContainer(initial: false);
      addTearDown(container.dispose);

      container.read(screenPrivacyControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(setCalls, isEmpty);

      await container
          .read(screenPrivacyEnabledProvider.notifier)
          .set(true);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(screenPrivacyEnabledProvider.notifier)
          .set(false);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(screenPrivacyEnabledProvider.notifier)
          .set(true);
      await Future<void>.delayed(Duration.zero);

      expect(setCalls, [true, false, true]);
    });

    test('disposing the container does NOT turn the platform off',
        () async {
      final container = await makeContainer(initial: true);
      container.read(screenPrivacyControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(setCalls, [true]);

      container.dispose();

      // Tear-down of the provider tree must not push a setSecureDisplay(false)
      // call. The platform state survives the container — the toggle owns it.
      expect(setCalls, [true]);
    });
  });
}
