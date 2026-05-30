import 'package:prism_plurality/domain/models/member.dart';

/// Members split into currently fronting and everyone else, preserving input
/// order. Lets the picker surfaces float current fronters to the top.
class PickerMemberSections {
  const PickerMemberSections({required this.fronters, required this.others});

  /// Members currently fronting, in their input (display) order.
  final List<Member> fronters;

  /// Everyone else, in their input (display) order.
  final List<Member> others;

  /// True when a boundary is meaningful: at least one fronter and one
  /// non-fronter. When everyone (or nobody) is fronting, it's one flat group.
  bool get hasFronterSection => fronters.isNotEmpty && others.isNotEmpty;
}

/// Partitions [members] into current fronters (ids in [fronterIds]) and
/// everyone else, preserving each member's order within its group. Ids absent
/// from [members] are ignored; empty [fronterIds] returns [members] as `others`.
PickerMemberSections partitionMembersForPicker(
  List<Member> members,
  Set<String> fronterIds,
) {
  if (fronterIds.isEmpty) {
    return PickerMemberSections(fronters: const [], others: members);
  }
  final fronters = <Member>[];
  final others = <Member>[];
  for (final member in members) {
    if (fronterIds.contains(member.id)) {
      fronters.add(member);
    } else {
      others.add(member);
    }
  }
  return PickerMemberSections(fronters: fronters, others: others);
}

/// Flattened fronters-first ordering. Returns [members] unchanged when there
/// are no current fronters.
List<Member> orderMembersForPicker(
  List<Member> members,
  Set<String> fronterIds,
) {
  final sections = partitionMembersForPicker(members, fronterIds);
  if (sections.fronters.isEmpty) return members;
  return [...sections.fronters, ...sections.others];
}
