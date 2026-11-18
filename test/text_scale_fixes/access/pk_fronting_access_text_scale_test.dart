// Who's fronting? sheet: the defer action is reachable in a sheet that cannot be
// dismissed by drag or barrier, and the recommendation badge wraps inside its
// card at large text.
//
// The title and the option cards scroll inside the sheet body while "Decide
// later" is pinned below them, so the only non-mutating way out is one gesture
// away. The badge is capped to a share of the row so its word wraps instead of
// pushing the title to zero width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_fronter_choice_card.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_who_is_fronting_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

import 'access_text_scale_harness.dart';

const _localWren = (id: 'local-wren', name: 'Wren');
const _localNico = (id: 'local-nico', name: 'Nico');
const _pkAsh = (id: 'local-ash', name: 'Ash');

/// Opens the real non-dismissible sheet the way PluralKit sync does and keeps
/// the result the sheet returns.
class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.onResult});

  final void Function(Set<String>?) onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (buttonContext) => TextButton(
            onPressed: () async {
              final result = await PkWhoIsFrontingSheet.show(
                context: buttonContext,
                localFronters: const [_localWren, _localNico],
                pkFronters: const [_pkAsh],
                direction: PkSyncDirection.bidirectional,
              );
              onResult(result);
            },
            child: const Text('open sheet'),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadAccessFonts);

  testWidgets(
    'default text on a compact phone: the defer action is inside the sheet, '
    'tapping it closes the sheet without choosing a fronter',
    (tester) async {
      useWindow(tester, compactPhone);
      Set<String>? result;
      var closed = false;
      await tester.pumpWidget(
        accessApp(
          _SheetHost(
            onResult: (value) {
              result = value;
              closed = true;
            },
          ),
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final defer = find.text('Decide later');
      final deferRect = tester.getRect(defer);
      expect(deferRect.top, greaterThanOrEqualTo(0));
      expect(
        deferRect.bottom,
        lessThanOrEqualTo(compactPhone.height),
        reason: 'the safe, non-mutating exit must be on the sheet',
      );

      // Non-dismissible by drag and barrier: pulling down on the body must not
      // close the sheet (unchanged dismissal semantics).
      await tester.drag(find.text("Who's fronting?"), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('Decide later'), findsOneWidget);

      await tester.tap(defer);
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull, reason: '"Decide later" defers, it does not pick');
      expect(find.byType(PkFronterChoiceCard), findsNothing);
    },
  );

  testWidgets(
    'composed 3.375x on a compact phone: the defer action stays reachable and '
    'a choice further down the card list can still be scrolled to and taken',
    (tester) async {
      useWindow(tester, compactPhone);
      Set<String>? result;
      var closed = false;
      await tester.pumpWidget(
        accessApp(
          _SheetHost(
            onResult: (value) {
              result = value;
              closed = true;
            },
          ),
          systemScaler: maxSystemScaler,
          appFontScale: maxAppFontScale,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a choice card row must not overflow: the recommendation badge is '
            'capped to a share of the row so its word wraps beside the title.',
      );

      final deferRect = tester.getRect(find.text('Decide later'));
      expect(deferRect.top, greaterThanOrEqualTo(0));
      expect(
        deferRect.bottom,
        lessThanOrEqualTo(compactPhone.height),
        reason:
            '"Decide later" must be inside the sheet: the cards scroll above it '
            'and the defer action is pinned.',
      );

      // The body scrolls, so a card below the fold is still usable.
      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);
      final lastCard = find.byType(PkFronterChoiceCard).last;
      await tester.scrollUntilVisible(lastCard, 160, scrollable: scrollable);
      await tester.tap(lastCard);
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, equals({'local-ash'}));
    },
  );

  testWidgets(
    'composed 3.375x: the recommendation badge stays inside its card at full '
    'size instead of overflowing the row',
    (tester) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        accessApp(
          _SheetHost(onResult: (_) {}),
          systemScaler: maxSystemScaler,
          appFontScale: maxAppFontScale,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      final badge = find.text('Recommended');
      expect(badge, findsOneWidget);

      // Not ellipsised and not clipped: the word keeps its requested size.
      final badgeText = tester.widget<Text>(badge);
      expect(badgeText.maxLines, isNull);
      expect(badgeText.overflow, isNull);

      final cardRect = tester.getRect(
        find.ancestor(of: badge, matching: find.byType(PrismSurface)).first,
      );
      final badgeRect = tester.getRect(badge);
      expect(badgeRect.left, greaterThanOrEqualTo(cardRect.left - 0.5));
      expect(
        badgeRect.right,
        lessThanOrEqualTo(cardRect.right + 0.5),
        reason: 'the badge must stay inside its card.',
      );

      // The badge wraps rather than shrinking: measured from the paragraph it
      // actually renders, the whole word is laid out at the requested size.
      final paragraph = paragraphOf(tester, badge);
      final needed = paragraphMaxIntrinsicHeight(paragraph);
      expect(
        paragraph.size.height + 0.5,
        greaterThanOrEqualTo(needed),
        reason:
            'the badge must keep the whole word at the requested size (needs '
            '${needed.toStringAsFixed(1)}dp, has '
            '${paragraph.size.height.toStringAsFixed(1)}dp)',
      );
    },
  );

  testWidgets(
    'composed 1.5x on a compact phone: cards and defer action all fit',
    (tester) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        accessApp(
          _SheetHost(onResult: (_) {}),
          systemScaler: const TextScaler.linear(1.0),
          appFontScale: 1.5,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final deferRect = tester.getRect(find.text('Decide later'));
      expect(deferRect.bottom, lessThanOrEqualTo(compactPhone.height));
      for (final element in find.byType(PkFronterChoiceCard).evaluate()) {
        final box = element.renderObject! as RenderBox;
        expect(box.size.height, greaterThan(0));
      }
    },
  );

  testWidgets('wide layout at 3.375x: the badge stays inside its card and the '
      'defer action stays on the sheet', (tester) async {
    useWindow(tester, wideDesktop);
    await tester.pumpWidget(
      accessApp(
        _SheetHost(onResult: (_) {}),
        systemScaler: maxSystemScaler,
        appFontScale: maxAppFontScale,
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final badge = find.text('Recommended');
    final badgeText = tester.widget<Text>(badge);
    expect(badgeText.overflow, isNull);
    final badgeRect = tester.getRect(badge);
    final cardRect = tester.getRect(
      find.ancestor(of: badge, matching: find.byType(PrismSurface)).first,
    );
    expect(badgeRect.right, lessThanOrEqualTo(cardRect.right + 0.5));

    final deferRect = tester.getRect(find.text('Decide later'));
    expect(deferRect.top, greaterThanOrEqualTo(0));
    expect(deferRect.bottom, lessThanOrEqualTo(wideDesktop.height));
  });
}
