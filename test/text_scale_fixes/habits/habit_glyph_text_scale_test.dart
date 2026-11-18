import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/habits/widgets/habit_chip.dart';
import 'package:prism_plurality/features/habits/widgets/habit_row.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size < 20 ? size * 2.7 : size * 3.2;
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 3.2;
}

void main() {
  setUpAll(loadPrismGoldenFonts);
  for (final family in ['Lexend', 'OpenDyslexic']) {
    for (final scale in [0.5, 1.0, 1.5, 3.375, -1.0]) {
      for (final compact in [false, true]) {
        testWidgets(
          '$family ${compact ? 'chip' : 'row'} glyph fits at $scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(320, 568);
            addTearDown(tester.view.reset);
            final scaler = scale == -1.0
                ? const _NonlinearScaler()
                : PrismTextScaler(
                    TextScaler.linear(scale == 3.375 ? 2.25 : 1),
                    scale == 3.375 ? 1.5 : scale,
                  );
            var quick = 0;
            var opened = 0;
            final habit = Habit(
              id: 'synthetic-habit',
              name: 'Water',
              icon: '🎯',
              frequency: HabitFrequency.daily,
              createdAt: DateTime(2026, 1, 1),
              modifiedAt: DateTime(2026, 1, 1),
            );
            final child = compact
                ? HabitChip(
                    habit: habit,
                    todayCompletions: const [],
                    onTap: () => opened++,
                    onQuickComplete: () async {
                      quick++;
                    },
                  )
                : HabitRow(
                    habit: habit,
                    todayCompletions: const [],
                    onTap: () => opened++,
                    onQuickComplete: () async {
                      quick++;
                    },
                  );
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  fontFamily: family,
                  fontFamilyFallback: const ['NotoColorEmoji'],
                  extensions: const [PrismShapes.rounded],
                ),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: const [Locale('en')],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: scaler),
                  child: child!,
                ),
                home: Scaffold(body: SingleChildScrollView(child: child)),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final glyph = find.text('🎯');
            final paragraph = tester.renderObject<RenderParagraph>(glyph);
            final natural = TextPainter(
              text: paragraph.text,
              textScaler: paragraph.textScaler,
              textDirection: paragraph.textDirection,
              locale: paragraph.locale,
              maxLines: 1,
            )..layout();
            try {
              expect(
                paragraph.size.height,
                greaterThanOrEqualTo(natural.height - .5),
                reason:
                    'The actual emoji line must not be clamped by its circle.',
              );
              expect(
                paragraph.size.width,
                greaterThanOrEqualTo(natural.width - .5),
              );
            } finally {
              natural.dispose();
            }
            final role = compact ? 18.0 : 20.0;
            expect(
              paragraph.textScaler.scale(role),
              closeTo(scaler.scale(role), .001),
            );
            expect(
              tester.getRect(glyph).height,
              closeTo(paragraph.size.height, .01),
              reason: 'A transform must not shrink the requested glyph.',
            );
            final circle = find
                .ancestor(of: glyph, matching: find.byType(AnimatedContainer))
                .first;
            final target = find
                .ancestor(
                  of: glyph,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is GestureDetector && widget.onTap != null,
                  ),
                )
                .first;
            final circleRect = tester.getRect(circle);
            final glyphRect = tester.getRect(glyph);
            expect(glyphRect.left, greaterThanOrEqualTo(circleRect.left - .5));
            expect(glyphRect.right, lessThanOrEqualTo(circleRect.right + .5));
            expect(glyphRect.top, greaterThanOrEqualTo(circleRect.top - .5));
            expect(glyphRect.bottom, lessThanOrEqualTo(circleRect.bottom + .5));
            expect(
              tester.getSize(target).shortestSide,
              greaterThanOrEqualTo(44),
            );
            await tester.tap(glyph);
            await tester.pumpAndSettle();
            expect(quick, 1);
            expect(opened, 0);
            await tester.tap(find.text('Water'));
            expect(opened, 1);
            expect(quick, 1);
          },
        );
      }
    }
  }
}
