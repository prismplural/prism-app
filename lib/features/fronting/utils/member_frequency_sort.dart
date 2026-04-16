import 'package:prism_plurality/domain/models/models.dart';

/// Sorts members by fronting frequency (descending), with optional pinning.
///
/// Used by QuickFrontSection (pins current fronter) and the wake-up sheet
/// (no pinning, morning-weighted counts).
List<Member> sortMembersByFrequency(
  List<Member> members,
  Map<String, int> counts, {
  String? pinnedMemberId,
  int take = 4,
}) {
  final sorted = [...members]..sort((a, b) {
    if (pinnedMemberId != null) {
      if (a.id == pinnedMemberId) return -1;
      if (b.id == pinnedMemberId) return 1;
    }
    final countDiff = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
    if (countDiff != 0) return countDiff;
    final orderDiff = a.displayOrder.compareTo(b.displayOrder);
    if (orderDiff != 0) return orderDiff;
    return a.id.compareTo(b.id);
  });
  return sorted.take(take).toList();
}
