import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
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

ProviderContainer _container(FakeFrontingSessionRepository repo,
    List<Member> members) {
  return ProviderContainer(
    overrides: [
      frontingSessionRepositoryProvider.overrideWithValue(repo),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      recentSleepSessionsPaginatedProvider.overrideWith(
        (ref, limit) => Stream.value(const <FrontingSession>[]),
      ),
    ],
  );
}

/// Taps the on-screen center of the session bar whose id is [sessionId].
Future<void> _tapSession(WidgetTester tester, String sessionId) async {
  final painter = _timelinePainter(tester);
  final canvasRect = tester.getRect(_timelineCanvasFinder());
  final zones = painter.computeHitZones(canvasRect.size);
  final zone = zones.firstWhere((z) => z.session.id == sessionId);
  await tester.tapAt(canvasRect.topLeft + zone.rect.center);
  await tester.pumpAndSettle();
}

void main() {
  late FakeFrontingSessionRepository repo;
  late List<Member> members;

  setUp(() {
    repo = FakeFrontingSessionRepository();
    final now = DateTime.now();
    members = [
      Member(id: 'alice', name: 'Alice', createdAt: DateTime(2026, 1, 1)),
    ];
    repo.sessions.add(
      FrontingSession(
        id: 'alice-session',
        memberId: 'alice',
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(minutes: 20)),
      ),
    );
  });

  testWidgets(
    'narrow layout taps show the preview sheet before the full detail',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 800);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = _container(repo, members);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildSubject(container));
      await tester.pumpAndSettle();

      await _tapSession(tester, 'alice-session');

      // Below the side-sheet breakpoint, the compact preview is shown first.
      expect(find.text('View Details'), findsOneWidget);
      expect(find.byType(SessionDetailScreen), findsNothing);
      expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    },
  );

  testWidgets(
    'wide layout taps skip the preview and open the detail side sheet directly',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      // >= detailSideSheetMinWidth (900).
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = _container(repo, members);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildSubject(container));
      await tester.pumpAndSettle();

      await _tapSession(tester, 'alice-session');

      // The detail side sheet opens directly, skipping the preview.
      expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);
      expect(find.byType(SessionDetailScreen), findsOneWidget);
      expect(find.text('View Details'), findsNothing);
    },
  );
}
