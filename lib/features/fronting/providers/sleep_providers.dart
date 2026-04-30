import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';

/// Aggregate sleep statistics for display in the sleep history view.
@immutable
class SleepStatsView {
  const SleepStatsView({
    required this.totalEverCount,
    required this.lastNight,
    required this.avg7d,
    required this.avg7dPrior,
  });

  final int totalEverCount;
  final FrontingSession? lastNight;
  final ({int count, Duration? avgDuration}) avg7d;
  final ({int count, Duration? avgDuration}) avg7dPrior;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SleepStatsView &&
        other.totalEverCount == totalEverCount &&
        other.lastNight == lastNight &&
        other.avg7d.count == avg7d.count &&
        other.avg7d.avgDuration == avg7d.avgDuration &&
        other.avg7dPrior.count == avg7dPrior.count &&
        other.avg7dPrior.avgDuration == avg7dPrior.avgDuration;
  }

  @override
  int get hashCode => Object.hash(
        totalEverCount,
        lastNight,
        avg7d.count,
        avg7d.avgDuration,
        avg7dPrior.count,
        avg7dPrior.avgDuration,
      );
}

/// Watches the current active sleep session (null if not sleeping).
final activeSleepSessionProvider = StreamProvider<FrontingSession?>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchActiveSleepSession();
});

/// Sleep stats for the current and prior 7-day windows, plus an all-time count.
///
/// IMPORTANT: this provider must be **watched** (not just `read`) by a widget
/// with screen lifetime. autoDispose means a short-lived ref (e.g. inside a
/// scroll callback) would dispose it immediately, triggering a fresh DB fetch
/// on every re-read.
final sleepStatsProvider =
    FutureProvider.autoDispose<SleepStatsView>((ref) async {
  ref.watch(frontingTableTickerProvider);

  final repo = ref.watch(frontingSessionRepositoryProvider);
  final now = DateTime.now();
  final minus7d = now.subtract(const Duration(days: 7));
  final minus14d = now.subtract(const Duration(days: 14));
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final results = await Future.wait([
    repo.getSleepStats(since: minus7d),
    repo.getSleepStats(since: minus14d, until: minus7d),
    repo.getSleepStats(since: epoch),
  ]);

  final current7d = results[0];
  final prior7d = results[1];
  final allTime = results[2];

  final recent = await repo.watchRecentSleepSessions(limit: 1).first;
  final lastNight = recent.isEmpty ? null : recent.first;

  return SleepStatsView(
    totalEverCount: allTime.count,
    lastNight: lastNight,
    avg7d: current7d,
    avg7dPrior: prior7d,
  );
});

/// Recent completed sleep sessions, parameterized by limit.
/// Default limit of 20 is appropriate for most list views.
final recentSleepSessionsPaginatedProvider = StreamProvider.autoDispose
    .family<List<FrontingSession>, int>((ref, limit) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchRecentSleepSessions(limit: limit);
});

/// Member fronting frequency during morning hours (6am-12pm) over last 60 days.
/// Used by the wake-up sheet to suggest likely morning fronters.
final morningFrontingCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.getMemberFrontingCounts(
    startHour: 6,
    endHour: 11,
    withinDays: 60,
  );
});

/// Notifier for sleep session actions.
class SleepNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> startSleep({
    String? notes,
    DateTime? startTime,
    SleepQuality? quality,
  }) async {
    await ref.read(frontingMutationServiceProvider).startSleep(
      notes: notes,
      startTime: startTime,
      quality: quality,
    );
  }

  Future<void> endSleep(String id) async {
    await ref.read(frontingMutationServiceProvider).endSleep(id);
  }

  Future<void> updateSleepQuality(String id, SleepQuality quality) async {
    await ref.read(frontingMutationServiceProvider).updateSleepQuality(
      id,
      quality,
    );
  }

  Future<void> deleteSleep(String id) async {
    await ref.read(frontingMutationServiceProvider).deleteSleep(id);
  }
}

final sleepNotifierProvider =
    NotifierProvider<SleepNotifier, void>(SleepNotifier.new);
