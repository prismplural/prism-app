// PinInputScreen must reflow on the height it actually has. It scrolls when the
// content does not fit and keeps its centred Spacer layout when it does, so:
//
//  * a 320x360 window at NORMAL text stays usable even though the pad is taller
//    than the window;
//  * with an open keyboard (viewInsets.bottom) the pad ends above the inset
//    instead of being hidden behind it;
//  * a 320x568 phone at 1x keeps the existing layout untouched.
//
// The keyboard inset is reserved once: a parent that has already shrunk the body
// for it (Scaffold's resizeToAvoidBottomInset) must not be subtracted from twice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_metrics.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

Widget _app(
  Widget home, {
  TextScaler textScaler = const PrismTextScaler(TextScaler.noScaling, 1.0),
  double keyboardInset = 0,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        fontFamily: 'Lexend',
        fontFamilyFallback: const ['NotoColorEmoji'],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    ),
  );
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _tapKey(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  testWidgets('1x on a 320x360 window: the pad scrolls and stays usable', (
    tester,
  ) async {
    _useViewport(tester, const Size(320, 360));
    String? entered;

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: PinInputScreen(
            mode: PinInputMode.set,
            allowBiometric: false,
            onPinEntered: (pin) => entered = pin,
            onSuccess: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no layout error');
    expect(
      find.byType(SingleChildScrollView),
      findsWidgets,
      reason:
          'a 320x360 window at 1x is shorter than the pad plus its header, so '
          'the screen must scroll instead of laying the last row out below the '
          'bottom edge',
    );

    for (final digit in kPinNumpadDigits.take(6)) {
      await _tapKey(tester, find.text(digit).first);
    }
    expect(entered, '012345');
  });

  testWidgets('1x with an open keyboard: keys stay above the inset', (
    tester,
  ) async {
    _useViewport(tester, const Size(320, 568));
    const inset = 260.0;

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: PinInputScreen(
            mode: PinInputMode.set,
            allowBiometric: false,
            onPinEntered: (_) {},
            onSuccess: () {},
          ),
        ),
        keyboardInset: inset,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no layout error');

    // Reachability is proven by driving the keys, not by an unrendered rect: scroll
    // the last row into view above the inset and tap it.
    final zeroFinder = find.text('0').first;
    await tester.ensureVisible(zeroFinder);
    await tester.pumpAndSettle();
    final zero = tester.getRect(
      find
          .ancestor(of: zeroFinder, matching: find.byType(PinNumpadButton))
          .first,
    );
    expect(
      zero.bottom,
      lessThanOrEqualTo(568 - inset + 0.5),
      reason:
          'the pad must sit above the keyboard inset (zero key bottom '
          '${zero.bottom.toStringAsFixed(1)})',
    );
    await tester.tap(zeroFinder);
    await tester.pumpAndSettle();

    final backspaceFinder = find.byIcon(AppIcons.backspaceOutlined).first;
    await tester.ensureVisible(backspaceFinder);
    await tester.pumpAndSettle();
    final backspace = tester.getRect(backspaceFinder);
    expect(
      backspace.bottom,
      lessThanOrEqualTo(568 - inset + 0.5),
      reason: 'the backspace key must sit above the keyboard inset',
    );
    await tester.tap(backspaceFinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('1x on a normal phone: the existing layout still fits', (
    tester,
  ) async {
    _useViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: PinInputScreen(
            mode: PinInputMode.set,
            allowBiometric: false,
            onPinEntered: (_) {},
            onSuccess: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final digit in kPinNumpadDigits) {
      final rect = tester.getRect(find.text(digit).first);
      expect(
        rect.bottom,
        lessThanOrEqualTo(568),
        reason: '"$digit" must be on screen at 1x on a 320x568 phone',
      );
    }
  });
}
