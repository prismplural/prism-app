import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

/// Watches all non-deleted groups ordered by displayOrder.
final allGroupsProvider = StreamProvider<List<MemberGroup>>((ref) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchAllGroups();
});

/// Watches member counts for all groups in a single query.
/// Returns `Map<groupId, memberCount>`.
final groupMemberCountsProvider = StreamProvider<Map<String, int>>((ref) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchMemberCountsByGroup();
});

/// Watches groups that a specific member belongs to.
final memberGroupsProvider =
    StreamProvider.autoDispose.family<List<MemberGroup>, String>((ref, memberId) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchGroupsForMember(memberId);
});

/// Watches entries (group–member links) for a specific group.
final groupEntriesProvider =
    StreamProvider.autoDispose.family<List<MemberGroupEntry>, String>((ref, groupId) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchGroupEntries(groupId);
});

/// Watches a single group by ID.
final groupByIdProvider =
    StreamProvider.autoDispose.family<MemberGroup?, String>((ref, id) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchGroupById(id);
});

/// Notifier for group CRUD and membership mutations.
class GroupNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createGroup(MemberGroup group) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.createGroup(group);
    });
  }

  Future<void> updateGroup(MemberGroup group) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.updateGroup(group);
    });
  }

  Future<void> reorderGroups(List<MemberGroup> groups) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      for (int i = 0; i < groups.length; i++) {
        if (groups[i].displayOrder != i) {
          await repo.updateGroup(groups[i].copyWith(displayOrder: i));
        }
      }
    });
  }

  Future<void> deleteGroup(String groupId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.deleteGroup(groupId);
    });
  }

  Future<void> addMemberToGroup(String groupId, String memberId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      final entryId = _uuid.v4();
      await repo.addMemberToGroup(groupId, memberId, entryId);
    });
  }

  Future<void> removeMemberFromGroup(
      String groupId, String memberId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.removeMemberFromGroup(groupId, memberId);
    });
  }
}

final groupNotifierProvider =
    AsyncNotifierProvider<GroupNotifier, void>(GroupNotifier.new);

/// Watches all non-deleted group entries across every group.
final allGroupEntriesProvider = StreamProvider<List<MemberGroupEntry>>((ref) {
  return ref.watch(memberGroupsRepositoryProvider).watchAllGroupEntries();
});

/// Notifier for the active group filter selection.
/// null = show all, '__ungrouped__' = ungrouped members, any other value = group ID.
class ActiveGroupFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? filter) => state = filter;
}

final activeGroupFilterProvider =
    NotifierProvider.autoDispose<ActiveGroupFilterNotifier, String?>(
        ActiveGroupFilterNotifier.new);

/// True when at least one active member has no group entry.
final ungroupedMembersExistProvider = Provider.autoDispose<bool>((ref) {
  final members = ref.watch(allMembersProvider).value ?? [];
  final entries = ref.watch(allGroupEntriesProvider).value ?? [];
  final groupedMemberIds = entries.map((e) => e.memberId).toSet();
  return members.any((m) => m.isActive && !groupedMemberIds.contains(m.id));
});
