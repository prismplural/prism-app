import 'package:prism_plurality/domain/models/models.dart';

/// Sorts members by fronting frequency (descending). Ties resolve by
/// [Member.displayOrder] ascending, then by id for full determinism.
///
/// Callers that want a currently-fronting group on top should filter those
/// members out of [members] first and concatenate their own ordered list in
/// front (see [QuickFrontSection]).
List<Member> sortMembersByFrequency(
  List<Member> members,
  Map<String, int> counts, {
  int take = 4,
}) {
  final sorted = [...members]..sort((a, b) {
    final countDiff = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
    if (countDiff != 0) return countDiff;
    final orderDiff = a.displayOrder.compareTo(b.displayOrder);
    if (orderDiff != 0) return orderDiff;
    return a.id.compareTo(b.id);
  });
  return sorted.take(take).toList();
}
