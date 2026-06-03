import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_painter.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

Finder _timelineCanvasFinder() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is TimelinePainter,
);

TimelinePainter _timelinePainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(_timelineCanvasFinder());
  return paint.painter! as TimelinePainter;
}

double _timelineCanvasHeight(WidgetTester tester) {
  final renderObject = tester.renderObject<RenderCustomPaint>(
    _timelineCanvasFinder(),
  );
  return renderObject.size.height;
}

Rect _timelineCanvasRect(WidgetTester tester) =>
    tester.getRect(_timelineCanvasFinder());

Widget _buildSubject(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: TimelineView()),
    ),
  );
}

void main() {
  testWidgets('short timelines center their chart instead of stretching it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repo = FakeFrontingSessionRepository();
    final now = DateTime.now();
    final members = [
      Member(id: 'alice', name: 'Alice', createdAt: DateTime(2026, 1, 1)),
      Member(id: 'bob', name: 'Bob', createdAt: DateTime(2026, 1, 1)),
    ];
    repo.sessions.addAll([
      FrontingSession(
        id: 'alice-session',
        memberId: 'alice',
        startTime: now.subtract(const Duration(hours: 3)),
        endTime: now.subtract(const Duration(hours: 1)),
      ),
      FrontingSession(
        id: 'bob-session',
        memberId: 'bob',
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(minutes: 30)),
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        frontingSessionRepositoryProvider.overrideWithValue(repo),
        allMembersProvider.overrideWith((ref) => Stream.value(members)),
        recentSleepSessionsPaginatedProvider.overrideWith(
          (ref, limit) => Stream.value(const <FrontingSession>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pumpAndSettle();

    final canvasRect = _timelineCanvasRect(tester);
    const timeGutterWidth = 52.0;
    final expectedChartLeft = (1000 - (timeGutterWidth + canvasRect.width)) / 2;

    expect(canvasRect.width, closeTo(136, 1));
    expect(canvasRect.left, closeTo(expectedChartLeft + timeGutterWidth, 1));
  });

  testWidgets('many-member timelines still overflow horizontally', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repo = FakeFrontingSessionRepository();
    final now = DateTime.now();
    final members = [
      for (var i = 0; i < 40; i++)
        Member(
          id: 'member-$i',
          name: 'Member $i',
          createdAt: DateTime(2026, 1, 1),
        ),
    ];
    repo.sessions.addAll([
      for (final member in members)
        FrontingSession(
          id: '${member.id}-session',
          memberId: member.id,
          startTime: now.subtract(const Duration(hours: 3)),
          endTime: now.subtract(const Duration(hours: 1)),
        ),
    ]);

    final container = ProviderContainer(
      overrides: [
        frontingSessionRepositoryProvider.overrideWithValue(repo),
        allMembersProvider.overrideWith((ref) => Stream.value(members)),
        recentSleepSessionsPaginatedProvider.overrideWith(
          (ref, limit) => Stream.value(const <FrontingSession>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pumpAndSettle();

    final canvasRect = _timelineCanvasRect(tester);

    expect(canvasRect.width, greaterThan(1000 - 52));
    expect(canvasRect.left, closeTo(52, 1));
  });

  testWidgets('zooming out after auto-scroll keeps culling offset in bounds', (
    tester,
  ) async {
    final repo = FakeFrontingSessionRepository();
    final member = Member(
      id: 'alice',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 21));
    repo.sessions.add(
      FrontingSession(
        id: 'long-session',
        memberId: member.id,
        startTime: start,
        endTime: now,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        frontingSessionRepositoryProvider.overrideWithValue(repo),
        allMembersProvider.overrideWith((ref) => Stream.value([member])),
        recentSleepSessionsPaginatedProvider.overrideWith(
          (ref, limit) => Stream.value(const <FrontingSession>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pumpAndSettle();

    final initialPainter = _timelinePainter(tester);
    expect(
      initialPainter.scrollOffsetNotifier!.value,
      lessThanOrEqualTo(_timelineCanvasHeight(tester)),
    );

    final notifier = container.read(timelineStateProvider.notifier);
    while (container.read(timelineStateProvider).pixelsPerHour >
        TimelineState.minPixelsPerHour) {
      notifier.zoomOut();
      await tester.pump();
    }

    final zoomedPainter = _timelinePainter(tester);
    expect(
      zoomedPainter.scrollOffsetNotifier!.value,
      lessThanOrEqualTo(_timelineCanvasHeight(tester)),
      reason: 'stale culling offset can skip every timeline bar after zoom-out',
    );
  });
}
