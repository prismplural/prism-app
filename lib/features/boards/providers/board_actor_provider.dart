import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

/// Explicit board identity, independent of the chat speaker and viewed profile.
/// Selection is session-local; opening a board never chooses an actor.
final boardActorProvider = NotifierProvider<BoardActorNotifier, String?>(
  BoardActorNotifier.new,
);

class BoardActorNotifier extends Notifier<String?> {
  String? _selectedId;

  @override
  String? build() {
    final members = ref.watch(activeMemberListProvider).asData?.value;
    if (members == null) return null;
    final selected = members
        .where((member) => member.id == _selectedId)
        .firstOrNull;
    if (selected == null ||
        !selected.isActive ||
        selected.isDeleted ||
        selected.id == unknownSentinelMemberId) {
      _selectedId = null;
    }
    return _selectedId;
  }

  void setMember(String? memberId) {
    final members =
        ref.read(activeMemberListProvider).asData?.value ?? const <Member>[];
    final selected = members
        .where((member) => member.id == memberId)
        .firstOrNull;
    _selectedId =
        selected != null &&
            selected.isActive &&
            !selected.isDeleted &&
            selected.id != unknownSentinelMemberId
        ? selected.id
        : null;
    ref.invalidateSelf();
  }
}

/// Resolve the current actor through the live member record, so deletion or
/// archival revokes permissions even while a board surface is open.
final boardActorMemberProvider = Provider<Member?>((ref) {
  final id = ref.watch(boardActorProvider);
  if (id == null) return null;
  final member = ref.watch(activeMemberByIdProvider(id)).asData?.value;
  return member != null && member.isActive && !member.isDeleted ? member : null;
});
