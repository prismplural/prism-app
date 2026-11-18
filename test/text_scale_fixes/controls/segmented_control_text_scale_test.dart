// Segmented control under text scaling.
//
// The track must hold its labels. A fixed 44dp box with single-line labels sliced
// the glyph band vertically (and ellipsised it horizontally) once the composed text
// grew. The track follows the label's real line box, keeps 44dp as its floor so
// normal-text geometry is unchanged, and lets a label take a second line before it
// ellipsises.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// Non-linear system scaler (as iOS/Android accessibility allow) composed with
/// the app's own factor; the fitting math has to follow the real line box.
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

void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _app(Widget home, {required TextScaler textScaler}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    theme: ThemeData(
      fontFamily: 'Lexend',
      fontFamilyFallback: const ['NotoColorEmoji'],
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}

/// Puts a control where it really lives: a column inside a scrolling page, i.e. under
/// a parent whose vertical axis is unbounded. A bounded parent (a Scaffold body, or a
/// sliver band) must not stretch the track - the bounded-parent cases below check
/// exactly that - so this host is used where only the control's own extent matters.
Widget _naturalHost(Widget child) {
  return Scaffold(
    body: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [child],
      ),
    ),
  );
}

Widget _control({
  required ValueChanged<String> onChanged,
  String selected = 'list',
  int? badgeCount,
}) {
  return PrismSegmentedControl<String>(
    segments: [
      const PrismSegment(value: 'list', label: 'List'),
      PrismSegment(value: 'chart', label: 'Chart', badgeCount: badgeCount),
    ],
    selected: selected,
    onChanged: onChanged,
  );
}

/// Height the paragraph would take at its own width if its box never clipped
/// it (2 lines are allowed, matching the control's own policy).
double _naturalHeight(RenderParagraph paragraph, {int maxLines = 2}) {
  final painter = TextPainter(
    text: TextSpan(
      text: paragraph.text.toPlainText(),
      style: paragraph.text.style,
    ),
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    textAlign: paragraph.textAlign,
    maxLines: maxLines,
  )..layout(maxWidth: paragraph.size.width);
  final height = painter.height;
  painter.dispose();
  return height;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPrismGoldenFonts();
  });

  for (final (label, scaler) in _scales) {
    testWidgets('track holds its label glyphs on a compact phone ($label)', (
      tester,
    ) async {
      _useViewport(tester, const Size(320, 568));
      var selected = 'list';

      await tester.pumpWidget(
        _app(
          _naturalHost(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StatefulBuilder(
                builder: (context, setState) => _control(
                  selected: selected,
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label: no layout error');

      final track = tester.getRect(find.byType(PrismSegmentedControl<String>));
      expect(track.height, greaterThanOrEqualTo(44));

      for (final text in const ['List', 'Chart']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        final needed = _naturalHeight(paragraph);
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(needed - 0.5),
          reason:
              '$label: "$text" needs ${needed.toStringAsFixed(1)}px but the '
              'track gives it ${paragraph.size.height.toStringAsFixed(1)}px',
        );
        final rect = tester.getRect(find.text(text));
        expect(
          rect.top,
          greaterThanOrEqualTo(track.top - 0.5),
          reason: '$label: "$text" painted above the track',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(track.bottom + 0.5),
          reason: '$label: "$text" painted below the track',
        );
      }

      // The control still works: tapping the second segment reports its value.
      await tester.tap(find.text('Chart'));
      await tester.pumpAndSettle();
      expect(selected, 'chart');
    });

    testWidgets('badge grows with its count instead of being sliced ($label)', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        _app(
          _naturalHost(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _control(onChanged: (_) {}, badgeCount: 9999),
            ),
          ),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label: no layout error');
      final badge = tester.renderObject<RenderParagraph>(find.text('9+'));
      final needed = _naturalHeight(badge, maxLines: 1);
      expect(
        badge.size.height,
        greaterThanOrEqualTo(needed - 0.5),
        reason:
            '$label: badge needs ${needed.toStringAsFixed(1)}px but has '
            '${badge.size.height.toStringAsFixed(1)}px',
      );
      final track = tester.getRect(find.byType(PrismSegmentedControl<String>));
      final badgeRect = tester.getRect(find.text('9+'));
      expect(badgeRect.top, greaterThanOrEqualTo(track.top - 0.5));
      expect(badgeRect.bottom, lessThanOrEqualTo(track.bottom + 0.5));
    });
  }

  // A finite parent height is what every non-scrolling page gives the track, so the
  // track must keep its own 44dp there instead of filling the parent (it once read
  // 780). The unbounded hosts used elsewhere cannot observe this.
  testWidgets('default geometry is 44dp inside a full-height bounded body', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _control(onChanged: (_) {}),
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.noScaling, 1.0),
      ),
    );
    await tester.pumpAndSettle();
    final track = tester.getRect(find.byType(PrismSegmentedControl<String>));
    expect(
      track.height,
      44,
      reason:
          'a finite parent height must not stretch the track to the parent '
          '(the regression read 780 here)',
    );
  });

  testWidgets('default geometry is 44dp inside a short bounded box', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(
        // The 300dp box is a viewport, not a constraint on the control: an Align
        // hands the track loose constraints, the way a page column does, so the
        // track keeps its own 44dp instead of being stretched (or forced) by it.
        Center(
          child: SizedBox(
            height: 300,
            width: 358,
            child: Align(
              alignment: Alignment.topCenter,
              child: _control(onChanged: (_) {}),
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.noScaling, 1.0),
      ),
    );
    await tester.pumpAndSettle();
    final track = tester.getRect(find.byType(PrismSegmentedControl<String>));
    expect(
      track.height,
      44,
      reason: 'a 300dp parent must not stretch the track',
    );
    expect(track.top, greaterThan(0));
  });

  testWidgets('four segments at 3.375x stay inside their track', (
    tester,
  ) async {
    _useViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      _app(
        _naturalHost(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PrismSegmentedControl<String>(
              segments: const [
                PrismSegment(value: 'a', label: 'Default'),
                PrismSegment(value: 'b', label: 'Pixels'),
                PrismSegment(value: 'c', label: 'Percent'),
                PrismSegment(value: 'd', label: 'Em'),
              ],
              selected: 'a',
              onChanged: (_) {},
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.linear(2.25), 1.5),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final track = tester.getRect(find.byType(PrismSegmentedControl<String>));
    for (final text in const ['Default', 'Pixels', 'Percent', 'Em']) {
      final rect = tester.getRect(find.text(text));
      expect(rect.top, greaterThanOrEqualTo(track.top - 0.5), reason: text);
      expect(rect.bottom, lessThanOrEqualTo(track.bottom + 0.5), reason: text);
    }
  });

  // The pinned-header contract: a caller that reserves space for this control
  // must get exactly the height it renders - labels' real wrapping (two lines),
  // badges and the hairline border included.
  for (final (name, segments) in <(String, List<PrismSegment<String>>)>[
    (
      'two segments',
      const [
        PrismSegment(value: 'a', label: 'List'),
        PrismSegment(value: 'b', label: 'Chart'),
      ],
    ),
    (
      'three segments with a badge',
      const [
        PrismSegment(value: 'a', label: 'Group Chats', badgeCount: 12),
        PrismSegment(value: 'b', label: 'Direct Messages'),
        PrismSegment(value: 'c', label: 'Archived'),
      ],
    ),
    (
      'four segments',
      const [
        PrismSegment(value: 'a', label: 'Default'),
        PrismSegment(value: 'b', label: 'Pixels'),
        PrismSegment(value: 'c', label: 'Percent'),
        PrismSegment(value: 'd', label: 'Em'),
      ],
    ),
  ]) {
    for (final (label, scaler) in _scales) {
      testWidgets('preferredHeightFor matches the rendering ($name, $label)', (
        tester,
      ) async {
        for (final width in const [320.0, 390.0, 800.0]) {
          _useViewport(tester, Size(width, 780));
          await tester.pumpWidget(
            _app(
              _naturalHost(
                SizedBox(
                  width: width - 32,
                  child: PrismSegmentedControl<String>(
                    segments: segments,
                    selected: 'a',
                    onChanged: (_) {},
                  ),
                ),
              ),
              textScaler: scaler,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: '$name/$label/$width: no layout error',
          );
          final finder = find.byType(PrismSegmentedControl<String>);
          final rendered = tester.getRect(finder).height;
          final control = tester.widget<PrismSegmentedControl<String>>(finder);
          final context = tester.element(finder);
          expect(
            control,
            isA<PrismScaledHeight>(),
            reason: 'the control opts into the pinned-header height contract',
          );
          expect(
            control.preferredHeightFor(context, availableWidth: width - 32),
            closeTo(rendered, 0.01),
            reason:
                '$name/$label/$width: the reported height must be the height '
                'that is really painted',
          );
          expect(
            rendered,
            greaterThanOrEqualTo(44.0 - 0.01),
            reason: '$name/$label/$width: the 44dp floor is preserved',
          );
        }
      });
    }
  }

  // A label whose line count differs between the unselected weight (w500) and the
  // selected one (w600) at this segment width. The measurement has to use the
  // weight the segment really renders, otherwise a selected label that wraps only
  // when bold is reserved one line short and the pinned band clips it.
  // A label whose line count differs between two weights at this segment width.
  // Used to prove the measurement picks the weight the segment really renders:
  // w600 for the selected segment (vs w500), and w700 for every segment once
  // MediaQuery.boldText is on (Text.build merges FontWeight.bold).
  ({String label, double segmentWidth})? wrapBoundaryLabel({
    required double controlWidth,
    required int segmentCount,
    required TextScaler scaler,
    required TextStyle base,
    required TextDirection direction,
    required FontWeight weightA,
    required FontWeight weightB,
  }) {
    final segmentWidth = (controlWidth - 1) / segmentCount;

    double heightFor(String label, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: base.copyWith(fontWeight: weight),
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: segmentWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    for (var words = 1; words <= 10; words++) {
      final label = List.filled(words, 'Word').join(' ');
      if (heightFor(label, weightA) != heightFor(label, weightB)) {
        return (label: label, segmentWidth: segmentWidth);
      }
    }
    return null;
  }

  for (final (label, scaler) in _scales) {
    testWidgets('selected weight decides the wrap it reserves ($label)', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 780));
      const controlWidth = 358.0;
      final base = ThemeData(
        fontFamily: 'Lexend',
        fontFamilyFallback: const ['NotoColorEmoji'],
      ).textTheme.labelLarge!;

      final boundary = wrapBoundaryLabel(
        controlWidth: controlWidth,
        segmentCount: 2,
        scaler: scaler,
        base: base,
        direction: TextDirection.ltr,
        weightA: FontWeight.w500,
        weightB: FontWeight.w600,
      );
      // When this face's metrics do not separate the two weights at this width,
      // every candidate label wraps the same way under both. The case then falls back
      // to a fixed label: it checks only that the reported height matches the height
      // that is painted, and says nothing about the weight difference.
      final caseLabel = boundary?.label ?? 'Word Word Word';

      for (final selectedFirst in const [true, false]) {
        await tester.pumpWidget(
          _app(
            _naturalHost(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PrismSegmentedControl<String>(
                  segments: [
                    PrismSegment(
                      value: 'a',
                      label: selectedFirst ? caseLabel : 'Ab',
                    ),
                    PrismSegment(
                      value: 'b',
                      label: selectedFirst ? 'Ab' : caseLabel,
                    ),
                  ],
                  selected: selectedFirst ? 'a' : 'b',
                  onChanged: (_) {},
                ),
              ),
            ),
            textScaler: scaler,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '$label: no layout error',
        );
        final finder = find.byType(PrismSegmentedControl<String>);
        final control = tester.widget<PrismSegmentedControl<String>>(finder);
        final context = tester.element(finder);
        final rendered = tester.getRect(finder).height;
        expect(
          control.preferredHeightFor(context, availableWidth: controlWidth),
          closeTo(rendered, 0.01),
          reason:
              '$label: selected=${selectedFirst ? 'first' : 'second'}; the '
              'reserved height must match the track that really renders the '
              'label at its own weight',
        );
        final boundaryFinder = find.text(caseLabel);
        final trackRect = tester.getRect(finder);
        final labelRect = tester.getRect(boundaryFinder);
        expect(
          labelRect.bottom,
          lessThanOrEqualTo(trackRect.bottom + 0.5),
          reason: '$label: the boundary label must not be clipped',
        );
      }
    });

    testWidgets('the segment target itself is >= 44dp and takes edge taps', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 780));
      final calls = <String>[];

      await tester.pumpWidget(
        _app(
          _naturalHost(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PrismSegmentedControl<String>(
                segments: const [
                  PrismSegment(value: 'a', label: 'Alpha'),
                  PrismSegment(value: 'b', label: 'Beta'),
                ],
                selected: 'a',
                onChanged: calls.add,
              ),
            ),
          ),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();

      // The real hit area, not the track: the hairline border insets the segments
      // by 0.5dp on each side, so this rect - not `track.height` - is what the
      // 44dp target rule applies to.
      final beta = find.ancestor(
        of: find.text('Beta'),
        matching: find.byType(GestureDetector),
      );
      expect(beta, findsWidgets, reason: '$label: the segment is tappable');
      final target = tester.getRect(beta.first);
      expect(
        target.height,
        greaterThanOrEqualTo(44.0 - 0.01),
        reason:
            '$label: the segment gesture target is '
            '${target.height.toStringAsFixed(2)}dp tall; the contract needs '
            '44dp, and the 0.5dp border inset plus the 43dp inner floor can '
            'leave it short',
      );
      expect(target.width, greaterThanOrEqualTo(44.0 - 0.01));

      await tester.tapAt(Offset(target.center.dx, target.top + 0.25));
      await tester.pumpAndSettle();
      expect(calls, [
        'b',
      ], reason: '$label: a tap on the target top edge selects');

      final alpha = tester.getRect(
        find
            .ancestor(
              of: find.text('Alpha'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.tapAt(Offset(alpha.center.dx, alpha.bottom - 0.25));
      await tester.pumpAndSettle();
      expect(calls, [
        'b',
      ], reason: '$label: tapping the already-selected segment does nothing');
    });
  }

  testWidgets('bold text: the reserved height still matches the rendering', (
    tester,
  ) async {
    // Text merges `FontWeight.bold` (w700) when MediaQuery.boldText is true, so the
    // painted label is w700 while the control measures w500/w600; the measurement has
    // to apply that same merge to predict the same height.
    _useViewport(tester, const Size(390, 780));
    const controlWidth = 358.0;
    const scaler = PrismTextScaler(TextScaler.linear(2.25), 1.5);
    final base = ThemeData(
      fontFamily: 'Lexend',
      fontFamilyFallback: const ['NotoColorEmoji'],
    ).textTheme.labelLarge!;

    final boundary = wrapBoundaryLabel(
      controlWidth: controlWidth,
      segmentCount: 2,
      scaler: scaler,
      base: base,
      direction: TextDirection.ltr,
      weightA: FontWeight.w600,
      weightB: FontWeight.w700,
    );
    // As above: if this face's metrics do not separate w600 from w700 at this width,
    // the case falls back to a fixed label and checks only that the reported height
    // matches the painted one.
    final caseLabel = boundary?.label ?? 'Word Word Word Word';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        theme: ThemeData(
          fontFamily: 'Lexend',
          fontFamilyFallback: const ['NotoColorEmoji'],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: scaler, boldText: true),
          child: child ?? const SizedBox.shrink(),
        ),
        home: _naturalHost(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PrismSegmentedControl<String>(
              segments: [
                PrismSegment(value: 'a', label: caseLabel),
                const PrismSegment(value: 'b', label: 'Ab'),
              ],
              selected: 'a',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no layout error');
    final finder = find.byType(PrismSegmentedControl<String>);
    final control = tester.widget<PrismSegmentedControl<String>>(finder);
    final context = tester.element(finder);
    expect(
      control.preferredHeightFor(context, availableWidth: controlWidth),
      closeTo(tester.getRect(finder).height, 0.01),
      reason:
          'with bold text the painted label is w700, so the measurement has to '
          'be bold too',
    );
  });

  // The badge is painted at w600 (`_SegmentBadge` merges fontWeight w600) but the
  // height prediction measures it from the bare labelSmall style. Its width feeds
  // the label's available width ("slot - badge - 6"), so a badge measured at the
  // wrong weight can move a label across the wrap boundary and reserve one line
  // less than the label renders. `9999` gives the two-character "9+" badge, where
  // the weight difference is largest.
  for (final (label, scaler) in _scales) {
    testWidgets('a w600 badge keeps the label wrap it reserves ($label)', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 780));
      const controlHeightFloor = 44.0;
      final theme = ThemeData(
        fontFamily: 'Lexend',
        fontFamilyFallback: const ['NotoColorEmoji'],
      );
      final labelStyle = theme.textTheme.labelLarge!;
      final badgeBase = theme.textTheme.labelSmall!.copyWith(height: 1.0);

      double lineHeight(String text, TextStyle style, double maxWidth) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 2,
        )..layout(maxWidth: maxWidth);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      double badgeWidth(FontWeight weight) {
        final painter = TextPainter(
          text: TextSpan(
            text: '9+',
            style: badgeBase.copyWith(fontWeight: weight),
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = math.max(18.0, painter.width + 12);
        painter.dispose();
        return width;
      }

      final realBadge = badgeWidth(FontWeight.w600);
      final measuredBadge = badgeWidth(FontWeight.w400);

      // Prefer a (width, label) pair whose wrap differs between the badge width as
      // painted (w600) and a narrower one (w400): only such a pair can show the
      // difference. Where the badge metrics do not move the wrap at any tried width,
      // the case falls back to a fixed label and checks only that the reported height
      // matches the painted one.
      ({double width, String label})? boundary;
      for (final width in const [200.0, 240.0, 280.0, 320.0, 358.0]) {
        final slot = (width - 1) / 2;
        final realLabelWidth = math.max(1.0, slot - realBadge - 6);
        final measuredLabelWidth = math.max(1.0, slot - measuredBadge - 6);
        for (var n = 1; n <= 12 && boundary == null; n++) {
          for (final candidate in [
            List.filled(n, 'Word').join(' '),
            List.filled(n + 1, 'W').join(),
          ]) {
            if (lineHeight(candidate, labelStyle, realLabelWidth) !=
                lineHeight(candidate, labelStyle, measuredLabelWidth)) {
              boundary = (width: width, label: candidate);
              break;
            }
          }
        }
        if (boundary != null) break;
      }
      final badgeCase = boundary ?? (width: 358.0, label: 'Word Word Word');

      await tester.pumpWidget(
        _app(
          _naturalHost(
            SizedBox(
              width: badgeCase.width,
              child: PrismSegmentedControl<String>(
                segments: [
                  PrismSegment(
                    value: 'a',
                    label: badgeCase.label,
                    badgeCount: 9999,
                    badgeSemanticLabel: '9999 unread',
                  ),
                  const PrismSegment(value: 'b', label: 'Ab'),
                ],
                selected: 'a',
                onChanged: (_) {},
              ),
            ),
          ),
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label: no layout error');
      final finder = find.byType(PrismSegmentedControl<String>);
      final control = tester.widget<PrismSegmentedControl<String>>(finder);
      final context = tester.element(finder);
      final trackRect = tester.getRect(finder);
      expect(trackRect.height, greaterThanOrEqualTo(controlHeightFloor - 0.01));
      expect(
        control.preferredHeightFor(context, availableWidth: badgeCase.width),
        closeTo(trackRect.height, 0.01),
        reason:
            '$label: the badge is painted at w600, so its width - and therefore '
            'the label width it leaves - must be measured at w600 too',
      );

      final badgeParagraph = tester.renderObject<RenderParagraph>(
        find.text('9+'),
      );
      final badgeNatural = _naturalHeight(badgeParagraph, maxLines: 1);
      expect(
        badgeParagraph.size.height,
        greaterThanOrEqualTo(badgeNatural - 0.5),
        reason: '$label: the badge glyphs must not be clipped',
      );
    });
  }

  // A 44dp viewport pins the geometry exactly, so the segment target can be measured
  // without depending on the face's line height. The track paints 44dp tall and its
  // segments are the tap targets, so each one has to be 44dp too; the assertion
  // reports the value it measured, so the failure text is the measurement itself.
  testWidgets('forced 44dp track: the real segment target is at least 44dp', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 780));
    final calls = <String>[];
    var selected = 'a';

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            height: 44,
            width: 358,
            child: Align(
              alignment: Alignment.topCenter,
              child: StatefulBuilder(
                builder: (context, setSelected) =>
                    PrismSegmentedControl<String>(
                      segments: const [
                        PrismSegment(value: 'a', label: 'Alpha'),
                        PrismSegment(value: 'b', label: 'Beta'),
                      ],
                      selected: selected,
                      onChanged: (value) {
                        calls.add(value);
                        setSelected(() => selected = value);
                      },
                    ),
              ),
            ),
          ),
        ),
        textScaler: const PrismTextScaler(TextScaler.noScaling, 1.0),
      ),
    );
    await tester.pumpAndSettle();

    final track = tester.getRect(find.byType(PrismSegmentedControl<String>));
    expect(
      track.height,
      44,
      reason: 'the track keeps its own 44dp height inside the 44dp viewport',
    );

    final target = tester.getRect(
      find
          .ancestor(
            of: find.text('Beta'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(
      target.height,
      greaterThanOrEqualTo(44.0 - 0.01),
      reason:
          'the segment gesture target measures '
          '${target.height.toStringAsFixed(2)}dp inside the 44dp track: the 0.5dp '
          'hairline is an inset in decoration:, so the tappable content is 43dp',
    );

    // The target still behaves across its real extent: the top edge of the second
    // segment selects it, and the bottom edge of the first selects that one.
    await tester.tapAt(Offset(target.center.dx, target.top + 0.25));
    await tester.pumpAndSettle();
    expect(calls, ['b']);
    expect(selected, 'b', reason: 'the controlled host must accept the change');

    final firstTarget = tester.getRect(
      find
          .ancestor(
            of: find.text('Alpha'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.tapAt(
      Offset(firstTarget.center.dx, firstTarget.bottom - 0.25),
    );
    await tester.pumpAndSettle();
    expect(calls, ['b', 'a']);
    expect(selected, 'a');
  });
}
