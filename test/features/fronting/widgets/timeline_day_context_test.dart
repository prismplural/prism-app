import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_date_overlay.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_geometry.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_painter.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_time_label_formatter.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';

Widget _buildOverlay({
  required DateTime viewStart,
  required DateTime viewEnd,
  required double pixelsPerHour,
  required double viewportHeight,
  required double contentHeight,
  required ValueNotifier<double> scrollOffset,
  required DateTime now,
  double width = 240,
  double contentTopInViewport = 0,
  TextScaler textScaler = TextScaler.noScaling,
  ValueNotifier<DateTime>? nowListenable,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SizedBox(
            width: width,
            height: viewportHeight,
            child: TimelineDateOverlay(
              viewStart: viewStart,
              viewEnd: viewEnd,
              pixelsPerHour: pixelsPerHour,
              viewportHeight: viewportHeight,
              contentHeight: contentHeight,
              scrollOffsetListenable: scrollOffset,
              contentTopInViewport: contentTopInViewport,
              nowListenable: nowListenable,
              now: now,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('TimelineGeometry', () {
    test('maps later times to larger content y values', () {
      final start = DateTime(2026, 7, 1, 8);
      final geometry = TimelineGeometry(
        viewStart: start,
        viewEnd: start.add(const Duration(hours: 8)),
        pixelsPerHour: 24,
        viewportHeight: 120,
        contentHeight: 192,
        scrollOffset: 0,
      );

      expect(
        geometry.timeToContentY(start.add(const Duration(hours: 2))),
        greaterThan(geometry.timeToContentY(start)),
      );
      expect(geometry.timeToContentY(start.add(const Duration(hours: 2))), 48);
    });

    test('clamps active day probes that land in top padding', () {
      final start = DateTime(2026, 7, 2, 9);
      final geometry = TimelineGeometry(
        viewStart: start,
        viewEnd: start.add(const Duration(hours: 2)),
        pixelsPerHour: 50,
        viewportHeight: 400,
        contentHeight: 100,
        scrollOffset: 0,
        contentTopInViewport: 120,
      );

      expect(geometry.viewportYToContentY(12), 0);
      expect(geometry.activeDayAtProbe(12), DateTime(2026, 7, 2));
    });

    test('clamps active day probes that land below short content', () {
      final start = DateTime(2026, 7, 2, 9);
      final geometry = TimelineGeometry(
        viewStart: start,
        viewEnd: start.add(const Duration(hours: 2)),
        pixelsPerHour: 50,
        viewportHeight: 400,
        contentHeight: 100,
        scrollOffset: 0,
      );

      expect(geometry.viewportYToContentY(380), 100);
      expect(geometry.activeDayAtProbe(380), DateTime(2026, 7, 2));
    });

    test('uses full scrollable height for viewport positioning', () {
      final start = DateTime(2026, 7, 2);
      final geometry = TimelineGeometry(
        viewStart: start,
        viewEnd: start.add(const Duration(hours: 10)),
        pixelsPerHour: 100,
        viewportHeight: 400,
        contentHeight: 1000,
        scrollableHeight: 1080,
        scrollOffset: 680,
      );

      expect(geometry.boundedScrollOffset(), 600);
      expect(geometry.visualScrollOffset(), 680);
      expect(geometry.contentYToViewportY(1000), 320);
      expect(geometry.viewportYToContentY(400), 1000);
    });

    test('calendar day offsets use local calendar dates', () {
      final geometry = TimelineGeometry(
        viewStart: DateTime(2026, 3, 8),
        viewEnd: DateTime(2026, 3, 10),
        pixelsPerHour: 10,
        viewportHeight: 100,
        contentHeight: 480,
        scrollOffset: 0,
      );

      expect(
        geometry.calendarDayOffset(DateTime(2026, 3, 8), 1),
        DateTime(2026, 3, 9),
      );
    });

    test('day boundaries stay aligned across variable-length days', () {
      tzdata.initializeTimeZones();
      final location = tz.getLocation('America/New_York');
      final viewStart = tz.TZDateTime(location, 2026, 3, 8);
      final viewEnd = tz.TZDateTime(location, 2026, 3, 10);
      const pixelsPerHour = 10.0;
      final contentHeight =
          viewEnd.difference(viewStart).inMilliseconds /
          Duration.millisecondsPerHour *
          pixelsPerHour;
      final geometry = TimelineGeometry(
        viewStart: viewStart,
        viewEnd: viewEnd,
        pixelsPerHour: pixelsPerHour,
        viewportHeight: contentHeight,
        contentHeight: contentHeight,
        scrollOffset: 0,
      );

      final boundary = geometry
          .dayBoundariesNearViewport(bleed: 0)
          .singleWhere((day) => day.month == 3 && day.day == 9);

      expect(boundary.difference(viewStart).inHours, 23);
      expect(geometry.timeToContentY(boundary), 23 * pixelsPerHour);
    });

    test('finds visible midnight boundaries', () {
      final geometry = TimelineGeometry(
        viewStart: DateTime(2026, 7, 1, 12),
        viewEnd: DateTime(2026, 7, 4),
        pixelsPerHour: 10,
        viewportHeight: 260,
        contentHeight: 600,
        scrollOffset: 0,
      );

      expect(geometry.dayBoundariesNearViewport(bleed: 0).toList(), [
        DateTime(2026, 7, 2),
      ]);
    });

    test('painter hit zones use the shared time-to-y mapping', () {
      final viewStart = DateTime(2026, 7, 1, 8);
      final session = FrontingSession(
        id: 'alice-session',
        memberId: 'alice',
        startTime: viewStart.add(const Duration(minutes: 90)),
        endTime: viewStart.add(const Duration(minutes: 150)),
      );
      final member = Member(
        id: 'alice',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
      );
      const canvasSize = Size(44, 240);
      final painter = TimelinePainter(
        rows: [
          TimelineMemberRow(member: member, sessions: [session]),
        ],
        sleepSessions: const [],
        columnWidth: 40,
        columnPadding: 4,
        pixelsPerHour: 60,
        viewStart: viewStart,
        viewEnd: viewStart.add(const Duration(hours: 4)),
        primaryColor: Colors.purple,
        surfaceColor: Colors.white,
        onSurfaceColor: Colors.black,
        surfaceContainerColor: Colors.white,
        brightness: Brightness.light,
        viewportHeight: 200,
        shapes: PrismShapes.rounded,
      );
      final geometry = TimelineGeometry(
        viewStart: viewStart,
        viewEnd: viewStart.add(const Duration(hours: 4)),
        pixelsPerHour: 60,
        viewportHeight: 200,
        contentHeight: canvasSize.height,
        scrollOffset: 0,
      );

      final zone = painter.computeHitZones(canvasSize).single;

      expect(zone.rect.top, geometry.timeToContentY(session.startTime));
      expect(zone.rect.bottom, geometry.timeToContentY(session.endTime!));
    });
  });

  group('TimelineTimeLabelFormatter', () {
    test('formats normal English 12-hour labels', () {
      final formatter = TimelineTimeLabelFormatter(
        locale: 'en_US',
        alwaysUse24HourFormat: false,
      );

      expect(formatter.normalLabel(DateTime(2026, 7, 1, 20)), '8 PM');
      expect(formatter.normalLabel(DateTime(2026, 7, 1)), '12 AM');
    });

    test('formats normal and compact 24-hour labels', () {
      final formatter = TimelineTimeLabelFormatter(
        locale: 'en_US',
        alwaysUse24HourFormat: true,
      );

      expect(formatter.normalLabel(DateTime(2026, 7, 1, 20)), '20:00');
      expect(formatter.compactLabel(DateTime(2026, 7, 1)), '00');
      expect(formatter.compactLabel(DateTime(2026, 7, 1, 20)), '20');
    });

    test(
      'forces 12-hour output when the device 24-hour setting is off',
      () async {
        await initializeDateFormatting('en_GB');
        final formatter = TimelineTimeLabelFormatter(
          locale: 'en_GB',
          alwaysUse24HourFormat: false,
        );

        final label = formatter.normalLabel(DateTime(2026, 7, 1, 20));

        expect(label, contains('8'));
        expect(label, isNot(contains('20')));
        expect(label.toUpperCase(), contains('PM'));
      },
    );

    test(
      'uses marker compact labels for English and numeric fallback otherwise',
      () {
        final english = TimelineTimeLabelFormatter(
          locale: 'en_US',
          alwaysUse24HourFormat: false,
        );
        final spanish = TimelineTimeLabelFormatter(
          locale: 'es',
          alwaysUse24HourFormat: false,
        );

        expect(english.compactLabel(DateTime(2026, 7, 1, 20)), '8P');
        expect(spanish.compactLabel(DateTime(2026, 7, 1, 20)), '8');
      },
    );

    testWidgets('keeps non-English 12-hour gutter labels visible when tight', (
      tester,
    ) async {
      await initializeDateFormatting('es');
      final formatter = TimelineTimeLabelFormatter(
        locale: 'es',
        alwaysUse24HourFormat: false,
      );
      const style = TextStyle(fontSize: 16);

      expect(
        formatter.bestLabel(
          time: DateTime(2026, 7, 1, 20),
          style: style,
          textScaler: TextScaler.noScaling,
          maxWidth: _labelWidth('8', style) + 0.1,
          textDirection: TextDirection.ltr,
        ),
        '8',
      );
    });

    testWidgets('chooses compact labels when normal labels do not fit', (
      tester,
    ) async {
      final formatter = TimelineTimeLabelFormatter(
        locale: 'en_US',
        alwaysUse24HourFormat: false,
      );
      const style = TextStyle(fontSize: 16);
      final normalWidth = _labelWidth(
        formatter.normalLabel(DateTime(2026, 7, 1, 20)),
        style,
      );
      final compactWidth = _labelWidth('8P', style);

      expect(
        formatter.bestLabel(
          time: DateTime(2026, 7, 1, 20),
          style: style,
          textScaler: TextScaler.noScaling,
          maxWidth: (normalWidth + compactWidth) / 2,
          textDirection: TextDirection.ltr,
        ),
        '8P',
      );
    });

    testWidgets('keeps compact labels when all candidates overflow', (
      tester,
    ) async {
      final formatter = TimelineTimeLabelFormatter(
        locale: 'en_US',
        alwaysUse24HourFormat: false,
      );

      expect(
        formatter.bestLabel(
          time: DateTime(2026, 7, 1, 20),
          style: const TextStyle(fontSize: 16),
          textScaler: const TextScaler.linear(3),
          maxWidth: 0,
          textDirection: TextDirection.ltr,
        ),
        '8P',
      );
    });
  });

  group('TimelineDateOverlay', () {
    testWidgets(
      'hides floating chip when a today-only probe lands in padding',
      (tester) async {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day, 9);
        final scrollOffset = ValueNotifier<double>(0);
        addTearDown(scrollOffset.dispose);

        await tester.pumpWidget(
          _buildOverlay(
            viewStart: todayStart,
            viewEnd: todayStart.add(const Duration(hours: 2)),
            pixelsPerHour: 50,
            viewportHeight: 400,
            contentHeight: 100,
            scrollOffset: scrollOffset,
            contentTopInViewport: 120,
            now: now,
          ),
        );

        expect(find.byType(DateChip), findsNothing);
      },
    );

    testWidgets('shows non-today context without taking pointer events', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 3, 12);
      final viewStart = DateTime(2026, 7, 1);
      final scrollOffset = ValueNotifier<double>(0);
      addTearDown(scrollOffset.dispose);

      await tester.pumpWidget(
        _buildOverlay(
          viewStart: viewStart,
          viewEnd: DateTime(2026, 7, 2, 12),
          pixelsPerHour: 20,
          viewportHeight: 240,
          contentHeight: 720,
          scrollOffset: scrollOffset,
          now: now,
        ),
      );

      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(TimelineDateOverlay),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);
      expect(find.byType(DateChip), findsWidgets);

      final floatingChip = tester
          .widgetList<DateChip>(find.byType(DateChip))
          .first;
      expect(floatingChip.includeSemantics, isTrue);
      expect(floatingChip.semanticHeader, isFalse);
      expect(floatingChip.semanticLabel, startsWith('Timeline position,'));
    });

    testWidgets('refreshes floating chip state when today changes', (
      tester,
    ) async {
      final now = ValueNotifier<DateTime>(DateTime(2026, 7, 3, 12));
      final scrollOffset = ValueNotifier<double>(0);
      addTearDown(now.dispose);
      addTearDown(scrollOffset.dispose);

      await tester.pumpWidget(
        _buildOverlay(
          viewStart: DateTime(2026, 7, 1),
          viewEnd: DateTime(2026, 7, 2, 12),
          pixelsPerHour: 20,
          viewportHeight: 240,
          contentHeight: 720,
          scrollOffset: scrollOffset,
          now: now.value,
          nowListenable: now,
        ),
      );

      Iterable<DateChip> chips() =>
          tester.widgetList<DateChip>(find.byType(DateChip));
      expect(chips().where((chip) => !chip.semanticHeader), isNotEmpty);

      now.value = DateTime(2026, 7, 1, 12);
      await tester.pump();

      expect(chips().where((chip) => !chip.semanticHeader), isEmpty);
    });

    testWidgets('does not build geometry with non-positive pixels per hour', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 3, 12);
      final scrollOffset = ValueNotifier<double>(0);
      addTearDown(scrollOffset.dispose);

      await tester.pumpWidget(
        _buildOverlay(
          viewStart: DateTime(2026, 7, 1),
          viewEnd: DateTime(2026, 7, 2, 12),
          pixelsPerHour: 0,
          viewportHeight: 240,
          contentHeight: 720,
          scrollOffset: scrollOffset,
          now: now,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(DateChip), findsNothing);
    });

    testWidgets('constrains date chips at large text sizes', (tester) async {
      final now = DateTime(2026, 7, 3, 12);
      final scrollOffset = ValueNotifier<double>(0);
      addTearDown(scrollOffset.dispose);

      await tester.pumpWidget(
        _buildOverlay(
          viewStart: DateTime(2026, 7, 1),
          viewEnd: DateTime(2026, 7, 2, 12),
          pixelsPerHour: 20,
          viewportHeight: 240,
          contentHeight: 720,
          scrollOffset: scrollOffset,
          now: now,
          width: 96,
          textScaler: const TextScaler.linear(1.5),
        ),
      );

      for (final element in tester.elementList(find.byType(DateChip))) {
        final box = element.renderObject! as RenderBox;
        expect(box.size.width, lessThanOrEqualTo(80));
      }
    });
  });
}

double _labelWidth(String label, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: TextScaler.noScaling,
  )..layout();
  return painter.width;
}
