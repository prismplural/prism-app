import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeFrontingNotifier extends FrontingNotifier {
  final List<String> switches = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> switchFronter(String newMemberId) async {
    switches.add(newMemberId);
  }
}

Member _m(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

FrontingSession _activeSession(String memberId) => FrontingSession(
      id: 'session-$memberId',
      startTime: DateTime(2026, 1, 1, 12),
      memberId: memberId,
    );

Widget _harness({
  required List<Member> members,
  required Stream<List<FrontingSession>> sessionsStream,
  required Map<String, int> counts,
  _FakeFrontingNotifier? notifier,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeSessionsProvider.overrideWith((ref) => sessionsStream),
      memberFrontingCountsProvider.overrideWith((ref) async => counts),
      if (notifier != null)
        frontingNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: const Scaffold(
        body: SizedBox(width: 400, child: QuickFrontSection()),
      ),
    ),
  );
}

int _progressRingPainterCount(WidgetTester tester) {
  var count = 0;
  for (final cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (cp.painter?.runtimeType.toString() == '_ProgressRingPainter') {
      count++;
    }
  }
  return count;
}

void main() {
  testWidgets(
    'baseline: switching the active session updates highlighted member',
    (tester) async {
      final members = [_m('a', 'Alex'), _m('b', 'Bea')];
      final controller = StreamController<List<FrontingSession>>.broadcast();
      addTearDown(controller.close);
      controller.onListen = () => controller.add([_activeSession('a')]);

      await tester.pumpWidget(_harness(
        members: members,
        sessionsStream: controller.stream,
        counts: {'a': 50, 'b': 30},
      ));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('Alex')).style?.fontWeight,
          FontWeight.bold);

      controller.add([_activeSession('b')]);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('Alex')).style?.fontWeight,
          FontWeight.normal);
      expect(tester.widget<Text>(find.text('Bea')).style?.fontWeight,
          FontWeight.bold);
    },
  );

  testWidgets(
    'regression: hold-to-front does not leave a phantom progress ring on the '
    'held member after they later become non-fronting',
    (tester) async {
      // Real user flow:
      //   1. A is fronting.
      //   2. Long-press B → hold-to-front timer completes → switch to B.
      //   3. Some time later, A becomes the fronter again (any path).
      // Without the fix, B's AnimationController stayed at 1.0 because
      // _onPressEnd reset only while isAnimating — a *completed* animation
      // is not animating. When B later transitioned to widget.isFronting=false,
      // its AnimatedBuilder branch painted a full _ProgressRingPainter,
      // visually re-highlighting B.
      final members = [_m('a', 'Alex'), _m('b', 'Bea')];
      final controller = StreamController<List<FrontingSession>>.broadcast();
      addTearDown(controller.close);
      controller.onListen = () => controller.add([_activeSession('a')]);

      final notifier = _FakeFrontingNotifier();

      await tester.pumpWidget(_harness(
        members: members,
        sessionsStream: controller.stream,
        counts: {'a': 50, 'b': 30},
        notifier: notifier,
      ));
      await tester.pumpAndSettle();

      // Long-press B in 50ms ticks so the long-press recognizer (500ms) and
      // the in-widget controller (800ms) both fire naturally.
      final beaCenter = tester.getCenter(find.text('Bea'));
      final gesture = await tester.startGesture(beaCenter);
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(notifier.switches, ['b'],
          reason: 'long-press should have triggered switchFronter("b")');

      // B becomes the fronter, then A becomes the fronter again.
      controller.add([_activeSession('b')]);
      await tester.pumpAndSettle();
      controller.add([_activeSession('a')]);
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('Alex')).style?.fontWeight,
          FontWeight.bold);
      expect(tester.widget<Text>(find.text('Bea')).style?.fontWeight,
          FontWeight.normal);

      expect(_progressRingPainterCount(tester), 0,
          reason:
              'No progress ring should be painted after the held member '
              'loses fronter status. A non-zero count means the controller '
              'leaked at value 1.0.');
    },
  );
}
