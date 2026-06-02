import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/features/settings/views/pin_lock_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// Records every set(bool) call so tests can assert on user interaction.
class _FakeScreenPrivacyNotifier extends ScreenPrivacyEnabledNotifier {
  _FakeScreenPrivacyNotifier({required this.initialValue});
  final bool initialValue;
  final List<bool> setCalls = <bool>[];

  @override
  Future<bool> build() async => initialValue;

  @override
  Future<void> set(bool value) async {
    setCalls.add(value);
    state = AsyncValue.data(value);
  }
}

// Loading variant — never resolves, so the section should stay hidden.
class _LoadingScreenPrivacyNotifier extends ScreenPrivacyEnabledNotifier {
  @override
  Future<bool> build() {
    return Completer<bool>().future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const secureDisplayChannel = MethodChannel(
    'com.prism.prism_plurality/secure_display',
  );
  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Mocks: prevent platform-channel exceptions during the test render.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureDisplayChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (call) async {
          switch (call.method) {
            case 'canCheckBiometrics':
              return false;
            case 'isDeviceSupported':
              return false;
            case 'getAvailableBiometrics':
              return <String>[];
          }
          return null;
        });
    ScreenSecurityService.debugResetForTests();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureDisplayChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null);
    ScreenSecurityService.debugResetForTests();
  });

  Widget buildSubject({
    required TargetPlatform platform,
    ScreenPrivacyEnabledNotifier Function()? screenPrivacyNotifier,
    SystemSettings settings = const SystemSettings(),
    bool isPinSet = false,
    Future<bool> Function()? biometricAvailability,
  }) {
    return ProviderScope(
      overrides: [
        targetPlatformProvider.overrideWithValue(platform),
        systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
        isPinSetProvider.overrideWith((ref) async => isPinSet),
        if (biometricAvailability != null)
          isBiometricAvailableProvider.overrideWith(
            (ref) => biometricAvailability(),
          ),
        if (screenPrivacyNotifier != null)
          screenPrivacyEnabledProvider.overrideWith(screenPrivacyNotifier),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PinLockSettingsScreen(),
      ),
    );
  }

  Widget buildPinInputSubject({
    required SystemSettings settings,
    required Future<bool> Function() biometricAvailability,
  }) {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
        isBiometricAvailableProvider.overrideWith(
          (ref) => biometricAvailability(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: PinInputScreen(mode: PinInputMode.unlock, onSuccess: () {}),
      ),
    );
  }

  group('Screen Privacy toggle', () {
    testWidgets('renders Android subtitle and switch OFF on Android', (
      tester,
    ) async {
      late _FakeScreenPrivacyNotifier fake;
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.android,
          screenPrivacyNotifier: () {
            fake = _FakeScreenPrivacyNotifier(initialValue: false);
            return fake;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screen Privacy'), findsOneWidget);
      expect(find.text('Hide app contents'), findsOneWidget);
      expect(
        find.text('Block screenshots and hide Prism from the app switcher.'),
        findsOneWidget,
      );
      // The first Switch in the rendered tree belongs to Screen Privacy
      // (the section sits above the PIN section).
      final firstSwitch = tester.widgetList<Switch>(find.byType(Switch)).first;
      expect(firstSwitch.value, isFalse);
    });

    testWidgets('renders iOS subtitle on iOS', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.iOS,
          screenPrivacyNotifier: () =>
              _FakeScreenPrivacyNotifier(initialValue: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Hide Prism from the app switcher and screen recordings',
        ),
        findsOneWidget,
      );
      final firstSwitch = tester.widgetList<Switch>(find.byType(Switch)).first;
      expect(firstSwitch.value, isTrue);
    });

    testWidgets('tapping the row calls set(true) on the notifier', (
      tester,
    ) async {
      late _FakeScreenPrivacyNotifier fake;
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.android,
          screenPrivacyNotifier: () {
            fake = _FakeScreenPrivacyNotifier(initialValue: false);
            return fake;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hide app contents'));
      await tester.pumpAndSettle();

      expect(fake.setCalls, [true]);
    });

    testWidgets('Screen Privacy section appears ABOVE PIN Lock section', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.android,
          screenPrivacyNotifier: () =>
              _FakeScreenPrivacyNotifier(initialValue: false),
        ),
      );
      await tester.pumpAndSettle();

      final screenPrivacyTop = tester
          .getTopLeft(find.text('Screen Privacy'))
          .dy;
      final pinLockTop = tester.getTopLeft(find.text('PIN Lock')).dy;
      expect(screenPrivacyTop, lessThan(pinLockTop));
    });

    testWidgets('section is absent on unsupported platforms (macOS)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.macOS,
          screenPrivacyNotifier: () =>
              _FakeScreenPrivacyNotifier(initialValue: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screen Privacy'), findsNothing);
      expect(find.text('Hide app contents'), findsNothing);
    });

    testWidgets('section is absent while the notifier is loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          platform: TargetPlatform.android,
          screenPrivacyNotifier: _LoadingScreenPrivacyNotifier.new,
        ),
      );
      // Pump the system-settings stream so the screen-level guard releases.
      await tester.pump();
      await tester.pump();

      // The screen-privacy notifier never resolves, so its section must
      // not render — but the rest of the screen does.
      expect(find.text('Screen Privacy'), findsNothing);
      // PIN Lock section still renders because settings stream resolved.
      expect(find.text('PIN Lock'), findsOneWidget);
    });
  });

  group('Biometric toggle', () {
    testWidgets(
      'does not probe availability before the user opts into biometrics',
      (tester) async {
        var availabilityChecks = 0;

        await tester.pumpWidget(
          buildSubject(
            platform: TargetPlatform.iOS,
            settings: const SystemSettings(
              pinLockEnabled: true,
              biometricLockEnabled: false,
            ),
            isPinSet: true,
            biometricAvailability: () async {
              availabilityChecks++;
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(availabilityChecks, 0);
        expect(find.text('Biometric Unlock'), findsOneWidget);
      },
    );

    testWidgets(
      'locked PIN screen does not probe availability when biometrics are off',
      (tester) async {
        var availabilityChecks = 0;

        await tester.pumpWidget(
          buildPinInputSubject(
            settings: const SystemSettings(
              pinLockEnabled: true,
              biometricLockEnabled: false,
            ),
            biometricAvailability: () async {
              availabilityChecks++;
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(availabilityChecks, 0);
        expect(find.byIcon(AppIcons.fingerprint), findsNothing);
      },
    );

    testWidgets(
      'locked PIN screen probes availability when biometrics are on',
      (tester) async {
        var availabilityChecks = 0;

        await tester.pumpWidget(
          buildPinInputSubject(
            settings: const SystemSettings(
              pinLockEnabled: true,
              biometricLockEnabled: true,
            ),
            biometricAvailability: () async {
              availabilityChecks++;
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(availabilityChecks, 1);
        expect(find.byIcon(AppIcons.fingerprint), findsOneWidget);
      },
    );
  });
}
