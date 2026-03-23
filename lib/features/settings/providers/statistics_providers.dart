import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

// ── Stat providers ─────────────────────────────────────────

/// Count-only provider for total members (uses SQL COUNT).
final memberCountStatProvider = FutureProvider<int>((ref) {
  return ref.watch(memberRepositoryProvider).getCount();
});

/// Count-only provider for total sessions (uses SQL COUNT).
final sessionCountStatProvider = FutureProvider<int>((ref) {
  return ref.watch(frontingSessionRepositoryProvider).getCount();
});

/// Full member list — still needed for active/inactive breakdown and top fronters.
final allMembersStatProvider = FutureProvider<List<Member>>((ref) {
  return ref.watch(memberRepositoryProvider).getAllMembers();
});

/// Full session list — still needed for top fronters and average duration.
final allSessionsStatProvider = FutureProvider<List<FrontingSession>>((ref) {
  return ref.watch(frontingSessionRepositoryProvider).getAllSessions();
});

final allConversationsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(conversationRepositoryProvider).getCount();
});

final allPollsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(pollRepositoryProvider).getCount();
});

/// Top fronters sorted by session count descending.
final topFrontersProvider = FutureProvider<List<MapEntry<Member, int>>>((ref) async {
  final sessions = await ref.watch(allSessionsStatProvider.future);
  final members = await ref.watch(allMembersStatProvider.future);
  final counts = <String, int>{};
  for (final session in sessions) {
    if (session.memberId != null) {
      counts[session.memberId!] = (counts[session.memberId!] ?? 0) + 1;
    }
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final memberMap = {for (final m in members) m.id: m};
  return sorted
      .where((e) => memberMap.containsKey(e.key))
      .map((e) => MapEntry(memberMap[e.key]!, e.value))
      .toList();
});
