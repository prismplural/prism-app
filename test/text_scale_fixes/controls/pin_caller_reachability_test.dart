// Caller reachability for the PIN pad after the keys grew with the digit.
//
// The set-PIN screen used a centred Spacer column. Once keys hold a 3.375x digit
// the pad is taller than a short phone viewport - and a short window can overflow
// even at 1x - so the screen now measures the height it really has (keyboard
// included) and scrolls only when the content does not fit. These tests walk the
// real flow (settings -> set PIN -> confirm) and tap through the pad: first key,
// last row, backspace, back/cancel, at 1x and large text, short windows, with an
// open keyboard, and across a live resize/scale change.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart'
    show systemSettingsRepositoryProvider;
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_lock_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';

import '../../helpers/fake_repositories.dart';
import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.4 : 28.0 + (fontSize - 20) * 3.0;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 3.0;
}

/// Stands in for the off-isolate PIN hash; nothing here touches the keychain.
class _FakePinLockService extends PinLockService {
  final storeCalls = <String>[];
  var stored = false;

  @override
  Future<bool> isPinSet() async => stored;

  @override
  Future<void> storePin(String pin) async {
    storeCalls.add(pin);
    stored = true;
  }

  @override
  Future<bool> verifyStoredPin(String pin) async => false;

  @override
  Future<bool> authenticateBiometric() async => false;
}

/// Live text scale + keyboard inset so a test can change them mid-flow and prove
/// the entered digits survive.
class _Harness extends ChangeNotifier {
  _Harness(this.textScaler);

  TextScaler textScaler;
  double keyboardInset = 0.0;

  void update({TextScaler? textScaler, double? keyboardInset}) {
    if (textScaler != null) this.textScaler = textScaler;
    if (keyboardInset != null) this.keyboardInset = keyboardInset;
    notifyListeners();
  }
}

Widget _launcher({
  required _FakePinLockService service,
  required FakeSystemSettingsRepository settingsRepository,
  _Harness? harness,
  TextScaler textScaler = const PrismTextScaler(TextScaler.noScaling, 1.0),
}) {
  return ProviderScope(
    overrides: [
      targetPlatformProvider.overrideWithValue(TargetPlatform.android),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      isPinSetProvider.overrideWith((ref) => service.isPinSet()),
      pinLockServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        fontFamily: 'OpenDyslexic',
        fontFamilyFallback: const ['NotoColorEmoji'],
      ),
      builder: (context, child) {
        Widget wrap(BuildContext context, TextScaler scaler, double inset) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: scaler,
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        }

        if (harness == null) {
          return wrap(context, textScaler, 0);
        }
        return ListenableBuilder(
          listenable: harness,
          builder: (context, _) =>
              wrap(context, harness.textScaler, harness.keyboardInset),
        );
      },
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PinLockSettingsScreen(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> _openCaptureStep(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // The settings page is a lazy list: at large text the PIN section is below the
  // fold, so drive the real control (scroll it into view) rather than assuming it
  // is already built.
  final enable = find.text('Enable PIN Lock');
  if (enable.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      enable,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // A cached label can exist below the viewport even at normal text.
  await tester.ensureVisible(enable);
  await tester.pumpAndSettle();
  expect(
    enable.hitTestable(),
    findsOneWidget,
    reason: 'Enable PIN Lock must receive the real toggle tap',
  );
  await tester.tap(enable);
  await tester.pumpAndSettle();

  // The flow enables PIN lock asynchronously before it shows the capture step, so
  // wait for the step itself and its keypad - not merely for a label - or the test
  // would assert geometry against an intermediate screen.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  expect(
    find.text('Set PIN'),
    findsOneWidget,
    reason: 'the set-PIN capture step is on screen',
  );
  expect(
    find.byType(PinNumpadButton),
    findsWidgets,
    reason: 'the capture step renders its keypad',
  );
}

/// Taps a keypad digit, scrolling it into view first (the pad may be taller than
/// the viewport once the keys grow with the digit).
Future<void> _tapDigit(WidgetTester tester, String digit) async {
  final finder = find.text(digit).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _revealAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
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

  setUpAll(() async {
    await loadPrismGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  for (final (label, scaler) in const [
    (
      'system 225% x Prism 150% = 3.375x',
      PrismTextScaler(TextScaler.linear(2.25), 1.5),
    ),
    (
      'nonlinear system scaler x Prism 150%',
      PrismTextScaler(_NonLinearTextScaler(), 1.5),
    ),
  ]) {
    testWidgets('every key of the set-PIN pad is reachable ($label)', (
      tester,
    ) async {
      useViewport(tester, const Size(320, 568));
      await tester.pumpWidget(
        _launcher(
          service: _FakePinLockService(),
          settingsRepository: FakeSystemSettingsRepository(),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();
      await _openCaptureStep(tester);

      expect(tester.takeException(), isNull, reason: '$label: no layout error');

      // First key, then the last row ('0'), then a backspace, then all six.
      await _tapDigit(tester, '1');
      await _tapDigit(tester, '0');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label: pad taps fine');

      await _revealAndTap(
        tester,
        find.byIcon(AppIcons.backspaceOutlined).first,
      );

      // '1' is still entered; five more digits complete the set step.
      for (final digit in const ['2', '3', '4', '5', '6']) {
        await _tapDigit(tester, digit);
      }
      await tester.pumpAndSettle();
      // Reaching the confirm step proves the whole pad (including the bottom
      // row) is reachable and the flow is intact.
      expect(find.text('Confirm PIN'), findsOneWidget);
    });
  }

  testWidgets('a short window scrolls even at normal text', (tester) async {
    // 320x360 is shorter than the pad plus its header at 1x, so the fit has to be
    // driven by the measured height - a text-scale threshold would miss this.
    useViewport(tester, const Size(320, 360));
    await tester.pumpWidget(
      _launcher(
        service: _FakePinLockService(),
        settingsRepository: FakeSystemSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await _openCaptureStep(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Set PIN'), findsOneWidget);

    for (final digit in const ['1', '2', '3', '4', '5', '6']) {
      await _tapDigit(tester, digit);
    }
    await tester.pumpAndSettle();
    expect(find.text('Confirm PIN'), findsOneWidget);
  });

  testWidgets('an open keyboard keeps the pad reachable', (tester) async {
    // Real viewInsets, as the platform reports them: 300dp of keyboard over a
    // 320x568 window leaves 268dp, far less than the pad needs at 3.375x.
    useViewport(tester, const Size(320, 568));
    final harness = _Harness(
      const PrismTextScaler(TextScaler.linear(2.25), 1.5),
    );
    addTearDown(harness.dispose);
    harness.keyboardInset = 300;

    await tester.pumpWidget(
      _launcher(
        service: _FakePinLockService(),
        settingsRepository: FakeSystemSettingsRepository(),
        harness: harness,
      ),
    );
    await tester.pumpAndSettle();
    await _openCaptureStep(tester);

    expect(tester.takeException(), isNull);
    await _tapDigit(tester, '9');
    await _tapDigit(tester, '0');

    // Back/Cancel stays reachable and still returns to PIN lock settings.
    await _revealAndTap(tester, find.byTooltip('Back').first);
    expect(find.text('Enable PIN Lock'), findsOneWidget);
  });

  testWidgets('normal text on a tall window keeps the centred geometry', (
    tester,
  ) async {
    useViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      _launcher(
        service: _FakePinLockService(),
        settingsRepository: FakeSystemSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await _openCaptureStep(tester);

    expect(tester.takeException(), isNull);
    for (final digit in const ['1', '5', '9', '0']) {
      final rect = tester.getRect(find.text(digit).first);
      expect(
        rect.bottom,
        lessThanOrEqualTo(568),
        reason: '"$digit" must be on screen without scrolling at normal text',
      );
    }

    // Geometry, not the absence of a scroll view: the Spacers keep their 2:2:1
    // weights, i.e. the gap above the title is twice the gap under the pad.
    final back = tester.getRect(find.byTooltip('Back').first);
    final title = tester.getRect(find.text('Set PIN'));
    // The pad's own column, so its row padding is included in the gap below.
    final padRect = tester.getRect(
      find
          .ancestor(
            of: find
                .ancestor(
                  of: find.text('0').first,
                  matching: find.byType(PinNumpadButton),
                )
                .first,
            matching: find.byType(Column),
          )
          .first,
    );
    final padTop = padRect.top;
    final padBottom = padRect.bottom;
    final aboveTitle = title.top - back.bottom;
    final belowPad = 568 - padBottom;
    expect(
      aboveTitle,
      greaterThan(10),
      reason: 'the top Spacer must still distribute free space',
    );
    expect(
      aboveTitle,
      closeTo(belowPad * 2, 2.0),
      reason:
          'the centred layout is flex 2 / flex 1 above and below the content '
          '(above $aboveTitle, below $belowPad)',
    );
    expect(padTop, greaterThan(title.bottom));
  });

  testWidgets('resizing and changing scale keeps the entered digits', (
    tester,
  ) async {
    useViewport(tester, const Size(320, 568));
    final harness = _Harness(
      const PrismTextScaler(TextScaler.linear(2.25), 1.5),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _launcher(
        service: _FakePinLockService(),
        settingsRepository: FakeSystemSettingsRepository(),
        harness: harness,
      ),
    );
    await tester.pumpAndSettle();
    await _openCaptureStep(tester);

    for (final digit in const ['1', '2', '3']) {
      await _tapDigit(tester, digit);
    }
    await tester.pumpAndSettle();
    expect(find.text('Set PIN'), findsOneWidget);

    // Shrink the window and drop to normal text while the sheet is mid-entry.
    tester.view.physicalSize = const Size(320, 360);
    await tester.pumpAndSettle();
    harness.update(
      textScaler: const PrismTextScaler(TextScaler.noScaling, 1.0),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Set PIN'), findsOneWidget);

    // Three more digits complete six: the buffer survived the relayout.
    for (final digit in const ['4', '5', '6']) {
      await _tapDigit(tester, digit);
    }
    await tester.pumpAndSettle();
    expect(find.text('Confirm PIN'), findsOneWidget);
  });
}
