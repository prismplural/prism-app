import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_group_entry_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';

class DriftMemberGroupsRepository
    with SyncRecordMixin
    implements MemberGroupsRepository {
  final MemberGroupsDao _dao;
  final MemberRepository _memberRepository;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _groupTable = 'member_groups';
  static const _entryTable = 'member_group_entries';

  DriftMemberGroupsRepository(
    this._dao,
    this._syncHandle, {
    MemberRepository? memberRepository,
  }) : _memberRepository = memberRepository ?? const _NoopMemberRepository();

  @override
  Stream<List<domain.MemberGroup>> watchAllGroups() {
    return _dao.watchAllGroups().map(
      (rows) => rows.map(MemberGroupMapper.toDomain).toList(),
    );
  }

  @override
  Stream<domain.MemberGroup?> watchGroupById(String id) {
    return _dao
        .watchGroupById(id)
        .map((row) => row != null ? MemberGroupMapper.toDomain(row) : null);
  }

  @override
  Stream<List<domain.MemberGroup>> watchGroupsForMember(String memberId) {
    return _dao
        .watchGroupsForMember(memberId)
        .map((rows) => rows.map(MemberGroupMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.MemberGroupEntry>> watchGroupEntries(String groupId) {
    return _dao
        .watchGroupEntries(groupId)
        .map((rows) => rows.map(MemberGroupEntryMapper.toDomain).toList());
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
    final stored = await _requireGroupRow(withOrder.id);
    await _syncGroupCreateIfAllowed(stored);
  }

  @override
  Future<void> updateGroup(domain.MemberGroup group) async {
    final companion = MemberGroupMapper.toCompanion(group);
    await _dao.updateGroup(group.id, companion);
    final stored = await _requireGroupRow(group.id);
    await _syncGroupUpdateIfAllowed(stored);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    // Fetch entries before the delete so we can emit ops for them.
    final entries = await _dao.entriesForGroup(groupId);
    final group = await _dao.getGroupById(groupId);
    final groupEntityId = _groupEntityId(group, fallbackId: groupId);
    final membersById = <String, member_domain.Member>{};
    for (final member in await _memberRepository.getMembersByIds(
      entries.map((entry) => entry.memberId).toSet().toList(),
    )) {
      membersById[member.id] = member;
    }
    final isSuppressed = await _dao.isGroupSyncSuppressed(groupId);
    await _dao.deleteGroup(groupId);
    if (isSuppressed) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    for (final entry in entries) {
      await syncRecordDelete(
        _entryTable,
        _entryEntityIdForDelete(
          group: group,
          entry: entry,
          member: membersById[entry.memberId],
        ),
      );
    }
    await syncRecordDelete(_groupTable, groupEntityId);
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  @override
  Future<void> promoteChildrenToRoot(String groupId) async {
    final group = await _dao.getGroupById(groupId);
    final groupEntityId = _groupEntityId(group, fallbackId: groupId);
    final children = await _dao.getDirectChildrenOf(groupId);
    final promotedModels = children.map((child) {
      return MemberGroupMapper.toDomain(child).copyWith(parentGroupId: null);
    }).toList();
    final entries = await _dao.entriesForGroup(groupId);
    final membersById = <String, member_domain.Member>{};
    for (final member in await _memberRepository.getMembersByIds(
      entries.map((entry) => entry.memberId).toSet().toList(),
    )) {
      membersById[member.id] = member;
    }
    final isDeletedGroupSuppressed = await _dao.isGroupSyncSuppressed(groupId);

    await _dao.transaction(() async {
      for (final promoted in promotedModels) {
        await _dao.updateGroup(
          promoted.id,
          MemberGroupMapper.toCompanion(promoted),
        );
      }
      await _dao.deleteGroup(groupId);
    });

    for (final promoted in promotedModels) {
      final stored = await _requireGroupRow(promoted.id);
      await _syncGroupUpdateIfAllowed(stored);
    }
    if (isDeletedGroupSuppressed) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    for (final entry in entries) {
      await syncRecordDelete(
        _entryTable,
        _entryEntityIdForDelete(
          group: group,
          entry: entry,
          member: membersById[entry.memberId],
        ),
      );
    }
    await syncRecordDelete(_groupTable, groupEntityId);
    await _syncLegacyPkGroupAliasDeletes(group);
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
      queue.addAll(
        (byParent[current] ?? []).where((id) => !toDelete.contains(id)),
      );
    }

    // Pre-fetch entries for sync ops before the transaction deletes them.
    final entriesByGroup = <String, List<domain.MemberGroupEntry>>{};
    final groupRowsById = <String, MemberGroupRow?>{};
    final suppressedByGroup = <String, bool>{};
    final membersById = <String, member_domain.Member>{};
    for (final id in toDelete) {
      entriesByGroup[id] = (await _dao.entriesForGroup(
        id,
      )).map(MemberGroupEntryMapper.toDomain).toList();
      groupRowsById[id] = await _dao.getGroupById(id);
      suppressedByGroup[id] = await _dao.isGroupSyncSuppressed(id);
    }
    final memberIds = entriesByGroup.values
        .expand((entries) => entries.map((entry) => entry.memberId))
        .toSet()
        .toList();
    for (final member in await _memberRepository.getMembersByIds(memberIds)) {
      membersById[member.id] = member;
    }

    await _dao.transaction(() async {
      for (final id in toDelete) {
        await _dao.deleteGroup(id);
      }
    });

    for (final id in toDelete) {
      if (suppressedByGroup[id] ?? false) continue;
      if (!await _shouldEmitPkBackedGroupSync(groupRowsById[id])) continue;
      for (final entry in entriesByGroup[id] ?? []) {
        await syncRecordDelete(
          _entryTable,
          _entryEntityIdForDelete(
            group: groupRowsById[id],
            entry: entry,
            member: membersById[entry.memberId],
          ),
        );
      }
      await syncRecordDelete(
        _groupTable,
        _groupEntityId(groupRowsById[id], fallbackId: id),
      );
      await _syncLegacyPkGroupAliasDeletes(groupRowsById[id]);
    }
  }

  @override
  Future<void> addMemberToGroup(
    String groupId,
    String memberId,
    String entryId,
  ) async {
    final existing = await _dao.findEntry(groupId, memberId);
    if (existing != null) return;
    final group = await _requireGroupRow(groupId);
    final member = await _memberRepository.getMemberById(memberId);
    final resolvedEntryId = _entryEntityId(
      group: group,
      member: member,
      fallbackId: entryId,
    );
    final companion = MemberGroupEntriesCompanion(
      id: Value(resolvedEntryId),
      groupId: Value(groupId),
      memberId: Value(memberId),
      pkGroupUuid: Value(group.pluralkitUuid),
      pkMemberUuid: Value(member?.pluralkitUuid),
      isDeleted: const Value(false),
    );
    if ((group.pluralkitUuid ?? '').isNotEmpty &&
        (member?.pluralkitUuid ?? '').isNotEmpty) {
      await _dao.upsertEntry(companion);
    } else {
      await _dao.createEntry(companion);
    }
    final stored = await _dao.findEntry(groupId, memberId);
    if (stored != null) {
      await _syncEntryCreateIfAllowed(stored, member: member);
    }
  }

  @override
  Future<void> removeMemberFromGroup(String groupId, String memberId) async {
    final entry = await _dao.findEntry(groupId, memberId);
    if (entry == null) return;
    final group = await _dao.getGroupById(groupId);
    if (group == null) return;
    final member = await _memberRepository.getMemberById(memberId);
    final entryEntityId = _entryEntityIdForDelete(
      group: group,
      entry: entry,
      member: member,
    );
    final isSuppressed = await _dao.isGroupSyncSuppressed(groupId);
    await _dao.deleteEntry(entry.id);
    if (isSuppressed) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordDelete(_entryTable, entryEntityId);
  }

  @override
  Future<void> emitGroupSyncState(String groupId) async {
    final group = await _dao.getGroupById(groupId);
    if (group == null) return;
    // Intentionally bypass `isGroupSyncSuppressed` — callers invoke this after
    // clearing review flags, and the goal is precisely to re-broadcast the
    // current state so accumulated local edits reach peers.
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordUpdate(
      _groupTable,
      _groupEntityId(group),
      _groupFields(group),
    );
    final entries = await _dao.entriesForGroup(groupId);
    final memberIds = entries.map((entry) => entry.memberId).toSet().toList();
    final membersById = <String, member_domain.Member>{};
    for (final member in await _memberRepository.getMembersByIds(memberIds)) {
      membersById[member.id] = member;
    }
    for (final entry in entries) {
      final member = membersById[entry.memberId];
      if (!_canEmitPkBackedEntry(entry, group: group, member: member)) {
        continue;
      }
      await syncRecordUpdate(
        _entryTable,
        _entryEntityIdFromStoredEntry(entry, group: group, member: member),
        _entryFields(entry, group: group, member: member),
      );
    }
  }

  Future<void> _syncGroupCreateIfAllowed(MemberGroupRow group) async {
    if (await _dao.isGroupSyncSuppressed(group.id)) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordCreate(
      _groupTable,
      _groupEntityId(group),
      _groupFields(group),
    );
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  Future<void> _syncGroupUpdateIfAllowed(MemberGroupRow group) async {
    if (await _dao.isGroupSyncSuppressed(group.id)) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordUpdate(
      _groupTable,
      _groupEntityId(group),
      _groupFields(group),
    );
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  Future<void> _syncEntryCreateIfAllowed(
    MemberGroupEntryRow entry, {
    member_domain.Member? member,
  }) async {
    if (await _dao.isGroupSyncSuppressed(entry.groupId)) return;
    final resolvedMember =
        member ?? await _memberRepository.getMemberById(entry.memberId);
    final group = await _requireGroupRow(entry.groupId);
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    if (!_canEmitPkBackedEntry(entry, group: group, member: resolvedMember)) {
      return;
    }
    await syncRecordCreate(
      _entryTable,
      _entryEntityIdFromStoredEntry(
        entry,
        group: group,
        member: resolvedMember,
      ),
      _entryFields(entry, group: group, member: resolvedMember),
    );
  }

  Future<bool> _shouldEmitPkBackedGroupSync(MemberGroupRow? group) async {
    final pkUuid = group?.pluralkitUuid;
    if (pkUuid == null || pkUuid.isEmpty) return true;
    final settings = await _dao.attachedDatabase.systemSettingsDao
        .getSettings();
    return settings.pkGroupSyncV2Enabled;
  }

  bool _canEmitPkBackedEntry(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) {
    final pkGroupUuid = (entry.pkGroupUuid ?? group.pluralkitUuid ?? '').trim();
    if (pkGroupUuid.isEmpty) return true;

    final pkMemberUuid = (entry.pkMemberUuid ?? member?.pluralkitUuid ?? '')
        .trim();
    return pkMemberUuid.isNotEmpty;
  }

  Future<void> _syncLegacyPkGroupAliasDeletes(MemberGroupRow? group) async {
    final pkGroupUuid = (group?.pluralkitUuid ?? '').trim();
    if (group == null || pkGroupUuid.isEmpty) return;
    final canonicalEntityId = _groupEntityId(group);
    final aliases = await _dao.attachedDatabase.pkGroupSyncAliasesDao
        .getByPkGroupUuid(pkGroupUuid);
    final legacyEntityIds = <String>{};
    for (final alias in aliases) {
      final legacyEntityId = alias.legacyEntityId.trim();
      if (legacyEntityId.isEmpty || legacyEntityId == canonicalEntityId) {
        continue;
      }
      legacyEntityIds.add(legacyEntityId);
    }
    for (final legacyEntityId in legacyEntityIds) {
      await syncRecordDelete(_groupTable, legacyEntityId);
    }
  }

  Future<MemberGroupRow> _requireGroupRow(String id) async {
    final row = await _dao.getGroupById(id);
    if (row == null) {
      throw StateError('Missing member group row $id');
    }
    return row;
  }

  String _groupEntityId(MemberGroupRow? group, {String? fallbackId}) {
    final pkUuid = group?.pluralkitUuid;
    if (pkUuid != null && pkUuid.isNotEmpty) {
      return 'pk-group:$pkUuid';
    }
    if (group != null) return group.id;
    if (fallbackId != null) return fallbackId;
    throw StateError('Missing member group identity');
  }

  String _entryEntityId({
    required MemberGroupRow group,
    required member_domain.Member? member,
    required String fallbackId,
  }) {
    return _entryEntityIdFromPkRefs(
      pkGroupUuid: group.pluralkitUuid,
      pkMemberUuid: member?.pluralkitUuid,
      fallbackId: fallbackId,
    );
  }

  String _entryEntityIdFromStoredEntry(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) {
    return _entryEntityIdFromPkRefs(
      pkGroupUuid: entry.pkGroupUuid ?? group.pluralkitUuid,
      pkMemberUuid: entry.pkMemberUuid ?? member?.pluralkitUuid,
      fallbackId: entry.id,
    );
  }

  String _entryEntityIdFromPkRefs({
    required String? pkGroupUuid,
    required String? pkMemberUuid,
    required String fallbackId,
  }) {
    final normalizedGroupPkUuid = (pkGroupUuid ?? '').trim();
    final normalizedMemberPkUuid = (pkMemberUuid ?? '').trim();
    if (normalizedGroupPkUuid.isEmpty || normalizedMemberPkUuid.isEmpty) {
      return fallbackId;
    }
    final digest = sha256.convert(
      utf8.encode('$normalizedGroupPkUuid\u0000$normalizedMemberPkUuid'),
    );
    return digest.toString().substring(0, 16);
  }

  String _entryEntityIdForDelete({
    required MemberGroupRow? group,
    required MemberGroupEntryRow entry,
    required member_domain.Member? member,
  }) {
    if (group == null) return entry.id;
    return _entryEntityIdFromStoredEntry(entry, group: group, member: member);
  }

  /// Visible-for-testing: builds the group field map this repository hands to
  /// the Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC.
  @visibleForTesting
  Map<String, dynamic> debugGroupFields(MemberGroupRow row) =>
      _groupFields(row);

  Map<String, dynamic> _groupFields(MemberGroupRow row) {
    return {
      'name': row.name,
      'description': row.description,
      'color_hex': row.colorHex,
      'emoji': row.emoji,
      'display_order': row.displayOrder,
      'parent_group_id': row.parentGroupId,
      'group_type': row.groupType,
      'filter_rules': row.filterRules,
      'created_at': toSyncUtc(row.createdAt),
      'pluralkit_id': row.pluralkitId,
      'pluralkit_uuid': row.pluralkitUuid,
      'last_seen_from_pk_at': toSyncUtcOrNull(row.lastSeenFromPkAt),
      'is_deleted': row.isDeleted,
    };
  }

  Map<String, dynamic> _entryFields(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) {
    final pkGroupUuid = entry.pkGroupUuid ?? group.pluralkitUuid;
    final pkMemberUuid = entry.pkMemberUuid ?? member?.pluralkitUuid;
    return {
      'group_id': entry.groupId,
      'member_id': entry.memberId,
      if ((pkGroupUuid ?? '').isNotEmpty) 'pk_group_uuid': pkGroupUuid,
      if ((pkMemberUuid ?? '').isNotEmpty) 'pk_member_uuid': pkMemberUuid,
      'is_deleted': entry.isDeleted,
    };
  }
}

class _NoopMemberRepository implements MemberRepository {
  const _NoopMemberRepository();

  @override
  Future<void> clearPluralKitLink(String id) async {}

  @override
  Future<void> createMember(member_domain.Member member) async {}

  @override
  Future<void> deleteMember(String id) async {}

  @override
  Future<List<member_domain.Member>> getAllMembers() async => const [];

  @override
  Future<int> getCount() async => 0;

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      const [];

  @override
  Future<member_domain.Member?> getMemberById(String id) async => null;

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      const [];

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> updateMember(member_domain.Member member) async {}

  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      const Stream.empty();

  @override
  Stream<List<member_domain.Member>> watchAllMembers() => const Stream.empty();

  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      const Stream.empty();

  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      const Stream.empty();

  @override
  Future<({member_domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnsupportedError(
    '_NoopMemberRepository does not support ensureUnknownSentinelMember',
  );
}
