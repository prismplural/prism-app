import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeFrontingNotifier extends FrontingNotifier {
  /// Member ids passed to [startFronting]. Named "switches" because the
  /// legacy quick-front behavior switched to the held member.
  final List<String> switches = [];

  /// Member ids passed to [endFronting]. Populated when the quick-front
  /// tile is held on an already-fronting member — preserved across
  /// preference values per spec.
  final List<String> ends = [];

  /// Member ids passed to [replaceFronting]. Populated only when the
  /// `quick_front_default_behavior` preference is `replace` and the user
  /// holds a non-fronting member.
  final List<String> replaces = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    switches.addAll(memberIds);
  }

  @override
  Future<void> endFronting(List<String> memberIds) async {
    ends.addAll(memberIds);
  }

  @override
  Future<void> replaceFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
  }) async {
    replaces.addAll(memberIds);
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
  FrontStartBehavior quickFrontDefaultBehavior = FrontStartBehavior.additive,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeSessionsProvider.overrideWith((ref) => sessionsStream),
      memberFrontingCountsProvider.overrideWith((ref) async => counts),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(
          SystemSettings(quickFrontDefaultBehavior: quickFrontDefaultBehavior),
        ),
      ),
      if (notifier != null)
        frontingNotifierProvider.overrideWith(() => notifier),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: SizedBox(width: 400, child: QuickFrontSection())),
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

Future<void> _completeQuickFrontHold(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'baseline: switching the active session updates highlighted member',
    (tester) async {
      final members = [_m('a', 'Alex'), _m('b', 'Bea')];
      final controller = StreamController<List<FrontingSession>>.broadcast();
      addTearDown(controller.close);
      controller.onListen = () => controller.add([_activeSession('a')]);

      await tester.pumpWidget(
        _harness(
          members: members,
          sessionsStream: controller.stream,
          counts: {'a': 50, 'b': 30},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.text('Alex')).style?.fontWeight,
        FontWeight.bold,
      );

      controller.add([_activeSession('b')]);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.text('Alex')).style?.fontWeight,
        FontWeight.normal,
      );
      expect(
        tester.widget<Text>(find.text('Bea')).style?.fontWeight,
        FontWeight.bold,
      );
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

      await tester.pumpWidget(
        _harness(
          members: members,
          sessionsStream: controller.stream,
          counts: {'a': 50, 'b': 30},
          notifier: notifier,
        ),
      );
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

      expect(
        notifier.switches,
        ['b'],
        reason: 'long-press should have triggered startFronting(["b"])',
      );

      // B becomes the fronter, then A becomes the fronter again.
      controller.add([_activeSession('b')]);
      await tester.pumpAndSettle();
      controller.add([_activeSession('a')]);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.text('Alex')).style?.fontWeight,
        FontWeight.bold,
      );
      expect(
        tester.widget<Text>(find.text('Bea')).style?.fontWeight,
        FontWeight.normal,
      );

      expect(
        _progressRingPainterCount(tester),
        0,
        reason:
            'No progress ring should be painted after the held member '
            'loses fronter status. A non-zero count means the controller '
            'leaked at value 1.0.',
      );
    },
  );

  testWidgets(
    'long press starts ring feedback and light haptic before release',
    (tester) async {
      final hapticCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              hapticCalls.add(call);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final members = [_m('a', 'Alex'), _m('b', 'Bea')];
      final controller = StreamController<List<FrontingSession>>.broadcast();
      addTearDown(controller.close);
      controller.onListen = () => controller.add([_activeSession('a')]);

      final notifier = _FakeFrontingNotifier();
      await tester.pumpWidget(
        _harness(
          members: members,
          sessionsStream: controller.stream,
          counts: {'a': 50, 'b': 30},
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Bea')),
      );
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_progressRingPainterCount(tester), 1);
      expect(
        hapticCalls.any(
          (call) => call.arguments == 'HapticFeedbackType.lightImpact',
        ),
        isTrue,
      );
      expect(notifier.switches, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(notifier.switches, isEmpty);
    },
  );

  testWidgets('a plain tap does not quick-front', (tester) async {
    final members = [_m('a', 'Alex'), _m('b', 'Bea')];
    final controller = StreamController<List<FrontingSession>>.broadcast();
    addTearDown(controller.close);
    controller.onListen = () => controller.add([_activeSession('a')]);

    final notifier = _FakeFrontingNotifier();
    await tester.pumpWidget(
      _harness(
        members: members,
        sessionsStream: controller.stream,
        counts: {'a': 50, 'b': 30},
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bea'));
    await tester.pumpAndSettle();

    expect(notifier.switches, isEmpty);
    expect(notifier.ends, isEmpty);
    expect(notifier.replaces, isEmpty);
  });

  group('quick-front hold honors quick_front_default_behavior', () {
    testWidgets(
      'holding an already-fronting member ends them (additive pref)',
      (tester) async {
        final members = [_m('a', 'Alex'), _m('b', 'Bea')];
        final controller = StreamController<List<FrontingSession>>.broadcast();
        addTearDown(controller.close);
        controller.onListen = () => controller.add([_activeSession('a')]);

        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _harness(
            members: members,
            sessionsStream: controller.stream,
            counts: {'a': 50, 'b': 30},
            notifier: notifier,
            // additive is default — but explicit for clarity.
          ),
        );
        await tester.pumpAndSettle();

        // Alex IS fronting → completed hold should end, not start or replace.
        await _completeQuickFrontHold(tester, find.text('Alex'));

        expect(notifier.ends, ['a']);
        expect(notifier.switches, isEmpty);
        expect(notifier.replaces, isEmpty);
      },
    );

    testWidgets(
      'holding an already-fronting member ends them (replace pref preserved)',
      (tester) async {
        // Per spec, holding an active fronter ALWAYS ends them — preserved
        // regardless of `quick_front_default_behavior`.
        final members = [_m('a', 'Alex'), _m('b', 'Bea')];
        final controller = StreamController<List<FrontingSession>>.broadcast();
        addTearDown(controller.close);
        controller.onListen = () => controller.add([_activeSession('a')]);

        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _harness(
            members: members,
            sessionsStream: controller.stream,
            counts: {'a': 50, 'b': 30},
            notifier: notifier,
            quickFrontDefaultBehavior: FrontStartBehavior.replace,
          ),
        );
        await tester.pumpAndSettle();

        // Alex IS fronting → hold should end, NOT replace, even when the
        // preference is `replace`. The replace pref only governs the
        // non-fronting hold path.
        await _completeQuickFrontHold(tester, find.text('Alex'));

        expect(notifier.ends, ['a']);
        expect(
          notifier.replaces,
          isEmpty,
          reason:
              'replace pref must NOT change the end-on-hold-of-active '
              'behavior',
        );
        expect(notifier.switches, isEmpty);
      },
    );

    testWidgets(
      'holding a non-fronting member in additive pref calls startFronting',
      (tester) async {
        final members = [_m('a', 'Alex'), _m('b', 'Bea')];
        final controller = StreamController<List<FrontingSession>>.broadcast();
        addTearDown(controller.close);
        controller.onListen = () => controller.add([_activeSession('a')]);

        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _harness(
            members: members,
            sessionsStream: controller.stream,
            counts: {'a': 50, 'b': 30},
            notifier: notifier,
            quickFrontDefaultBehavior: FrontStartBehavior.additive,
          ),
        );
        await tester.pumpAndSettle();

        // Bea is NOT fronting → completed hold should start, not replace.
        await _completeQuickFrontHold(tester, find.text('Bea'));

        expect(notifier.switches, ['b']);
        expect(notifier.replaces, isEmpty);
        expect(notifier.ends, isEmpty);
      },
    );

    testWidgets(
      'holding a non-fronting member in replace pref calls replaceFronting',
      (tester) async {
        final members = [_m('a', 'Alex'), _m('b', 'Bea')];
        final controller = StreamController<List<FrontingSession>>.broadcast();
        addTearDown(controller.close);
        controller.onListen = () => controller.add([_activeSession('a')]);

        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _harness(
            members: members,
            sessionsStream: controller.stream,
            counts: {'a': 50, 'b': 30},
            notifier: notifier,
            quickFrontDefaultBehavior: FrontStartBehavior.replace,
          ),
        );
        await tester.pumpAndSettle();

        // Bea is NOT fronting → hold should call replaceFronting (atomic
        // end-actives + start-new), not startFronting.
        await _completeQuickFrontHold(tester, find.text('Bea'));

        expect(notifier.replaces, ['b']);
        expect(
          notifier.switches,
          isEmpty,
          reason: 'replace pref must call replaceFronting, not startFronting',
        );
        expect(notifier.ends, isEmpty);
      },
    );
  });
}
