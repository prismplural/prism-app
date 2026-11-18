// Compact HabitChip at a 320px window with a weekly-progress pill, a positive
// multi-digit streak pill and a ZWJ family icon, at the maximum and a nonlinear text
// scale, in both bundled faces.
//
// Desired behaviour (nothing here assumes the icon is several ems wide - the font
// decides that):
//   * no layout error, i.e. the chip row does not overflow;
//   * the glyph is painted at the requested size (no clamp, no ancestor shrink) and
//     inside its completion target;
//   * the completion target stays >= 44dp;
//   * both pills are still painted, un-ellipsised, inside the chip;
//   * the completion tap still fires onQuickComplete and the body tap onTap.
//
// Geometry note: the chip is pumped inside the padding chain it really lives in -
// the due container's 16dp horizontal padding and `_FullDueContent`'s 12dp
// (`today_habits_container.dart:238-239`, `:333-334`) - so at a 320dp window the chip
// has 264dp, not 320dp.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/features/habits/widgets/habit_chip.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';

import '../../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// A ZWJ family sequence; how wide it renders is the font's decision.
const String _familyIcon =
    '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

final DateTime _baseDate = DateTime(2026, 4, 11);

/// Monday 2026-04-06 and Wednesday 2026-04-08 fall inside `weeklyDays` below, so the
/// progress pill reads 2/3.
Habit _habit() => Habit(
  id: 'h1',
  name: 'Walk together',
  icon: _familyIcon,
  createdAt: _baseDate,
  modifiedAt: _baseDate,
  frequency: HabitFrequency.weekly,
  weeklyDays: const [1, 3, 5],
  currentStreak: 12,
);

HabitCompletion _completion(DateTime at) => HabitCompletion(
  id: 'c-${at.millisecondsSinceEpoch}',
  habitId: 'h1',
  completedAt: at,
  createdAt: at,
  modifiedAt: at,
);

List<HabitCompletion> _weeklyCompletions() => [
  _completion(DateTime(2026, 4, 6, 9)),
  _completion(DateTime(2026, 4, 8, 9)),
];

/// A scaler that does not scale every size by one ratio.
class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 3.0 : fontSize * 1.6;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.0;

  @override
  bool operator ==(Object other) => other is _NonlinearTextScaler;

  @override
  int get hashCode => 0x68616231; // 'hab1'
}

Widget _scope({
  required double system,
  required double app,
  required String fontFamily,
  TextScaler? scalerOverride,
  VoidCallback? onTap,
  VoidCallback? onComplete,
}) {
  final scaler =
      scalerOverride ?? PrismTextScaler(TextScaler.linear(system), app);
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        fontFamily: fontFamily,
        fontFamilyFallback: const ['NotoColorEmoji'],
        extensions: const [PrismShapes.rounded],
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Padding(
          // Production nesting: the due container's padding, then the full-due
          // content's padding, so the chip has the width it really gets.
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: HabitChip(
              habit: _habit(),
              todayCompletions: const [],
              weeklyCompletions: _weeklyCompletions(),
              completed: false,
              onTap: onTap,
              onQuickComplete: onComplete == null
                  ? null
                  : () async => onComplete(),
            ),
          ),
        ),
      ),
    ),
  );
}

void useWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Asserts [inner] paints inside [outer].
void expectPaintedInside(
  WidgetTester tester,
  Finder inner,
  Finder outer, {
  required String label,
}) {
  final outerRect = tester.getRect(outer);
  final innerRect = tester.getRect(inner);
  expect(
    innerRect.left,
    greaterThanOrEqualTo(outerRect.left - 0.5),
    reason: '$label: left edge ${innerRect.left} < ${outerRect.left}',
  );
  expect(
    innerRect.right,
    lessThanOrEqualTo(outerRect.right + 0.5),
    reason: '$label: right edge ${innerRect.right} > ${outerRect.right}',
  );
  expect(
    innerRect.top,
    greaterThanOrEqualTo(outerRect.top - 0.5),
    reason: '$label: top edge ${innerRect.top} < ${outerRect.top}',
  );
  expect(
    innerRect.bottom,
    lessThanOrEqualTo(outerRect.bottom + 0.5),
    reason: '$label: bottom edge ${innerRect.bottom} > ${outerRect.bottom}',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  for (final (label, system, app, scalerOverride)
      in <(String, double, double, TextScaler?)>[
        ('system 225% x Prism 150% = 3.375x', 2.25, 1.5, null),
        ('nonlinear scaler', 1, 1, const _NonlinearTextScaler()),
      ]) {
    for (final fontFamily in ['Lexend', 'OpenDyslexic']) {
      testWidgets(
        'compact chip keeps glyph, target and pills intact - $label / $fontFamily',
        (tester) async {
          useWindow(tester, const Size(320, 800));
          await tester.pumpWidget(
            _scope(
              system: system,
              app: app,
              fontFamily: fontFamily,
              scalerOverride: scalerOverride,
            ),
          );
          await tester.pumpAndSettle();

          // No RenderFlex overflow anywhere in the chip.
          final error = tester.takeException();
          expect(
            error,
            isNull,
            reason: '$label / $fontFamily: layout reported "$error"',
          );

          final chip = find.byType(HabitChip);
          final circle = find.byType(HabitLeadingCircle);
          expect(chip, findsOneWidget);
          expect(circle, findsOneWidget);
          final target = tester.getSize(circle);

          // An accessible completion target, independent of the font's glyph width.
          expect(
            target.width,
            greaterThanOrEqualTo(44),
            reason: '$label / $fontFamily: completion target too narrow',
          );
          expect(
            target.height,
            greaterThanOrEqualTo(44),
            reason: '$label / $fontFamily: completion target too short',
          );

          // The glyph is the icon subtree's paragraph.
          final icon = find.byKey(
            const ValueKey('habit-chip-icon-$_familyIcon'),
          );
          expect(icon, findsOneWidget);
          final glyphFinder = find.descendant(
            of: icon,
            matching: find.byType(RichText),
          );
          expect(glyphFinder, findsOneWidget);
          final glyph = tester.renderObject<RenderParagraph>(glyphFinder);

          // Painted at the requested size: not clamped, not ellipsised, and no
          // ancestor (FittedBox and friends) shrinking the paint.
          expect(
            glyph.didExceedMaxLines,
            isFalse,
            reason: '$label / $fontFamily: the glyph was ellipsised',
          );
          expect(
            glyph.size.height,
            greaterThanOrEqualTo(
              glyph.getMaxIntrinsicHeight(glyph.size.width) - 0.5,
            ),
            reason: '$label / $fontFamily: the glyph was vertically clamped',
          );
          expect(
            glyph.getTransformTo(null).getMaxScaleOnAxis(),
            closeTo(1.0, 0.02),
            reason: '$label / $fontFamily: an ancestor scaled the glyph',
          );
          // ...and it sits inside the completion target it belongs to.
          expectPaintedInside(
            tester,
            glyphFinder,
            circle,
            label: 'glyph ($label / $fontFamily)',
          );

          // The metadata pills are still painted in full, inside the chip.
          for (final text in ['2/3', '12']) {
            final finder = find.text(text);
            expect(
              finder,
              findsWidgets,
              reason: '$text ($label / $fontFamily)',
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find
                  .descendant(
                    of: find
                        .ancestor(of: finder, matching: find.byType(PrismPill))
                        .first,
                    matching: find.byType(RichText),
                  )
                  .first,
            );
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '$label / $fontFamily: "$text" was ellipsised',
            );
            expectPaintedInside(
              tester,
              finder,
              chip,
              label: '$text ($label / $fontFamily)',
            );
          }
        },
      );
    }
  }

  testWidgets('the metadata gap is the same inline and stacked (6dp)', (
    tester,
  ) async {
    // Inline at the default size: the two pills sit on the title's line.
    useWindow(tester, const Size(320, 800));
    await tester.pumpWidget(_scope(system: 1, app: 1, fontFamily: 'Lexend'));
    await tester.pumpAndSettle();

    final pills = find.byType(PrismPill);
    expect(pills, findsNWidgets(2));
    var gap =
        tester.getRect(pills.at(1)).left - tester.getRect(pills.at(0)).right;
    expect(gap, closeTo(6, 0.6), reason: 'inline gap between the two pills');
    expect(
      tester.getCenter(pills.at(0)).dy,
      closeTo(tester.getCenter(pills.at(1)).dy, 0.6),
      reason: 'inline: both pills share one line',
    );

    // Stacked at the maximum scale: the wrap owns the gap, and it must be the same 6dp
    // (the old build interleaved a 6dp spacer *and* asked the wrap for 6dp, so this read
    // 18dp).
    await tester.pumpWidget(
      _scope(system: 2.25, app: 1.5, fontFamily: 'Lexend'),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'stacked layout must not overflow',
    );
    final stacked = find.byType(PrismPill);
    expect(stacked, findsNWidgets(2));
    final stacked0 = tester.getRect(stacked.at(0));
    final stacked1 = tester.getRect(stacked.at(1));
    if ((stacked1.left - stacked0.right).abs() < 100 &&
        (stacked1.top - stacked0.top).abs() < 0.6) {
      gap = stacked1.left - stacked0.right;
      expect(gap, closeTo(6, 0.6), reason: 'stacked gap between the two pills');
    } else {
      // A very narrow wrap may put the second pill on its own run; the vertical gap is
      // then the run spacing (2dp) and the horizontal gap is the same 6dp constant.
      expect(stacked1.left, closeTo(stacked0.left, 0.6));
    }
  });

  testWidgets(
    'the pills are never shrunk to make them fit at the inline boundary',
    (tester) async {
      // Widths at and just under the point where the pills stop fitting beside the title at
      // 1.5x: the layout may switch from inline to stacked between them, but the pill labels
      // must never be shrunk, ellipsised or clipped to buy the fit.
      for (final width in [320.0, 300.0, 280.0]) {
        useWindow(tester, Size(width, 800));
        await tester.pumpWidget(
          _scope(system: 1.5, app: 1, fontFamily: 'Lexend'),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '$width: the chip must not overflow at the boundary',
        );

        final chipRect = tester.getRect(find.byType(HabitChip));
        for (final label in ['2/3', '12']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find
                      .ancestor(
                        of: find.text(label),
                        matching: find.byType(PrismPill),
                      )
                      .first,
                  matching: find.byType(RichText),
                )
                .first,
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$width: "$label" was ellipsised to fit',
          );
          expect(
            paragraph.getTransformTo(null).getMaxScaleOnAxis(),
            closeTo(1.0, 0.02),
            reason: '$width: "$label" was scaled down to fit',
          );
          final rect = tester.getRect(find.text(label));
          expect(
            rect.right,
            lessThanOrEqualTo(chipRect.right + 0.5),
            reason: '$width: "$label" paints past the chip',
          );
        }
      }
    },
  );

  testWidgets('completion and detail taps still reach their own callbacks', (
    tester,
  ) async {
    useWindow(tester, const Size(320, 800));
    var completions = 0;
    var details = 0;
    await tester.pumpWidget(
      _scope(
        system: 2.25,
        app: 1.5,
        fontFamily: 'Lexend',
        onTap: () => details++,
        onComplete: () => completions++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(HabitLeadingCircle));
    await tester.pumpAndSettle();
    expect(
      completions,
      1,
      reason: 'the completion tap must fire onQuickComplete',
    );
    expect(
      details,
      0,
      reason: 'the completion tap must not open the detail view',
    );

    await tester.tap(find.text('Walk together'));
    await tester.pumpAndSettle();
    expect(details, 1, reason: 'the body tap must still open the detail view');
    expect(completions, 1, reason: 'the body tap must not toggle completion');
  });
}
