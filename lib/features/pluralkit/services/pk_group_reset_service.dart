import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';

class PkGroupResetResult {
  const PkGroupResetResult({
    this.groupsReset = 0,
    this.promotedChildGroups = 0,
    this.deferredOpsCleared = 0,
  });

  final int groupsReset;
  final int promotedChildGroups;
  final int deferredOpsCleared;

  bool get changedAnything =>
      groupsReset > 0 || promotedChildGroups > 0 || deferredOpsCleared > 0;
}

class PkGroupResetService {
  PkGroupResetService({
    required AppDatabase db,
    required MemberGroupsRepository memberGroupsRepository,
  }) : _db = db,
       _memberGroupsRepository = memberGroupsRepository;

  final AppDatabase _db;
  final MemberGroupsRepository _memberGroupsRepository;

  Future<PkGroupResetResult> resetPkGroupsOnly() async {
    final activeGroups = await _db.memberGroupsDao.getAllActiveGroups();
    final targetIds = activeGroups
        .where(_shouldResetGroup)
        .map((group) => group.id)
        .toSet();

    final promotedChildren =
        activeGroups
            .where(
              (group) =>
                  group.parentGroupId != null &&
                  targetIds.contains(group.parentGroupId) &&
                  !targetIds.contains(group.id),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final createdCompare = left.createdAt.compareTo(right.createdAt);
            if (createdCompare != 0) return createdCompare;
            return left.id.compareTo(right.id);
          });

    for (final child in promotedChildren) {
      final updated = MemberGroupMapper.toDomain(
        child,
      ).copyWith(parentGroupId: null);
      await _memberGroupsRepository.updateGroup(updated);
    }

    final groupById = {for (final group in activeGroups) group.id: group};
    final resetGroups =
        targetIds
            .map((id) => groupById[id])
            .whereType<MemberGroupRow>()
            .toList(growable: false)
          ..sort((left, right) {
            final depthCompare = _groupDepth(
              groupById,
              right,
            ).compareTo(_groupDepth(groupById, left));
            if (depthCompare != 0) return depthCompare;
            final createdCompare = right.createdAt.compareTo(left.createdAt);
            if (createdCompare != 0) return createdCompare;
            return right.id.compareTo(left.id);
          });

    for (final group in resetGroups) {
      if (group.syncSuppressed || group.suspectedPkGroupUuid != null) {
        await _db.memberGroupsDao.dismissGroupsFromPkReview([group.id]);
      }
      await _memberGroupsRepository.deleteGroup(group.id);
    }

    final deferredOps = await _db.pkGroupEntryDeferredSyncOpsDao.getAll();
    if (deferredOps.isNotEmpty) {
      await _db.pkGroupEntryDeferredSyncOpsDao.clearAll();
    }

    return PkGroupResetResult(
      groupsReset: resetGroups.length,
      promotedChildGroups: promotedChildren.length,
      deferredOpsCleared: deferredOps.length,
    );
  }

  static bool _shouldResetGroup(MemberGroupRow group) {
    final pkGroupUuid = (group.pluralkitUuid ?? '').trim();
    final suspectedPkGroupUuid = (group.suspectedPkGroupUuid ?? '').trim();
    return pkGroupUuid.isNotEmpty ||
        group.syncSuppressed ||
        suspectedPkGroupUuid.isNotEmpty;
  }

  static int _groupDepth(
    Map<String, MemberGroupRow> groupById,
    MemberGroupRow group,
  ) {
    var depth = 0;
    final seen = <String>{group.id};
    var current = group;

    while (true) {
      final parentId = current.parentGroupId;
      if (parentId == null || !seen.add(parentId)) break;
      final parent = groupById[parentId];
      if (parent == null) break;
      depth += 1;
      current = parent;
    }

    return depth;
  }
}
