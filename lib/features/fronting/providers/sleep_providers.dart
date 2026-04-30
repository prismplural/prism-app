import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';

/// Watches the current active sleep session (null if not sleeping).
final activeSleepSessionProvider = StreamProvider<FrontingSession?>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchActiveSleepSession();
});

/// Recent sleep sessions (last 10). Uses a stream for real-time updates.
final recentSleepSessionsProvider =
    StreamProvider<List<FrontingSession>>((ref) {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  return repo.watchAllSleepSessions().map((all) => all.take(10).toList());
});

/// Member fronting frequency during morning hours (6am-12pm) over last 60 days.
/// Used by the wake-up sheet to suggest likely morning fronters.
///
/// Auto-rebuilds on `fronting_sessions` writes via
/// [frontingTableTickerProvider].
final morningFrontingCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  ref.watch(frontingTableTickerProvider);
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

  Future<FrontingSession> logHistoricalSleep({
    required DateTime startTime,
    required DateTime endTime,
    SleepQuality? quality,
    String? notes,
  }) =>
      ref
          .read(frontingMutationServiceProvider)
          .logHistoricalSleep(
            startTime: startTime,
            endTime: endTime,
            quality: quality,
            notes: notes,
          )
          .then((r) => r.dataOrNull!);
}

final sleepNotifierProvider =
    NotifierProvider<SleepNotifier, void>(SleepNotifier.new);
