import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_analysis.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

/// Minimal SpExportData factory (CF-analysis only cares about frontHistory,
/// customFronts, and automatedTimers).
SpExportData _data({
  List<SpCustomFront> customFronts = const [],
  List<SpFrontHistory> frontHistory = const [],
  List<SpAutomatedTimer> automatedTimers = const [],
}) {
  return SpExportData(
    members: const [],
    customFronts: customFronts,
    frontHistory: frontHistory,
    groups: const [],
    channels: const [],
    messages: const [],
    polls: const [],
    automatedTimers: automatedTimers,
  );
}

void main() {
  group('analyzeCfUsage', () {
    test('seeds every listed CF with zeros even when unused', () {
      final data = _data(
        customFronts: const [
          SpCustomFront(id: 'cf-unused', name: 'Unused'),
        ],
      );
      final usage = analyzeCfUsage(data);
      expect(usage['cf-unused']!.total, 0);
      expect(usage['cf-unused']!.asPrimary, 0);
      expect(usage['cf-unused']!.asCoFronter, 0);
      expect(usage['cf-unused']!.asTimerTarget, 0);
    });

    test('counts primary, co-fronter, and timer usages correctly', () {
      final data = _data(
        customFronts: const [
          SpCustomFront(id: 'cf-sleep', name: 'Asleep'),
          SpCustomFront(id: 'cf-co', name: 'Co-fronting'),
        ],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-sleep',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'cf-sleep',
            startTime: DateTime(2024, 1, 2),
            coFronters: const ['cf-co'],
            isCustomFront: true,
          ),
          SpFrontHistory(
            id: 'f3',
            memberId: 'someone',
            coFronters: const ['cf-co', 'cf-co'],
            startTime: DateTime(2024, 1, 3),
          ),
        ],
        automatedTimers: const [
          SpAutomatedTimer(
            id: 't1',
            name: 'T',
            type: 1,
            targetId: 'cf-sleep',
          ),
        ],
      );
      final usage = analyzeCfUsage(data);
      expect(usage['cf-sleep']!.asPrimary, 2);
      expect(usage['cf-sleep']!.asCoFronter, 0);
      expect(usage['cf-sleep']!.asTimerTarget, 1);
      expect(usage['cf-co']!.asPrimary, 0);
      expect(usage['cf-co']!.asCoFronter, 3);
    });
  });

  group('suggestDefaults — smart defaults rules', () {
    test('zero-usage CF → Skip (rule 1 wins over sleep name)', () {
      // Even with a sleep-matching name, zero usage should take precedence.
      final cfs = const [SpCustomFront(id: 'cf1', name: 'Asleep')];
      final usage = {'cf1': const CfUsageStats()};
      final out = suggestDefaults(cfs, usage);
      expect(out['cf1']!.disposition, CfDisposition.skip);
      expect(out['cf1']!.reason, isNotEmpty);
    });

    test('sleep-ish name → convertToSleep (rule 2)', () {
      final cases = {
        'Sleep': CfDisposition.convertToSleep,
        'Asleep': CfDisposition.convertToSleep,
        'Sleeping beauty': CfDisposition.convertToSleep,
        'Nap time': CfDisposition.convertToSleep,
        'Napping': CfDisposition.convertToSleep,
      };
      for (final entry in cases.entries) {
        final cfs = [SpCustomFront(id: 'x', name: entry.key)];
        final usage = {
          'x': const CfUsageStats(asPrimary: 1),
        };
        final out = suggestDefaults(cfs, usage);
        expect(
          out['x']!.disposition,
          entry.value,
          reason: 'name="${entry.key}" should map to ${entry.value}',
        );
      }
    });

    test(
        'word-boundary regex does NOT match "overslept", "unsleep", "napkin"',
        () {
      final cfs = const [
        SpCustomFront(id: 'a', name: 'Overslept'),
        SpCustomFront(id: 'b', name: 'Unsleep'),
        SpCustomFront(id: 'c', name: 'Napkin folders'),
      ];
      final usage = {
        'a': const CfUsageStats(asPrimary: 5),
        'b': const CfUsageStats(asCoFronter: 5),
        'c': const CfUsageStats(asPrimary: 5),
      };
      final out = suggestDefaults(cfs, usage);
      expect(out['a']!.disposition, isNot(CfDisposition.convertToSleep));
      expect(out['b']!.disposition, isNot(CfDisposition.convertToSleep));
      expect(out['c']!.disposition, isNot(CfDisposition.convertToSleep));
    });

    test('co-fronter-only CF → mergeAsNote (rule 3)', () {
      final cfs = const [SpCustomFront(id: 'cf', name: 'Co-fronting')];
      final usage = {
        'cf': const CfUsageStats(asCoFronter: 4),
      };
      final out = suggestDefaults(cfs, usage);
      expect(out['cf']!.disposition, CfDisposition.mergeAsNote);
    });

    test('primary ≥ 50% of front-history usage → importAsMember (rule 4)', () {
      final cfs = const [SpCustomFront(id: 'cf', name: 'Blurry')];
      final usage = {
        'cf': const CfUsageStats(asPrimary: 5, asCoFronter: 5),
      };
      final out = suggestDefaults(cfs, usage);
      expect(out['cf']!.disposition, CfDisposition.importAsMember);
    });

    test('mixed usage (primary < 50%) → mergeAsNote (rule 5 default)', () {
      final cfs = const [SpCustomFront(id: 'cf', name: 'Mixed')];
      final usage = {
        'cf': const CfUsageStats(asPrimary: 1, asCoFronter: 9),
      };
      final out = suggestDefaults(cfs, usage);
      expect(out['cf']!.disposition, CfDisposition.mergeAsNote);
    });

    test('every suggestion carries a non-empty reason string', () {
      final cfs = const [
        SpCustomFront(id: 'a', name: 'Asleep'),
        SpCustomFront(id: 'b', name: 'Unused'),
        SpCustomFront(id: 'c', name: 'Co-only'),
        SpCustomFront(id: 'd', name: 'Primary'),
        SpCustomFront(id: 'e', name: 'Mixed'),
      ];
      final usage = {
        'a': const CfUsageStats(asPrimary: 2),
        'b': const CfUsageStats(),
        'c': const CfUsageStats(asCoFronter: 3),
        'd': const CfUsageStats(asPrimary: 8, asCoFronter: 1),
        'e': const CfUsageStats(asPrimary: 1, asCoFronter: 9),
      };
      final out = suggestDefaults(cfs, usage);
      for (final entry in out.entries) {
        expect(entry.value.reason, isNotEmpty,
            reason: 'CF ${entry.key} is missing a reason');
      }
    });

    test('timer-only usage still counts as non-zero (not Skip)', () {
      // A CF with no front history but a timer targeting it should not be
      // classified as zero-usage.
      final cfs = const [SpCustomFront(id: 'cf', name: 'Focus')];
      final usage = {
        'cf': const CfUsageStats(asTimerTarget: 1),
      };
      final out = suggestDefaults(cfs, usage);
      expect(out['cf']!.disposition, isNot(CfDisposition.skip));
    });
  });
}
