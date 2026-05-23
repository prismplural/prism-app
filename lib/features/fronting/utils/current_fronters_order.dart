import 'package:prism_plurality/domain/models/models.dart';

/// Orders members currently in front for the quick-front bar.
///
/// Most-recently-started first (leftmost). Ties on `startTime` — every
/// multi-select gesture shares one captured `now` — resolve by
/// [Member.displayOrder] then id. Without an explicit tiebreaker the order
/// falls through to SQLite rowid, which equals selection order and reads
/// as random to the user.
///
/// Skips sessions whose memberId doesn't resolve in [members].
List<Member> orderCurrentFronters(
  List<FrontingSession> activeSessions,
  List<Member> members,
) {
  if (activeSessions.isEmpty) return const [];

  final membersById = {for (final m in members) m.id: m};
  final entries = <_FronterEntry>[];
  for (final session in activeSessions) {
    final memberId = session.memberId;
    if (memberId == null) continue;
    final member = membersById[memberId];
    if (member == null) continue;
    entries.add(_FronterEntry(member: member, startTime: session.startTime));
  }

  entries.sort((a, b) {
    final startCmp = b.startTime.compareTo(a.startTime);
    if (startCmp != 0) return startCmp;
    final orderCmp = a.member.displayOrder.compareTo(b.member.displayOrder);
    if (orderCmp != 0) return orderCmp;
    return a.member.id.compareTo(b.member.id);
  });

  return [for (final e in entries) e.member];
}

class _FronterEntry {
  const _FronterEntry({required this.member, required this.startTime});
  final Member member;
  final DateTime startTime;
}
