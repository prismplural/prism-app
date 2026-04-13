import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';

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

/// Provides fronting stats (total sessions, total duration, last fronted)
/// for a given member ID.
final memberFrontingStatsProvider =
    FutureProvider.autoDispose.family<MemberFrontingStats, String>((ref, memberId) async {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  final sessions = await repo.getSessionsForMember(memberId);

  if (sessions.isEmpty) {
    return const MemberFrontingStats(
      totalSessions: 0,
      totalDuration: Duration.zero,
    );
  }

  final totalDuration = sessions.fold<Duration>(
    Duration.zero,
    (sum, session) => sum + session.duration,
  );

  // Find the most recent session start time.
  final sorted = [...sessions]
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  final lastFronted = sorted.first.startTime;

  return MemberFrontingStats(
    totalSessions: sessions.length,
    totalDuration: totalDuration,
    lastFronted: lastFronted,
  );
});

/// Provides the last 5 fronting sessions for a given member ID.
final memberRecentSessionsProvider =
    FutureProvider.autoDispose.family<List<FrontingSession>, String>((ref, memberId) async {
  final repo = ref.watch(frontingSessionRepositoryProvider);
  final sessions = await repo.getSessionsForMember(memberId);

  // Sort by start time descending and take at most 5.
  final sorted = [...sessions]
    ..sort((a, b) => b.startTime.compareTo(a.startTime));

  return sorted.take(5).toList();
});

/// Provides conversations that include a given member as a participant.
final memberConversationsProvider =
    FutureProvider.autoDispose.family<List<Conversation>, String>((ref, memberId) async {
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.getConversationsForMember(memberId);
});
