import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/settings/models/analytics_insight.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

void main() {
  group('computeInsights', () {
    // Helper to build FrontingAnalytics with the relevant fields only
    FrontingAnalytics makeAnalytics({
      Duration totalGapTime = Duration.zero,
      Duration rangeSpan = const Duration(days: 30),
      List<MemberAnalytics> memberStats = const [],
      List<CoFrontingPair> topCoFrontingPairs = const [],
    }) {
      final now = DateTime.utc(2026, 3, 1);
      return FrontingAnalytics(
        rangeStart: now,
        rangeEnd: now.add(rangeSpan),
        totalTrackedTime: Duration.zero,
        totalGapTime: totalGapTime,
        totalSessions: 0,
        uniqueFronters: 0,
        switchesPerDay: 0,
        memberStats: memberStats,
        topCoFrontingPairs: topCoFrontingPairs,
      );
    }

    MemberAnalytics makeMember(
      String id, {
      int totalMinutes = 60,
      int sessionCount = 5,
      int avgMinutes = 12,
      Map<String, int>? timeOfDay,
    }) =>
        MemberAnalytics(
          memberId: id,
          totalTime: Duration(minutes: totalMinutes),
          percentageOfTotal: 50,
          sessionCount: sessionCount,
          averageDuration: Duration(minutes: avgMinutes),
          medianDuration: Duration(minutes: avgMinutes),
          shortestSession: const Duration(minutes: 5),
          longestSession: const Duration(minutes: 30),
          timeOfDayBreakdown: timeOfDay ?? {'morning': 60},
        );

    test('no sessions produces no insights', () {
      final current = makeAnalytics();
      expect(computeInsights(current, null), isEmpty);
    });

    test('gap > 25% fires gapAlert', () {
      // 30-day range = 43200 minutes; gap of 12000 min = 27.7%
      final current = makeAnalytics(
        totalGapTime: const Duration(minutes: 12000),
        rangeSpan: const Duration(days: 30),
      );
      final insights = computeInsights(current, null);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.gapAlert), isTrue);
    });

    test('gap <= 25% does not fire gapAlert', () {
      // 30-day range; gap of 10000 min = 23.1%
      final current = makeAnalytics(
        totalGapTime: const Duration(minutes: 10000),
        rangeSpan: const Duration(days: 30),
      );
      final insights = computeInsights(current, null);
      expect(insights.any((i) => i.type == AnalyticsInsightType.gapAlert),
          isFalse);
    });

    test('member in previous but not current fires quietMember', () {
      final current = makeAnalytics(memberStats: [makeMember('a')]);
      final previous =
          makeAnalytics(memberStats: [makeMember('a'), makeMember('b')]);
      final insights = computeInsights(current, previous);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.quietMember),
          isTrue);
    });

    test('member only in current (not in previous) does not fire quietMember',
        () {
      final current =
          makeAnalytics(memberStats: [makeMember('a'), makeMember('b')]);
      final previous = makeAnalytics(memberStats: [makeMember('a')]);
      final insights = computeInsights(current, previous);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.quietMember),
          isFalse);
    });

    test(
        'session drift >= 25% with >= 2 prior sessions fires sessionDrift', () {
      final current =
          makeAnalytics(memberStats: [makeMember('a', avgMinutes: 20)]);
      final previous = makeAnalytics(
          memberStats: [makeMember('a', avgMinutes: 10, sessionCount: 3)]);
      final insights = computeInsights(current, previous);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.sessionDrift),
          isTrue);
    });

    test('session drift with only 1 prior session does not fire', () {
      final current =
          makeAnalytics(memberStats: [makeMember('a', avgMinutes: 20)]);
      final previous = makeAnalytics(
          memberStats: [makeMember('a', avgMinutes: 10, sessionCount: 1)]);
      final insights = computeInsights(current, previous);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.sessionDrift),
          isFalse);
    });

    test('session drift < 25% does not fire', () {
      final current =
          makeAnalytics(memberStats: [makeMember('a', avgMinutes: 12)]);
      final previous = makeAnalytics(
          memberStats: [makeMember('a', avgMinutes: 10, sessionCount: 3)]);
      final insights = computeInsights(current, previous);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.sessionDrift),
          isFalse);
    });

    test('co-fronting pair fires coFrontingHighlight', () {
      const pair = CoFrontingPair(
          memberIdA: 'a',
          memberIdB: 'b',
          totalTime: Duration(hours: 5));
      final current = makeAnalytics(topCoFrontingPairs: [pair]);
      final insights = computeInsights(current, null);
      expect(
          insights
              .any((i) => i.type == AnalyticsInsightType.coFrontingHighlight),
          isTrue);
    });

    test('no co-fronting pairs does not fire coFrontingHighlight', () {
      final current = makeAnalytics();
      final insights = computeInsights(current, null);
      expect(
          insights
              .any((i) => i.type == AnalyticsInsightType.coFrontingHighlight),
          isFalse);
    });

    test('previous null suppresses quietMember, sessionDrift, timeOfDayShift',
        () {
      final current = makeAnalytics(memberStats: [makeMember('a')]);
      final insights = computeInsights(current, null);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.quietMember),
          isFalse);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.sessionDrift),
          isFalse);
      expect(
          insights.any((i) => i.type == AnalyticsInsightType.timeOfDayShift),
          isFalse);
    });

    test('max 3 insights returned even when 5 conditions trigger', () {
      // Gap alert + quiet member + session drift + co-fronting + time shift
      const pair = CoFrontingPair(
          memberIdA: 'a',
          memberIdB: 'c',
          totalTime: Duration(hours: 3));
      final current = makeAnalytics(
        totalGapTime: const Duration(minutes: 12000),
        rangeSpan: const Duration(days: 30),
        memberStats: [
          makeMember('a',
              avgMinutes: 30, timeOfDay: {'evening': 90})
        ],
        topCoFrontingPairs: [pair],
      );
      final previous = makeAnalytics(
        memberStats: [
          makeMember('a',
              avgMinutes: 10, sessionCount: 3, timeOfDay: {'morning': 90}),
          makeMember('b'), // quiet member
        ],
      );
      final insights = computeInsights(current, previous);
      expect(insights.length, lessThanOrEqualTo(3));
    });

    test('results sorted by signalStrength descending', () {
      const pair = CoFrontingPair(
          memberIdA: 'a',
          memberIdB: 'b',
          totalTime: Duration(hours: 2));
      final current = makeAnalytics(
        totalGapTime: const Duration(minutes: 12000),
        rangeSpan: const Duration(days: 30),
        topCoFrontingPairs: [pair],
      );
      final insights = computeInsights(current, null);
      for (var i = 0; i < insights.length - 1; i++) {
        expect(insights[i].signalStrength,
            greaterThanOrEqualTo(insights[i + 1].signalStrength));
      }
    });

    test('coFrontingHighlight names both members when names provided', () {
      const pair = CoFrontingPair(
          memberIdA: 'a',
          memberIdB: 'b',
          totalTime: Duration(hours: 5));
      final current = makeAnalytics(topCoFrontingPairs: [pair]);
      final insights = computeInsights(
        current,
        null,
        names: const {'a': 'Alice', 'b': 'Bob'},
      );
      final coFront = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.coFrontingHighlight);
      expect(coFront.headline, contains('Alice'));
      expect(coFront.headline, contains('Bob'));
    });

    test('coFrontingHighlight falls back when either name is missing', () {
      const pair = CoFrontingPair(
          memberIdA: 'a',
          memberIdB: 'b',
          totalTime: Duration(hours: 5));
      final current = makeAnalytics(topCoFrontingPairs: [pair]);
      // Only one of the pair has a name in the map.
      final insights = computeInsights(
        current,
        null,
        names: const {'a': 'Alice'},
      );
      final coFront = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.coFrontingHighlight);
      expect(coFront.headline, 'Two members co-fronted a lot this period');
    });

    test('quietMember headline names the member when name provided', () {
      final current = makeAnalytics(memberStats: [makeMember('a')]);
      final previous = makeAnalytics(
          memberStats: [makeMember('a'), makeMember('b')]);
      final insights = computeInsights(
        current,
        previous,
        names: const {'b': 'Bob'},
      );
      final quiet = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.quietMember);
      expect(quiet.headline, startsWith('Bob'));
    });

    test('sessionDrift headline names the member when name provided', () {
      final current =
          makeAnalytics(memberStats: [makeMember('a', avgMinutes: 30)]);
      final previous = makeAnalytics(memberStats: [
        makeMember('a', avgMinutes: 10, sessionCount: 3),
      ]);
      final insights = computeInsights(
        current,
        previous,
        names: const {'a': 'Alice'},
      );
      final drift = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.sessionDrift);
      expect(drift.headline, startsWith("Alice's"));
    });

    test('timeOfDayShift headline names the member when name provided', () {
      final current = makeAnalytics(memberStats: [
        makeMember('a', timeOfDay: {'evening': 90}),
      ]);
      final previous = makeAnalytics(memberStats: [
        makeMember('a', timeOfDay: {'morning': 90}),
      ]);
      final insights = computeInsights(
        current,
        previous,
        names: const {'a': 'Alice'},
      );
      final shift = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.timeOfDayShift);
      expect(shift.headline, startsWith('Alice'));
    });

    test('headlines fall back to generic copy when names map is empty', () {
      const pair = CoFrontingPair(
          memberIdA: 'a',
          memberIdB: 'b',
          totalTime: Duration(hours: 5));
      final coFrontInsights = computeInsights(
          makeAnalytics(topCoFrontingPairs: [pair]), null);
      expect(
          coFrontInsights
              .firstWhere(
                  (i) => i.type == AnalyticsInsightType.coFrontingHighlight)
              .headline,
          'Two members co-fronted a lot this period');

      final quietInsights = computeInsights(
        makeAnalytics(memberStats: [makeMember('a')]),
        makeAnalytics(memberStats: [makeMember('a'), makeMember('b')]),
      );
      expect(
          quietInsights
              .firstWhere((i) => i.type == AnalyticsInsightType.quietMember)
              .headline,
          "One member hasn't fronted this period");

      final driftInsights = computeInsights(
        makeAnalytics(memberStats: [makeMember('a', avgMinutes: 30)]),
        makeAnalytics(
            memberStats: [makeMember('a', avgMinutes: 10, sessionCount: 3)]),
      );
      expect(
          driftInsights
              .firstWhere((i) => i.type == AnalyticsInsightType.sessionDrift)
              .headline,
          contains('a member'));

      final shiftInsights = computeInsights(
        makeAnalytics(memberStats: [
          makeMember('a', timeOfDay: {'evening': 90}),
        ]),
        makeAnalytics(memberStats: [
          makeMember('a', timeOfDay: {'morning': 90}),
        ]),
      );
      expect(
          shiftInsights
              .firstWhere((i) => i.type == AnalyticsInsightType.timeOfDayShift)
              .headline,
          "A member's fronting time of day shifted");
    });

    test('empty-string name falls back to generic copy', () {
      final current = makeAnalytics(memberStats: [makeMember('a')]);
      final previous = makeAnalytics(
          memberStats: [makeMember('a'), makeMember('b')]);
      final insights = computeInsights(
        current,
        previous,
        names: const {'b': ''}, // present but empty
      );
      final quiet = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.quietMember);
      expect(quiet.headline, "One member hasn't fronted this period");
    });

    test('quietMember surfaces the highest-totalTime member', () {
      // Members 'b' and 'c' are both quiet; 'c' has more prior-period time.
      final current = makeAnalytics(memberStats: [makeMember('a')]);
      final previous = makeAnalytics(memberStats: [
        makeMember('a'),
        makeMember('b', totalMinutes: 30),
        makeMember('c', totalMinutes: 240),
      ]);
      final insights = computeInsights(
        current,
        previous,
        names: const {'b': 'Bob', 'c': 'Cassie'},
      );
      final quiet = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.quietMember);
      expect(quiet.headline, startsWith('Cassie'));
    });

    test('quietMember breaks totalTime ties by memberId for determinism', () {
      // Members 'b' and 'a-second' are tied on totalTime; 'a-second' sorts
      // earlier alphabetically, so it wins.
      final current = makeAnalytics(memberStats: [makeMember('keeper')]);
      final previous = makeAnalytics(memberStats: [
        makeMember('keeper'),
        makeMember('b', totalMinutes: 60),
        makeMember('a-second', totalMinutes: 60),
      ]);
      final insights = computeInsights(
        current,
        previous,
        names: const {'b': 'Bob', 'a-second': 'Alex'},
      );
      final quiet = insights.firstWhere(
          (i) => i.type == AnalyticsInsightType.quietMember);
      expect(quiet.headline, startsWith('Alex'));
    });
  });
}
