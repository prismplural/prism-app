// PIN numpad keys under text scaling.
//
// A PIN key has to hold its digit at the size the user asked for. The digit keeps
// its font role (28pt headlineMedium on PinNumpadButton, 24pt on PinNumpadCell) at
// whatever scale the system and app sliders compose to, so the key grows with that
// glyph box in both axes: a fixed 72dp key (lockscreen) or 64dp key (change-PIN /
// sync) clipped it from about 1.8x, and growing only vertically would still clip a
// wide substituted digit.
//
// Every digit 0-9 is checked, in both bundled faces and under a nonlinear system
// scaler, because the key is sized from the widest/tallest digit rather than from
// one sample, and because a pad whose keys disagreed would show ragged rows.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_cell.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_metrics.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// System accessibility scaling that is not linear, like iOS/Android allow.
class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.4 : 28.0 + (fontSize - 20) * 3.0;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 3.0;
}

const _scales = <(String, TextScaler)>[
  (
    'system 100% x Prism 50% = 0.5x',
    PrismTextScaler(TextScaler.noScaling, 0.5),
  ),
  ('default text', PrismTextScaler(TextScaler.noScaling, 1.0)),
  ('large text 1.5x', PrismTextScaler(TextScaler.linear(1.5), 1.0)),
  (
    'system 225% x Prism 150% = 3.375x',
    PrismTextScaler(TextScaler.linear(2.25), 1.5),
  ),
  (
    'nonlinear system scaler x Prism 150%',
    PrismTextScaler(_NonLinearTextScaler(), 1.5),
  ),
];

const _fonts = <String>['Lexend', 'OpenDyslexic'];

Widget _app(
  Widget home, {
  required TextScaler textScaler,
  String font = 'Lexend',
  bool boldText = false,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        fontFamily: font,
        fontFamilyFallback: const ['NotoColorEmoji'],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: textScaler, boldText: boldText),
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

/// A whole keypad's worth of digit keys, as the pad renders them.
Widget _digitPad({required double size, required bool flatCell}) {
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final digit in kPinNumpadDigits)
          Builder(
            builder: (context) => flatCell
                ? PinNumpadCell(
                    label: digit,
                    onTap: () {},
                    theme: Theme.of(context),
                  )
                : PinNumpadButton(label: digit, onTap: () {}, size: size),
          ),
      ],
    ),
  );
}

RenderParagraph _digitParagraph(WidgetTester tester, String digit) {
  final finder = find.text(digit);
  expect(finder, findsOneWidget, reason: 'exactly one "$digit" key');
  return tester.renderObject<RenderParagraph>(finder);
}

/// Natural, unconstrained size of the digit as painted.
Size _naturalSize(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: TextSpan(
      text: paragraph.text.toPlainText(),
      style: paragraph.text.style,
    ),
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    maxLines: 1,
  )..layout();
  final size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}

void _expectEveryDigitPaintedWhole(
  WidgetTester tester, {
  required Type keyType,
  required String scaleLabel,
  required String font,
  required double minKeySize,
}) {
  final keySizes = <Size>{};
  for (final digit in kPinNumpadDigits) {
    final paragraph = _digitParagraph(tester, digit);
    final natural = _naturalSize(paragraph);

    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(natural.height - 0.5),
      reason:
          '$scaleLabel/$font: "$digit" needs ${natural.height.toStringAsFixed(1)}'
          'px of height but its key gives it '
          '${paragraph.size.height.toStringAsFixed(1)}px',
    );
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(natural.width - 0.5),
      reason:
          '$scaleLabel/$font: "$digit" needs ${natural.width.toStringAsFixed(1)}'
          'px of width but its key gives it '
          '${paragraph.size.width.toStringAsFixed(1)}px',
    );

    final digitRect = tester.getRect(find.text(digit));
    final keyRect = tester.getRect(
      find.ancestor(of: find.text(digit), matching: find.byType(keyType)).first,
    );
    keySizes.add(keyRect.size);
    if (keyType == PinNumpadButton) {
      final surface = find
          .ancestor(
            of: find.text(digit),
            matching: find.byType(TintedGlassSurface),
          )
          .first;
      final container = tester.widget<Container>(
        find.descendant(of: surface, matching: find.byType(Container)).first,
      );
      final border = (container.decoration! as BoxDecoration).border!;
      final insets = border.dimensions.resolve(TextDirection.ltr);
      // Exact real decoration budget on both axes; no half-pixel allowance.
      expect(
        keyRect.width - insets.horizontal,
        greaterThanOrEqualTo(natural.width),
      );
      expect(
        keyRect.height - insets.vertical,
        greaterThanOrEqualTo(natural.height),
      );
      expect(paragraph.size.width, greaterThanOrEqualTo(natural.width));
      expect(paragraph.size.height, greaterThanOrEqualTo(natural.height));
    }
    expect(keyRect.width, greaterThanOrEqualTo(minKeySize));
    expect(keyRect.height, greaterThanOrEqualTo(minKeySize));
    expect(
      digitRect.left,
      greaterThanOrEqualTo(keyRect.left - 0.5),
      reason: '$scaleLabel/$font: "$digit" painted outside its key (left)',
    );
    expect(
      digitRect.right,
      lessThanOrEqualTo(keyRect.right + 0.5),
      reason: '$scaleLabel/$font: "$digit" painted outside its key (right)',
    );
    expect(
      digitRect.top,
      greaterThanOrEqualTo(keyRect.top - 0.5),
      reason: '$scaleLabel/$font: "$digit" painted outside its key (top)',
    );
    expect(
      digitRect.bottom,
      lessThanOrEqualTo(keyRect.bottom + 0.5),
      reason: '$scaleLabel/$font: "$digit" painted outside its key (bottom)',
    );
  }
  expect(
    keySizes,
    hasLength(1),
    reason:
        '$scaleLabel/$font: every key in a pad must resolve to one extent, '
        'otherwise the rows are ragged',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  for (final (label, scaler) in _scales) {
    for (final font in _fonts) {
      testWidgets('64dp keys hold all ten digits ($label, $font)', (
        tester,
      ) async {
        _useViewport(tester, const Size(320, 568));
        await tester.pumpWidget(
          _app(
            Scaffold(body: _digitPad(size: 64, flatCell: false)),
            textScaler: scaler,
            font: font,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '$label/$font: no layout error',
        );
        _expectEveryDigitPaintedWhole(
          tester,
          keyType: PinNumpadButton,
          scaleLabel: label,
          font: font,
          minKeySize: 64,
        );
      });

      testWidgets('72dp keys hold all ten digits ($label, $font)', (
        tester,
      ) async {
        _useViewport(tester, const Size(320, 568));
        await tester.pumpWidget(
          _app(
            Scaffold(body: _digitPad(size: 72, flatCell: false)),
            textScaler: scaler,
            font: font,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '$label/$font: no layout error',
        );
        _expectEveryDigitPaintedWhole(
          tester,
          keyType: PinNumpadButton,
          scaleLabel: label,
          font: font,
          minKeySize: 72,
        );
      });

      testWidgets('flat cells hold all ten digits ($label, $font)', (
        tester,
      ) async {
        _useViewport(tester, const Size(320, 568));
        await tester.pumpWidget(
          _app(
            Scaffold(body: _digitPad(size: 72, flatCell: true)),
            textScaler: scaler,
            font: font,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '$label/$font: no layout error',
        );
        _expectEveryDigitPaintedWhole(
          tester,
          keyType: PinNumpadCell,
          scaleLabel: label,
          font: font,
          minKeySize: 72,
        );
      });
    }
  }

  for (final font in _fonts) {
    for (final (label, scaler) in [_scales[3], _scales[4]]) {
      testWidgets('glass interior resolves inherited style and bold '
          '($font, $label)', (tester) async {
        _useViewport(tester, const Size(320, 568));
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: font,
                  height: 1.3,
                  letterSpacing: 0.7,
                ),
                child: _digitPad(size: 72, flatCell: false),
              ),
            ),
            textScaler: scaler,
            font: font,
            boldText: true,
          ),
        );
        await tester.pumpAndSettle();
        for (final digit in kPinNumpadDigits) {
          expect(
            _digitParagraph(tester, digit).text.style!.fontWeight,
            FontWeight.bold,
          );
        }
        _expectEveryDigitPaintedWhole(
          tester,
          keyType: PinNumpadButton,
          scaleLabel: 'inherited/bold/$scaler',
          font: font,
          minKeySize: 72,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final font in _fonts) {
    testWidgets('metrics match ambient default style and bold paint ($font)', (
      tester,
    ) async {
      _useViewport(tester, const Size(500, 1000));
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: DefaultTextStyle(
              style: TextStyle(
                fontFamily: font,
                height: 1.3,
                letterSpacing: 0.7,
              ),
              child: Wrap(
                children: [
                  for (final digit in kPinNumpadDigits)
                    Builder(
                      builder: (context) {
                        const style = TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                        );
                        final extent = pinNumpadKeyExtent(
                          context,
                          size: 72,
                          style: style,
                        );
                        return TintedGlassSurface(
                          key: ValueKey('ambient-$digit'),
                          width: extent.width,
                          height: extent.height,
                          child: Text(digit, style: style),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          textScaler: const PrismTextScaler(_NonLinearTextScaler(), 1.5),
          font: font,
          boldText: true,
        ),
      );
      await tester.pumpAndSettle();
      for (final digit in kPinNumpadDigits) {
        final paragraph = _digitParagraph(tester, digit);
        expect(paragraph.text.style!.fontFamily, font);
        expect(paragraph.text.style!.height, 1.3);
        expect(paragraph.text.style!.letterSpacing, 0.7);
        expect(paragraph.text.style!.fontWeight, FontWeight.bold);
        final natural = _naturalSize(paragraph);
        final surface = find.byKey(ValueKey('ambient-$digit'));
        final container = tester.widget<Container>(
          find.descendant(of: surface, matching: find.byType(Container)).first,
        );
        final inset = (container.decoration! as BoxDecoration)
            .border!
            .dimensions
            .resolve(TextDirection.ltr);
        final rect = tester.getRect(surface);
        expect(
          rect.width - inset.horizontal,
          greaterThanOrEqualTo(natural.width),
        );
        expect(
          rect.height - inset.vertical,
          greaterThanOrEqualTo(natural.height),
        );
        expect(paragraph.size.width, greaterThanOrEqualTo(natural.width));
        expect(paragraph.size.height, greaterThanOrEqualTo(natural.height));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a small requested digit key still has a 44dp tap target', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: PinNumpadButton(label: '8', size: 24, onTap: () => taps++),
          ),
        ),
        textScaler: TextScaler.noScaling,
      ),
    );
    await tester.pumpAndSettle();
    final key = find.byType(PinNumpadButton);
    expect(tester.getSize(key).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(key).height, greaterThanOrEqualTo(44));
    expect(key.hitTestable(), findsOneWidget);
    await tester.tap(key);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default geometry is unchanged at normal text sizes', (
    tester,
  ) async {
    for (final (scaler, size) in const [
      (PrismTextScaler(TextScaler.noScaling, 1.0), 72.0),
      (PrismTextScaler(TextScaler.noScaling, 1.0), 64.0),
      (PrismTextScaler(TextScaler.linear(1.5), 1.0), 72.0),
      (PrismTextScaler(TextScaler.linear(1.5), 1.0), 64.0),
    ]) {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: Builder(
                builder: (context) =>
                    PinNumpadButton(label: '0', onTap: () {}, size: size),
              ),
            ),
          ),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PinNumpadButton)),
        Size(size, size),
        reason: 'a $size dp key stays square while every digit fits',
      );
    }
  });

  testWidgets('icon-only key keeps its square geometry and its semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => PinNumpadButton(
                icon: Icons.backspace_outlined,
                onTap: () {},
                size: 64,
                semanticLabel: 'Delete',
              ),
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.linear(2.25), 1.5),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PinNumpadButton)), const Size(64, 64));
    final semantics = tester.getSemantics(find.byType(PinNumpadButton));
    expect(semantics.label, contains('Delete'));
    expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
  });

  testWidgets('flat backspace cell keeps its tooltip and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => PinNumpadCell(
                icon: Icons.backspace_outlined,
                onTap: () {},
                theme: Theme.of(context),
              ),
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.linear(2.25), 1.5),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PinNumpadCell)), const Size(72, 72));
    expect(find.byType(Tooltip), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(PinNumpadCell));
    expect(semantics.label, isNotEmpty);
  });

  testWidgets('a grown 64dp key is still tappable and keeps its digit label', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) =>
                  PinNumpadButton(label: '3', onTap: () => taps++, size: 64),
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.linear(2.25), 1.5),
      ),
    );
    await tester.pumpAndSettle();

    final keyRect = tester.getRect(find.byType(PinNumpadButton));
    expect(keyRect.height, greaterThan(64));
    expect(keyRect.width, greaterThanOrEqualTo(64));

    await tester.tap(find.byType(PinNumpadButton));
    await tester.pump();
    expect(taps, 1);

    final semantics = tester.getSemantics(find.byType(PinNumpadButton));
    expect(semantics.label, contains('3'));
  });
}
