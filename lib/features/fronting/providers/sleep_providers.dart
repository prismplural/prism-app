import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches the current active sleep session (null if not sleeping).
final activeSleepSessionProvider = StreamProvider<SleepSession?>((ref) {
  final repo = ref.watch(sleepSessionRepositoryProvider);
  return repo.watchActiveSleepSession();
});

/// Recent sleep sessions (last 10). Uses a stream for real-time updates.
final recentSleepSessionsProvider =
    StreamProvider<List<SleepSession>>((ref) {
  final repo = ref.watch(sleepSessionRepositoryProvider);
  return repo.watchAllSleepSessions().map((all) => all.take(10).toList());
});

/// Notifier for sleep session actions.
class SleepNotifier extends Notifier<void> {
  static const _uuid = Uuid();

  @override
  void build() {}

  Future<void> startSleep({
    String? notes,
    DateTime? startTime,
  }) async {
    final repo = ref.read(sleepSessionRepositoryProvider);
    final session = SleepSession(
      id: _uuid.v4(),
      startTime: startTime ?? DateTime.now(),
      notes: notes,
    );
    await repo.createSleepSession(session);
  }

  Future<void> endSleep(String id) async {
    final repo = ref.read(sleepSessionRepositoryProvider);
    await repo.endSleepSession(id, DateTime.now());
  }

  Future<void> updateSleepQuality(String id, SleepQuality quality) async {
    final repo = ref.read(sleepSessionRepositoryProvider);
    // We need to watch the active session to get the full model,
    // but for a targeted update we can construct a minimal update.
    final sessions = await repo.getRecentSleepSessions(limit: 50);
    final session = sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    await repo.updateSleepSession(session.copyWith(quality: quality));
  }

  Future<void> deleteSleep(String id) async {
    final repo = ref.read(sleepSessionRepositoryProvider);
    await repo.deleteSleepSession(id);
  }
}

final sleepNotifierProvider =
    NotifierProvider<SleepNotifier, void>(SleepNotifier.new);
