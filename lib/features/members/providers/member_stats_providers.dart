import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';

/// Fronting statistics for a single member.
class MemberFrontingStats {
  const MemberFrontingStats({
    required this.totalSessions,
    required this.totalDuration,
    this.lastFronted,
  });

  final int totalSessions;
  final Duration totalDuration;
  final DateTime? lastFronted;
}

const _emptyFrontingStats = MemberFrontingStats(
  totalSessions: 0,
  totalDuration: Duration.zero,
);

/// Provides fronting stats for every member in a single repository read.
///
/// This is used by member/group ordering actions. Those actions may include
/// hundreds or thousands of visible members, so reading one per-member provider
/// would fan out into hundreds or thousands of session queries.
final allMemberFrontingStatsProvider =
    FutureProvider.autoDispose<Map<String, MemberFrontingStats>>((ref) async {
      ref.watch(frontingTableTickerProvider);
      final repo = ref.watch(frontingSessionRepositoryProvider);
      final sessions = await repo.getFrontingSessions();
      return aggregateMemberFrontingStats(sessions);
    });

/// Provides fronting stats (total sessions, total duration, last fronted)
/// for a given member ID.
///
/// Auto-rebuilds on `fronting_sessions` writes via
/// [frontingTableTickerProvider] (debounced for bulk imports).
final memberFrontingStatsProvider = FutureProvider.autoDispose
    .family<MemberFrontingStats, String>((ref, memberId) async {
      ref.watch(frontingTableTickerProvider);
      final repo = ref.watch(frontingSessionRepositoryProvider);
      final sessions = await repo.getSessionsForMember(memberId);
      return aggregateMemberFrontingStats(sessions)[memberId] ??
          _emptyFrontingStats;
    });

Map<String, MemberFrontingStats> aggregateMemberFrontingStats(
  Iterable<FrontingSession> sessions,
) {
  final totalSessions = <String, int>{};
  final totalDurations = <String, Duration>{};
  final lastFronted = <String, DateTime>{};

  for (final session in sessions) {
    if (session.isSleep || session.isDeleted) continue;
    final memberId = session.memberId;
    if (memberId == null) continue;

    totalSessions.update(memberId, (value) => value + 1, ifAbsent: () => 1);
    totalDurations.update(
      memberId,
      (value) => value + session.duration,
      ifAbsent: () => session.duration,
    );
    final currentLastFronted = lastFronted[memberId];
    if (currentLastFronted == null ||
        session.startTime.isAfter(currentLastFronted)) {
      lastFronted[memberId] = session.startTime;
    }
  }

  return {
    for (final entry in totalSessions.entries)
      entry.key: MemberFrontingStats(
        totalSessions: entry.value,
        totalDuration: totalDurations[entry.key] ?? Duration.zero,
        lastFronted: lastFronted[entry.key],
      ),
  };
}

/// Provides the last 5 fronting sessions for a given member ID.
///
/// Auto-rebuilds on `fronting_sessions` writes via
/// [frontingTableTickerProvider].
final memberRecentSessionsProvider = FutureProvider.autoDispose
    .family<List<FrontingSession>, String>((ref, memberId) async {
      ref.watch(frontingTableTickerProvider);
      final repo = ref.watch(frontingSessionRepositoryProvider);
      final sessions = await repo.getSessionsForMember(memberId);

      // Sort by start time descending and take at most 5.
      final sorted = [...sessions]
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

      return sorted.take(5).toList();
    });

/// Provides conversations that include a given member as a participant.
final memberConversationsProvider = FutureProvider.autoDispose
    .family<List<Conversation>, String>((ref, memberId) async {
      final repo = ref.watch(conversationRepositoryProvider);
      return repo.getConversationsForMember(memberId);
    });
