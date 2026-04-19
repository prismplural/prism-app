import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_group_entry_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';

class DriftMemberGroupsRepository
    with SyncRecordMixin
    implements MemberGroupsRepository {
  final MemberGroupsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _groupTable = 'member_groups';
  static const _entryTable = 'member_group_entries';

  DriftMemberGroupsRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.MemberGroup>> watchAllGroups() {
    return _dao.watchAllGroups().map(
      (rows) => rows.map(MemberGroupMapper.toDomain).toList(),
    );
  }

  @override
  Stream<domain.MemberGroup?> watchGroupById(String id) {
    return _dao.watchGroupById(id).map(
        (row) => row != null ? MemberGroupMapper.toDomain(row) : null);
  }

  @override
  Stream<List<domain.MemberGroup>> watchGroupsForMember(String memberId) {
    return _dao.watchGroupsForMember(memberId).map(
      (rows) => rows.map(MemberGroupMapper.toDomain).toList(),
    );
  }

  @override
  Stream<List<domain.MemberGroupEntry>> watchGroupEntries(String groupId) {
    return _dao.watchGroupEntries(groupId).map(
      (rows) => rows.map(MemberGroupEntryMapper.toDomain).toList(),
    );
  }

  @override
  Stream<List<domain.MemberGroupEntry>> watchAllGroupEntries() {
    return _dao.watchAllGroupEntries().map(
      (rows) => rows.map(MemberGroupEntryMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.MemberGroupEntry>> getAllGroupEntries() async {
    final rows = await _dao.getAllGroupEntries();
    return rows.map(MemberGroupEntryMapper.toDomain).toList();
  }

  @override
  Stream<Map<String, int>> watchMemberCountsByGroup() {
    return _dao.watchMemberCountsByGroup();
  }

  @override
  Future<void> createGroup(domain.MemberGroup group) async {
    final displayOrder = await _dao.nextDisplayOrder(group.parentGroupId);
    final withOrder = group.copyWith(displayOrder: displayOrder);
    final companion = MemberGroupMapper.toCompanion(withOrder);
    await _dao.createGroup(companion);
    await syncRecordCreate(_groupTable, withOrder.id, _groupFields(withOrder));
  }

  @override
  Future<void> updateGroup(domain.MemberGroup group) async {
    final companion = MemberGroupMapper.toCompanion(group);
    await _dao.updateGroup(group.id, companion);
    await syncRecordUpdate(_groupTable, group.id, _groupFields(group));
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    // Fetch entries before the delete so we can emit ops for them.
    final entries = await _dao.watchGroupEntries(groupId).first;
    await _dao.deleteGroup(groupId);
    for (final entry in entries) {
      await syncRecordDelete(_entryTable, entry.id);
    }
    await syncRecordDelete(_groupTable, groupId);
  }

  @override
  Future<void> promoteChildrenToRoot(String groupId) async {
    final children = await _dao.getDirectChildrenOf(groupId);
    for (final child in children) {
      final domain = MemberGroupMapper.toDomain(child);
      final promoted = domain.copyWith(parentGroupId: null);
      await _dao.updateGroup(child.id, MemberGroupMapper.toCompanion(promoted));
      await syncRecordUpdate(_groupTable, child.id, _groupFields(promoted));
    }
    await deleteGroup(groupId);
  }

  @override
  Future<void> deleteGroupWithDescendants(String groupId) async {
    // BFS to collect all descendant IDs (max 3 levels, so at most ~100 groups).
    final allGroups = await _dao.getAllActiveGroups();
    final byParent = <String, List<String>>{};
    for (final g in allGroups) {
      if (g.parentGroupId != null) {
        byParent.putIfAbsent(g.parentGroupId!, () => []).add(g.id);
      }
    }
    final toDelete = <String>{};
    final queue = [groupId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      toDelete.add(current);
      queue.addAll(byParent[current] ?? []);
    }
    for (final id in toDelete) {
      await deleteGroup(id);
    }
  }

  @override
  Future<void> addMemberToGroup(
      String groupId, String memberId, String entryId) async {
    final existing = await _dao.findEntry(groupId, memberId);
    if (existing != null) return;
    final entry = domain.MemberGroupEntry(
      id: entryId,
      groupId: groupId,
      memberId: memberId,
    );
    final companion = MemberGroupEntryMapper.toCompanion(entry);
    await _dao.createEntry(companion);
    await syncRecordCreate(_entryTable, entry.id, _entryFields(entry));
  }

  @override
  Future<void> removeMemberFromGroup(
      String groupId, String memberId) async {
    final entry = await _dao.findEntry(groupId, memberId);
    if (entry == null) return;
    await _dao.deleteEntry(entry.id);
    await syncRecordDelete(_entryTable, entry.id);
  }

  Map<String, dynamic> _groupFields(domain.MemberGroup g) {
    return {
      'name': g.name,
      'description': g.description,
      'color_hex': g.colorHex,
      'emoji': g.emoji,
      'display_order': g.displayOrder,
      'parent_group_id': g.parentGroupId,
      'group_type': g.groupType,
      'filter_rules': g.filterRules,
      'created_at': g.createdAt.toIso8601String(),
      'is_deleted': false,
    };
  }

  Map<String, dynamic> _entryFields(domain.MemberGroupEntry e) {
    return {
      'group_id': e.groupId,
      'member_id': e.memberId,
      'is_deleted': false,
    };
  }
}
