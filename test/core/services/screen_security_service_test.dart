import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/services/screen_security_service.dart';

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
  });
}
