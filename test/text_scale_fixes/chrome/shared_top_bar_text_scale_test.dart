// `PrismTopBar` in a pinned header.
//
// The bar is 66dp whenever its content fits there, and grows with the ambient text
// scale when it does not: the title is laid out and painted at the size the user
// asked for (one ellipsised line, full string in its semantics) instead of being
// shrunk to fit, and the pinned band is sized from the same measurement so the bar
// never paints outside it.
//
// Asserted through the app's real mount (`PrismPageScaffold(topBar:)` ->
// `SliverPinnedTopBar` -> `SliverPersistentHeader`):
//   - the title is laid out, painted at the requested size and clear of the actions,
//   - the bar/header height contains it,
//   - 66dp stays exactly 66 whenever the text really fits it, and the bar grows
//     when it does not (decided by the measured block, not by a scale threshold),
//   - the bar re-measures when the text scale changes on a live tree,
//   - RTL, a nonlinear scaler and a wide window behave the same,
//   - a fallback face's ink stays inside the bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

import 'chrome_text_scale_harness.dart';

Widget _page({
  required String title,
  String? subtitle,
  bool showBackButton = true,
}) {
  return PrismPageScaffold(
    topBar: PrismTopBar(
      title: title,
      subtitle: subtitle,
      showBackButton: showBackButton,
      actions: [
        PrismTopBarAction(icon: AppIcons.add, tooltip: 'Add', onPressed: () {}),
      ],
    ),
    body: ListView.builder(
      itemCount: 40,
      itemBuilder: (context, index) =>
          SizedBox(height: 48, child: Text('Row $index')),
    ),
  );
}

Widget _app(
  Widget page, {
  required double system,
  required double app,
  required String family,
  TextDirection? textDirection,
}) {
  return ProviderScope(
    child: chromeApp(
      page,
      system: system,
      app: app,
      fontFamily: family,
      textDirection: textDirection,
    ),
  );
}

/// The bar must never paint its title over a leading or trailing action.
void _expectTitleClearOfActions(
  WidgetTester tester, {
  required Rect titleRect,
  required String label,
}) {
  final actions = find.byType(PrismTopBarAction);
  for (var i = 0; i < actions.evaluate().length; i++) {
    final rect = tester.getRect(find.byType(PrismTopBarAction).at(i));
    final overlapsHorizontally =
        titleRect.left < rect.right - 0.5 && titleRect.right > rect.left + 0.5;
    expect(
      overlapsHorizontally,
      isFalse,
      reason:
          '$label: the title (${titleRect.left.toStringAsFixed(1)}..'
          '${titleRect.right.toStringAsFixed(1)}) paints under action $i '
          '(${rect.left.toStringAsFixed(1)}..${rect.right.toStringAsFixed(1)})',
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  for (final family in chromeFontFamilies) {
    for (final (system, app, label) in chromeScales) {
      final scaleLabel = '$label, $family';

      testWidgets('PrismTopBar keeps its title inside the pinned header '
          '($scaleLabel)', (tester) async {
        useWindow(tester, compactPhone);
        const title = 'Members';
        await tester.pumpWidget(
          _app(
            _page(title: title),
            system: system,
            app: app,
            family: family,
          ),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(PrismTopBar));
        expect(
          barRect.height,
          greaterThanOrEqualTo(PrismTokens.topBarHeight - 0.5),
          reason: '$scaleLabel: the bar may never reserve less than 66dp',
        );
        // Whether 66dp survives is decided by what the text actually needs, not by
        // a scale threshold: a face whose ink escapes its line box needs more room
        // even at 1.5x, and one that fits needs none.
        final natural = naturalBarBlockHeight(tester, title: title);
        if (natural <= PrismTokens.topBarHeight + 0.01) {
          expect(
            barRect.height,
            closeTo(PrismTokens.topBarHeight, 0.5),
            reason:
                '$scaleLabel: the block needs ${natural.toStringAsFixed(1)}px, so '
                'the default 66dp must be preserved exactly',
          );
        } else {
          expect(
            barRect.height,
            greaterThanOrEqualTo(natural - 0.5),
            reason:
                '$scaleLabel: the block needs ${natural.toStringAsFixed(1)}px, so '
                'the bar must grow to it',
          );
        }

        final titleRect = expectFullSizeText(
          tester,
          title,
          label: scaleLabel,
          container: barRect,
        );
        _expectTitleClearOfActions(
          tester,
          titleRect: titleRect,
          label: scaleLabel,
        );
        expectNoLayoutException(tester, scaleLabel);
      });

      testWidgets('PrismTopBar keeps a title with a subtitle '
          '($scaleLabel)', (tester) async {
        useWindow(tester, compactPhone);
        const title = 'Timeline';
        const subtitle = '12 headmates';
        await tester.pumpWidget(
          _app(
            _page(title: title, subtitle: subtitle),
            system: system,
            app: app,
            family: family,
          ),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(PrismTopBar));
        final natural = naturalBarBlockHeight(
          tester,
          title: title,
          subtitle: subtitle,
        );
        if (natural <= PrismTokens.topBarHeight + 0.01) {
          expect(
            barRect.height,
            closeTo(PrismTokens.topBarHeight, 0.5),
            reason:
                '$scaleLabel: title plus subtitle need '
                '${natural.toStringAsFixed(1)}px, so 66dp must be preserved '
                'exactly',
          );
        } else {
          expect(
            barRect.height,
            greaterThanOrEqualTo(natural - 0.5),
            reason:
                '$scaleLabel: title plus subtitle need '
                '${natural.toStringAsFixed(1)}px, so the bar must grow to it',
          );
        }
        final titleRect = expectFullSizeText(
          tester,
          title,
          label: '$scaleLabel (title)',
          container: barRect,
        );
        expectFullSizeText(
          tester,
          subtitle,
          label: '$scaleLabel (subtitle)',
          container: barRect,
        );
        _expectTitleClearOfActions(
          tester,
          titleRect: titleRect,
          label: scaleLabel,
        );
        expectNoLayoutException(tester, scaleLabel);
      });

      testWidgets('PrismTopBar paints a long title at the requested size '
          '($scaleLabel)', (tester) async {
        useWindow(tester, compactPhone);
        const title = 'Fronting schedule today';
        await tester.pumpWidget(
          _app(
            _page(title: title),
            system: system,
            app: app,
            family: family,
          ),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(PrismTopBar));
        final titleRect = expectFullSizeText(
          tester,
          title,
          label: scaleLabel,
          container: barRect,
        );
        _expectTitleClearOfActions(
          tester,
          titleRect: titleRect,
          label: scaleLabel,
        );
        expectNoLayoutException(tester, scaleLabel);
      });
    }
  }

  testWidgets('PrismTopBar re-measures when the text scale changes on a live '
      'tree', (tester) async {
    useWindow(tester, compactPhone);
    const title = 'Members';
    final page = _page(title: title, subtitle: '12 headmates');

    await tester.pumpWidget(
      _app(page, system: 1.0, app: 1.0, family: 'Lexend'),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(PrismTopBar)).height;
    expect(before, closeTo(PrismTokens.topBarHeight, 0.5));

    await tester.pumpWidget(
      _app(page, system: 2.25, app: 1.5, family: 'Lexend'),
    );
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(PrismTopBar)).height;
    expect(
      after,
      greaterThan(before),
      reason: 'the bar must follow the new text scale, not a cached height',
    );
    final barRect = tester.getRect(find.byType(PrismTopBar));
    expectFullSizeText(
      tester,
      title,
      label: 'after scale change',
      container: barRect,
    );
    expectFullSizeText(
      tester,
      '12 headmates',
      label: 'after scale change (subtitle)',
      container: barRect,
    );
    expectNoLayoutException(tester, 'after scale change');
  });

  testWidgets('PrismTopBar contains its title on a nonlinear scaler', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const title = 'Members';
    await tester.pumpWidget(
      ProviderScope(
        child: chromeApp(
          _page(title: title, subtitle: '12 headmates'),
          system: 1.0,
          app: 1.0,
          scalerOverride: const NonlinearTextScaler(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismTopBar));
    expectFullSizeText(tester, title, label: 'nonlinear', container: barRect);
    expectFullSizeText(
      tester,
      '12 headmates',
      label: 'nonlinear (subtitle)',
      container: barRect,
    );
    expectNoLayoutException(tester, 'nonlinear');
  });

  testWidgets('PrismTopBar keeps the title between the actions in RTL', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    const title = 'Members';
    await tester.pumpWidget(
      _app(
        _page(title: title),
        system: 2.25,
        app: 1.5,
        family: 'Lexend',
        textDirection: TextDirection.rtl,
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismTopBar));
    final titleRect = expectFullSizeText(
      tester,
      title,
      label: 'RTL',
      container: barRect,
    );
    _expectTitleClearOfActions(tester, titleRect: titleRect, label: 'RTL');
    expectNoLayoutException(tester, 'RTL');
  });

  testWidgets('PrismTopBar keeps the default height and a full-size title on '
      'a wide window', (tester) async {
    useWindow(tester, wideWindow);
    const title = 'Fronting schedule today';
    await tester.pumpWidget(
      _app(_page(title: title), system: 1.5, app: 1.0, family: 'Lexend'),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismTopBar));
    final natural = naturalBarBlockHeight(tester, title: title);
    if (natural <= PrismTokens.topBarHeight + 0.01) {
      expect(
        barRect.height,
        closeTo(PrismTokens.topBarHeight, 0.5),
        reason:
            'the 18pt desktop title needs ${natural.toStringAsFixed(1)}px at 1.5x, '
            'so 66dp must hold',
      );
    } else {
      expect(
        barRect.height,
        greaterThanOrEqualTo(natural - 0.5),
        reason: 'the wide bar must grow to the ink it paints',
      );
    }
    final titleRect = expectFullSizeText(
      tester,
      title,
      label: 'wide 1.5x',
      container: barRect,
    );
    _expectTitleClearOfActions(
      tester,
      titleRect: titleRect,
      label: 'wide 1.5x',
    );
    expectNoLayoutException(tester, 'wide 1.5x');
  });

  // The bar's height comes from the line box of the text it will paint, and a run
  // resolved to a fallback face (emoji, CJK, Arabic) can report a taller line box
  // and draw ink beyond the primary face's. These cases check the ink the
  // paragraph actually paints, not just its box, at both ends of the scale.
  for (final family in chromeFontFamilies) {
    for (final (system, app, label) in chromeScales) {
      testWidgets('mixed-script title and subtitle ink stays inside the bar '
          '($label, $family)', (tester) async {
        useWindow(tester, compactPhone);
        const title = 'ÉÅgjpq 🜁';
        const subtitle = 'نور 中文 ١٢';
        await tester.pumpWidget(
          _app(
            _page(title: title, subtitle: subtitle),
            system: system,
            app: app,
            family: family,
          ),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(PrismTopBar));
        expectFullSizeText(
          tester,
          title,
          label: '$label (mixed title)',
          container: barRect,
        );
        expectFullSizeText(
          tester,
          subtitle,
          label: '$label (mixed subtitle)',
          container: barRect,
        );
        expectInkInside(
          tester,
          title,
          container: barRect,
          label: '$label (mixed title)',
        );
        expectInkInside(
          tester,
          subtitle,
          container: barRect,
          label: '$label (mixed subtitle)',
        );
        expect(
          tester.getRect(find.text(title)).width,
          greaterThan(0),
          reason: 'the mixed-script title must render glyphs',
        );
        expectNoLayoutException(tester, '$label (mixed script)');
      });
    }
  }
}
