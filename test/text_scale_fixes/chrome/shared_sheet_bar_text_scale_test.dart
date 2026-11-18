// `PrismSheetTopBar` in the compositions its call sites use
// (`SafeArea > Column > [bar, Expanded(body)]`, plus the `SliverToBoxAdapter` form
// `member_search_sheet` uses).
//
// The bar is at least 66dp and grows to contain its title: one ellipsised line at
// the requested size, inset between the action slots so it cannot paint under
// them, measured from the same text it paints.
//   - the bar is at least 66dp and grows to contain its own title,
//   - the title is laid out and painted at the requested size, inside the bar,
//   - the title never paints under the leading/trailing action,
//   - a short window with the keyboard up still lays out the body,
//   - the bar re-measures when the text scale changes on a live tree.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

import 'chrome_text_scale_harness.dart';

const _trailingKey = Key('sheetBarTrailing');

Widget _bar({required String title, bool trailing = true}) {
  return PrismSheetTopBar(
    title: title,
    trailing: trailing
        ? PrismGlassIconButton(
            key: _trailingKey,
            icon: AppIcons.check,
            tooltip: 'Done',
            size: PrismTokens.topBarActionSize,
            onPressed: () {},
          )
        : null,
  );
}

Widget _columnSheet({
  required String title,
  bool trailing = true,
  double bodyHeight = 400,
}) {
  return Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          _bar(title: title, trailing: trailing),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                key: const Key('sheetBody'),
                height: bodyHeight,
                child: const Text('body'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _sliverSheet({required String title}) {
  return Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _bar(title: title)),
        const SliverToBoxAdapter(
          child: SizedBox(
            key: Key('sheetBody'),
            height: 400,
            child: Text('body'),
          ),
        ),
      ],
    ),
  );
}

Widget _app(
  Widget sheet, {
  required double system,
  required double app,
  required String family,
}) {
  return ProviderScope(
    child: chromeApp(sheet, system: system, app: app, fontFamily: family),
  );
}

void _expectTitleClearOfTrailing(
  WidgetTester tester, {
  required Rect titleRect,
  required String label,
}) {
  final trailing = find.byKey(_trailingKey);
  if (trailing.evaluate().isEmpty) return;
  final trailingRect = tester.getRect(trailing);
  expect(
    titleRect.right,
    lessThanOrEqualTo(trailingRect.left + 0.5),
    reason:
        '$label: the title runs under the trailing action '
        '(${titleRect.right.toStringAsFixed(1)} > ${trailingRect.left.toStringAsFixed(1)})',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  for (final family in chromeFontFamilies) {
    for (final (system, app, label) in chromeScales) {
      final scaleLabel = '$label, $family';

      testWidgets('PrismSheetTopBar contains its title in a sheet column '
          '($scaleLabel)', (tester) async {
        useWindow(tester, compactPhone);
        const title = 'Edit fronting session';
        await tester.pumpWidget(
          _app(
            _columnSheet(title: title),
            system: system,
            app: app,
            family: family,
          ),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(PrismSheetTopBar));
        expect(
          barRect.height,
          greaterThanOrEqualTo(PrismTokens.topBarHeight - 0.5),
          reason: '$scaleLabel: the sheet bar may never reserve less than 66dp',
        );
        // Fit, not a scale threshold: a face whose ink escapes its line box needs
        // more than 66dp even at 1.5x.
        final natural = naturalBarBlockHeight(tester, title: title);
        if (natural <= PrismTokens.topBarHeight + 0.01) {
          expect(
            barRect.height,
            closeTo(PrismTokens.topBarHeight, 0.5),
            reason:
                '$scaleLabel: the title needs ${natural.toStringAsFixed(1)}px, so '
                '66dp must be preserved exactly',
          );
        } else {
          expect(
            barRect.height,
            greaterThanOrEqualTo(natural - 0.5),
            reason:
                '$scaleLabel: the title needs ${natural.toStringAsFixed(1)}px, so '
                'the bar must grow to it',
          );
        }
        final titleRect = expectFullSizeText(
          tester,
          title,
          label: scaleLabel,
          container: barRect,
        );
        _expectTitleClearOfTrailing(
          tester,
          titleRect: titleRect,
          label: scaleLabel,
        );

        final bodyRect = tester.getRect(find.byKey(const Key('sheetBody')));
        expect(
          bodyRect.top,
          greaterThanOrEqualTo(barRect.bottom - 0.5),
          reason: '$scaleLabel: the body starts under the bar',
        );
        expectNoLayoutException(tester, scaleLabel);
      });

      testWidgets('PrismSheetTopBar keeps its title in a scrolling sliver '
          '($scaleLabel)', (tester) async {
        useWindow(tester, compactPhone);
        const title = 'Add members to this group conversation';
        await tester.pumpWidget(
          _app(
            _sliverSheet(title: title),
            system: system,
            app: app,
            family: family,
          ),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(PrismSheetTopBar));
        final titleRect = expectFullSizeText(
          tester,
          title,
          label: '$scaleLabel (sliver)',
          container: barRect,
        );
        _expectTitleClearOfTrailing(
          tester,
          titleRect: titleRect,
          label: '$scaleLabel (sliver)',
        );
        expectNoLayoutException(tester, '$scaleLabel (sliver)');
      });
    }
  }

  testWidgets('PrismSheetTopBar leaves the body a laid-out area on a short '
      'window with the keyboard up', (tester) async {
    useWindow(tester, compactPhone, keyboardInset: 260);
    const title = 'Edit fronting session';
    await tester.pumpWidget(
      _app(
        _columnSheet(title: title),
        system: 2.25,
        app: 1.5,
        family: 'Lexend',
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byType(PrismSheetTopBar));
    expectFullSizeText(
      tester,
      title,
      label: 'short window',
      container: barRect,
    );
    final bodyRect = tester.getRect(find.byKey(const Key('sheetBody')));
    expect(
      bodyRect.top,
      greaterThanOrEqualTo(barRect.bottom - 0.5),
      reason: 'the body must start under the bar, not overlap it',
    );
    expectNoLayoutException(tester, 'short window');
  });

  testWidgets('PrismSheetTopBar re-measures when the text scale changes on a '
      'live tree', (tester) async {
    useWindow(tester, compactPhone);
    const title = 'Edit fronting session';
    final sheet = _columnSheet(title: title);

    await tester.pumpWidget(
      _app(sheet, system: 1.0, app: 1.0, family: 'Lexend'),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(PrismSheetTopBar)).height;
    expect(before, closeTo(PrismTokens.topBarHeight, 0.5));

    await tester.pumpWidget(
      _app(sheet, system: 2.25, app: 1.5, family: 'Lexend'),
    );
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(PrismSheetTopBar)).height;
    expect(
      after,
      greaterThan(before),
      reason: 'the sheet bar must follow the new text scale',
    );
    expectFullSizeText(
      tester,
      title,
      label: 'sheet bar after scale change',
      container: tester.getRect(find.byType(PrismSheetTopBar)),
    );
    expectNoLayoutException(tester, 'sheet bar after scale change');
  });
}
