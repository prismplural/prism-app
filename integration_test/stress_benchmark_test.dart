// Manual pre-release benchmark — measures frame timing across screens.
//
// Run on a real device in profile mode:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/stress_benchmark_test.dart \
//     --profile
//
// For stress testing, seed data via the debug screen first, then run this
// benchmark. The traceAction calls produce timeline traces that can be
// analyzed for frame build/rasterize times.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/migration/services/sp_reply_quote_backfill_service.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';
import 'package:prism_plurality/main.dart' as app;
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

const _preRepairReplyQuotes = bool.fromEnvironment(
  'PRISM_BENCHMARK_PRE_REPAIR_REPLY_QUOTES',
);
const _presetName = String.fromEnvironment(
  'PRISM_STRESS_PRESET',
  defaultValue: 'reportedLarge',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Stress benchmark', () {
    testWidgets('measure frame timing with stress data', (tester) async {
      await _ensureStressFixture();

      final launchSw = Stopwatch()..start();
      await binding.traceAction(() async {
        // Launch the app.
        app.main();
        await tester.pump();
        await _pumpUntilVisible(
          tester,
          find.descendant(
            of: find.byType(QuickFrontSection),
            matching: find.byType(MemberAvatar),
          ),
          maxPumps: 120,
        );
      }, reportKey: 'quick_front_initial_render');
      // ignore: avoid_print
      print('[startup-visible] quickFront=${launchSw.elapsedMilliseconds}ms');

      final frontingListSw = Stopwatch()..start();
      await binding.traceAction(() async {
        await _pumpUntilVisible(
          tester,
          find.descendant(
            of: find.byType(SessionHistoryList),
            matching: find.byType(FrontingHistoryRowMarker),
          ),
          maxPumps: 120,
        );
        // ignore: avoid_print
        print(
          '[startup-visible] frontingRows=${frontingListSw.elapsedMilliseconds}ms',
        );
        final scrollable = find.byType(Scrollable).first;
        if (scrollable.evaluate().isNotEmpty) {
          await tester.fling(scrollable, const Offset(0, -700), 1200);
          await _pumpFor(tester, const Duration(seconds: 1));
        }
      }, reportKey: 'fronting_list_initial_scroll');

      await binding.traceAction(() async {
        await tester.pump(const Duration(seconds: 1));
        final scrollable = find.byType(Scrollable).first;
        if (scrollable.evaluate().isNotEmpty) {
          await tester.fling(scrollable, const Offset(0, -500), 1000);
          await _pumpFor(tester, const Duration(seconds: 1));
        }
      }, reportKey: 'home_scroll_timeline');

      // --- Chat tab ---
      await binding.traceAction(() async {
        final chatTab = find.text('Chat');
        if (chatTab.evaluate().isNotEmpty) {
          await tester.tap(chatTab);
          await _pumpFor(tester, const Duration(seconds: 2));
        }
      }, reportKey: 'chat_list_render');

      // --- Habits tab ---
      await binding.traceAction(() async {
        final habitsTab = find.text('Habits');
        if (habitsTab.evaluate().isNotEmpty) {
          await tester.tap(habitsTab);
          await _pumpFor(tester, const Duration(seconds: 2));
        }
      }, reportKey: 'habits_render');

      // --- Polls tab ---
      await binding.traceAction(() async {
        final pollsTab = find.text('Polls');
        if (pollsTab.evaluate().isNotEmpty) {
          await tester.tap(pollsTab);
          await _pumpFor(tester, const Duration(seconds: 2));
        }
      }, reportKey: 'polls_render');

      // --- Settings tab ---
      await binding.traceAction(() async {
        final settingsTab = find.text('Settings');
        if (settingsTab.evaluate().isNotEmpty) {
          await tester.tap(settingsTab);
          await _pumpFor(tester, const Duration(seconds: 2));
        }
      }, reportKey: 'settings_render');
    });
  });
}

Future<void> _ensureStressFixture() async {
  final preset = _stressPreset();
  final probe = await probeAppDatabaseStartup();
  if (probe.state != DbStartupState.ready || probe.keyInMemory == null) {
    // ignore: avoid_print
    print('[stress-counts] database not ready: ${probe.state}');
    return;
  }

  final container = ProviderContainer(
    overrides: [
      verifiedStartupKeyProvider.overrideWithValue(probe.keyInMemory),
    ],
  );
  try {
    final db = container.read(databaseProvider);
    var counts = await _readStressCounts(db);

    if (counts.members != preset.members || counts.groups != preset.groups) {
      final started = DateTime.now();
      final generator = StressDataGenerator(db);
      await generator.clearStressData();
      await for (final progress in generator.generate(preset)) {
        final percent = (progress.fraction * 100).toStringAsFixed(1);
        // ignore: avoid_print
        print('[stress-seed] ${progress.phase}: $percent%');
      }
      await db.systemSettingsDao.updateSystemName(
        'Prism ${preset.label} Fixture',
      );
      await db.systemSettingsDao.updateHasCompletedOnboarding(true);
      await db.systemSettingsDao.updateBoardsEnabled(true);
      await db.systemSettingsDao.updateSleepTrackingEnabled(true);
      counts = await _readStressCounts(db);
      // ignore: avoid_print
      print(
        '[stress-seed] elapsed=${DateTime.now().difference(started).inSeconds}s',
      );
    }

    if (_preRepairReplyQuotes) {
      final started = DateTime.now();
      final result = await SpReplyQuoteBackfillService(db: db).run();
      // ignore: avoid_print
      print(
        '[stress-pre-repair] replyQuotes=${result.messagesRepaired} '
        'elapsed=${DateTime.now().difference(started).inMilliseconds}ms',
      );
    }

    final hasReplyQuoteCandidates =
        await SpReplyQuoteBackfillService.hasCandidates(db);
    // ignore: avoid_print
    print(
      '[stress-counts] members=${counts.members} '
      'groups=${counts.groups} '
      'customFieldValues=${counts.customFieldValues} '
      'replyQuoteCandidates=$hasReplyQuoteCandidates',
    );
  } finally {
    container.dispose();
  }
}

StressPreset _stressPreset() {
  return switch (_presetName) {
    'reportedLarge' => StressPreset.reportedLarge,
    'heavy5k' => StressPreset.heavyFiveThousand,
    'huge' => StressPreset.huge,
    'massive' => StressPreset.massive,
    _ => throw ArgumentError('Unknown PRISM_STRESS_PRESET: $_presetName'),
  };
}

Future<_StressCounts> _readStressCounts(dynamic db) async {
  final memberCount = await db
      .customSelect(
        "SELECT COUNT(*) AS c FROM members WHERE id LIKE 'stress-%'",
      )
      .getSingle();
  final groupCount = await db
      .customSelect(
        "SELECT COUNT(*) AS c FROM member_groups WHERE id LIKE 'stress-%'",
      )
      .getSingle();
  final customFieldValueCount = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM custom_field_values '
        "WHERE id LIKE 'stress-%'",
      )
      .getSingle();
  return _StressCounts(
    members: memberCount.read<int>('c'),
    groups: groupCount.read<int>('c'),
    customFieldValues: customFieldValueCount.read<int>('c'),
  );
}

class _StressCounts {
  const _StressCounts({
    required this.members,
    required this.groups,
    required this.customFieldValues,
  });

  final int members;
  final int groups;
  final int customFieldValues;
}

Future<void> _pumpFor(
  WidgetTester tester,
  Duration duration, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}
