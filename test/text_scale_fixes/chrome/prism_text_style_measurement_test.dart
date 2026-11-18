// Measurement parity for the shared text-style helper.
//
// The bars size themselves from a `TextPainter`, so the painter's style must be the
// one the `Text` really paints with: `Text.build` merges the ambient
// `DefaultTextStyle` only when the given style is null or `inherit`, then applies
// `MediaQuery.boldText` as w700, and `RichText` resolves the locale and the inherited
// `TextHeightBehavior`. `prismTextStyleForMeasurement` mirrors those steps; these
// cases compare its output, and the heights measured from it, with a rendered `Text`.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';

import 'chrome_text_scale_harness.dart';

const _family = 'OpenDyslexic';

Widget _app(
  Widget child, {
  required TextStyle inherited,
  bool boldText = false,
  Locale locale = const Locale('en'),
  TextHeightBehavior? textHeightBehavior,
}) {
  return MaterialApp(
    theme: chromeTheme(_family),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    builder: (context, home) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.0), boldText: boldText),
      child: DefaultTextStyle(
        style: inherited,
        textHeightBehavior: textHeightBehavior,
        child: home ?? const SizedBox.shrink(),
      ),
    ),
    home: child,
  );
}

/// The style the rendered paragraph ended up with.
TextStyle _paintedStyle(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  return paragraph.text.style!;
}

/// The style the helper reports for the same context.
TextStyle _measuredStyle(WidgetTester tester, String text) {
  final context = tester.element(find.text(text));
  final painted = _paintedStyle(tester, text);
  return prismTextStyleForMeasurement(context, painted);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  testWidgets('an inheriting style measures the text it paints', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const inherited = TextStyle(fontSize: 20, color: Colors.black);
    const style = TextStyle(fontSize: 15, height: 1.2);
    await tester.pumpWidget(
      _app(
        const Center(child: Text('Members', style: style)),
        inherited: inherited,
      ),
    );
    await tester.pumpAndSettle();

    final measured = _measuredStyle(tester, 'Members');
    expect(measured.fontSize, 15);
    expect(measured.height, 1.2);
    // The default family wins where the given style leaves it null, exactly as the
    // painted paragraph resolved it.
    expect(measured.fontFamily, _paintedStyle(tester, 'Members').fontFamily);
    expect(
      prismLineHeight(
        tester.element(find.text('Members')),
        style,
        text: 'Members',
      ),
      closeTo(
        tester.renderObject<RenderParagraph>(find.text('Members')).size.height,
        0.01,
      ),
      reason: 'the measured line box is the painted line box',
    );
  });

  testWidgets(
    'an explicit inherit:false style does not take the default style',
    (tester) async {
      useWindow(tester, compactPhone);
      const inherited = TextStyle(fontFamily: 'Lexend', fontSize: 20);
      const style = TextStyle(
        inherit: false,
        fontFamily: _family,
        fontSize: 15,
        color: Colors.black,
      );
      await tester.pumpWidget(
        _app(
          const Center(child: Text('Members', style: style)),
          inherited: inherited,
        ),
      );
      await tester.pumpAndSettle();

      final measured = _measuredStyle(tester, 'Members');
      expect(
        measured.fontSize,
        15,
        reason: 'inherit:false keeps its own size, not the default 20',
      );
      expect(measured.fontFamily, _family);
      expect(measured.fontFamily, _paintedStyle(tester, 'Members').fontFamily);
    },
  );

  testWidgets('bold text is applied as w700 for measurement too', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const inherited = TextStyle(fontSize: 16);
    const style = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
    await tester.pumpWidget(
      _app(
        const Center(child: Text('Members', style: style)),
        inherited: inherited,
        boldText: true,
      ),
    );
    await tester.pumpAndSettle();

    final measured = _measuredStyle(tester, 'Members');
    expect(measured.fontWeight, FontWeight.bold);
    expect(measured.fontWeight, _paintedStyle(tester, 'Members').fontWeight);
    expect(
      prismLineHeight(
        tester.element(find.text('Members')),
        style,
        text: 'Members',
      ),
      closeTo(
        tester.renderObject<RenderParagraph>(find.text('Members')).size.height,
        0.01,
      ),
      reason: 'a bold paragraph is measured at the bold line box',
    );
  });

  testWidgets('an inherited TextHeightBehavior changes the measured line box', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const inherited = TextStyle(fontSize: 18, height: 2.0);
    const style = TextStyle(fontSize: 18, height: 2.0);
    const behaviour = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    await tester.pumpWidget(
      _app(
        const Center(child: Text('Members', style: style)),
        inherited: inherited,
        textHeightBehavior: behaviour,
      ),
    );
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Members'),
    );
    expect(
      prismLineHeight(
        tester.element(find.text('Members')),
        style,
        text: 'Members',
      ),
      closeTo(paragraph.size.height, 0.01),
      reason:
          'the helper passes the inherited textHeightBehavior, so the measurement '
          'matches the paragraph it will paint',
    );
  });

  testWidgets('a locale-dependent string measures as it paints', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const inherited = TextStyle(fontSize: 18);
    const style = TextStyle(fontSize: 18);
    const text = 'نور 中文';
    for (final locale in const [Locale('en'), Locale('es')]) {
      await tester.pumpWidget(
        _app(
          const Center(child: Text(text, style: style)),
          inherited: inherited,
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(
        prismLineHeight(tester.element(find.text(text)), style, text: text),
        closeTo(paragraph.size.height, 0.01),
        reason: 'locale $locale: the measured line box is the painted one',
      );
      expect(
        prismTextInkEscape(tester.element(find.text(text)), style, text: text),
        greaterThanOrEqualTo(0.0),
      );
    }
  });

  testWidgets('ordinary theme styles are unchanged by the helper', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const inherited = TextStyle(fontFamily: _family, fontSize: 14);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            // A settings-provided style (concrete family and size, inherit true).
            final style = TextStyle(
              fontFamily: _family,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            );
            final measured = prismTextStyleForMeasurement(context, style);
            expect(measured.fontFamily, _family);
            expect(measured.fontSize, 17);
            expect(measured.fontWeight, FontWeight.w500);
            return const SizedBox.shrink();
          },
        ),
        inherited: inherited,
      ),
    );
    await tester.pumpAndSettle();
  });
}
