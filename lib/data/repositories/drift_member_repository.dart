import 'dart:convert';
import 'dart:typed_data';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

class DriftMemberRepository with SyncRecordMixin implements MemberRepository {
  final MembersDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;
  // Plan 02 R1: optional — when wired, `deleteMember` stamps the current PK
  // link epoch onto the tombstone so push-time can gate stale intents.
  final PluralKitSyncDao? _pkSyncDao;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'members';

  DriftMemberRepository(this._dao, this._syncHandle, {PluralKitSyncDao? pkSyncDao})
      : _pkSyncDao = pkSyncDao;

  @override
  Future<List<domain.Member>> getAllMembers() async {
    final rows = await _dao.getAllMembers();
    return rows.map(MemberMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.Member>> watchAllMembers() {
    return _dao.watchAllMembers().map(
      (rows) => rows.map(MemberMapper.toDomain).toList(),
    );
  }

  @override
  Stream<List<domain.Member>> watchActiveMembers() {
    return _dao.watchActiveMembers().map(
      (rows) => rows.map(MemberMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.Member?> getMemberById(String id) async {
    final row = await _dao.getMemberById(id);
    return row != null ? MemberMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.Member?> watchMemberById(String id) {
    return _dao
        .watchMemberById(id)
        .map((row) => row != null ? MemberMapper.toDomain(row) : null);
  }

  @override
  Future<void> createMember(domain.Member member) async {
    final normalizedMember = _normalizeMember(member);
    final companion = MemberMapper.toCompanion(normalizedMember);
    await _dao.insertMember(companion);
    await syncRecordCreate(_table, normalizedMember.id, _memberFields(normalizedMember));
  }

  @override
  Future<void> updateMember(domain.Member member) async {
    final normalizedMember = _normalizeMember(member);
    final companion = MemberMapper.toCompanion(normalizedMember);
    await _dao.updateMember(companion);
    await syncRecordUpdate(_table, normalizedMember.id, _memberFields(normalizedMember));
  }

  @override
  Future<void> deleteMember(String id) async {
    // Plan 02 R1: if this member has a PK link and a sync DAO is wired,
    // stamp the current link epoch on the tombstone in the same transaction
    // so the PK push path can distinguish "tombstoned under this link" from
    // "tombstoned under a prior link / while disconnected." Members without
    // a PK link skip the stamp — there's nothing to push anyway.
    int? epoch;
    final pkDao = _pkSyncDao;
    final existing = await _dao.getMemberById(id);
    final isLinked = existing != null &&
        ((existing.pluralkitId != null && existing.pluralkitId!.isNotEmpty) ||
            (existing.pluralkitUuid != null &&
                existing.pluralkitUuid!.isNotEmpty));
    if (pkDao != null && isLinked) {
      epoch = await pkDao.getLinkEpoch();
    }

    await _dao.softDeleteMember(id);
    if (epoch != null) {
      await _dao.stampDeleteIntent(id, epoch);
    }
    await syncRecordDelete(_table, id);
  }

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async {
    final rows = await _dao.getDeletedLinkedMembers();
    return rows.map(MemberMapper.toDomain).toList();
  }

  @override
  Future<void> clearPluralKitLink(String id) async {
    await _dao.clearPluralKitLinkRaw(id);
    // Plan 02 R3: emit a CRDT op so peers converge. We deliberately send
    // only the changed fields (no full re-write) — recordUpdate is the
    // right channel; recordDelete has already been emitted for the
    // tombstone.
    await syncRecordUpdate(_table, id, {
      'pluralkit_id': null,
      'pluralkit_uuid': null,
    });
  }

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {
    await _dao.stampDeletePushStartedAt(id, timestampMs);
    await syncRecordUpdate(_table, id, {
      'delete_push_started_at': timestampMs,
    });
  }

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async {
    final rows = await _dao.getMembersByIds(ids);
    return rows.map(MemberMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) {
    return _dao
        .watchMembersByIds(ids)
        .map((rows) => rows.map(MemberMapper.toDomain).toList());
  }

  @override
  Future<int> getCount() => _dao.getCount();

  @override
  Future<({domain.Member member, bool wasCreated})>
      ensureUnknownSentinelMember() async {
    final existing = await getMemberById(unknownSentinelMemberId);
    if (existing != null) {
      return (member: existing, wasCreated: false);
    }
    final sentinel = domain.Member(
      id: unknownSentinelMemberId,
      name: 'Unknown',
      emoji: '❔',
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    );
    await createMember(sentinel);
    return (member: sentinel, wasCreated: true);
  }

  domain.Member _normalizeMember(domain.Member member) {
    final normalizedAvatar = AvatarNormalizer.normalize(member.avatarImageData);
    if (normalizedAvatar == member.avatarImageData) {
      return member;
    }
    return member.copyWith(avatarImageData: normalizedAvatar);
  }

  Map<String, dynamic> _memberFields(domain.Member m) {
    final Uint8List? avatar = m.avatarImageData;
    return {
      'name': m.name,
      'pronouns': m.pronouns,
      'emoji': m.emoji,
      'age': m.age,
      'bio': m.bio,
      'avatar_image_data': avatar != null ? base64Encode(avatar) : null,
      'is_active': m.isActive,
      'created_at': m.createdAt.toIso8601String(),
      'display_order': m.displayOrder,
      'is_admin': m.isAdmin,
      'custom_color_enabled': m.customColorEnabled,
      'custom_color_hex': m.customColorHex,
      'parent_system_id': m.parentSystemId,
      'pluralkit_uuid': m.pluralkitUuid,
      'pluralkit_id': m.pluralkitId,
      'markdown_enabled': m.markdownEnabled,
      'is_deleted': false,
    };
  }
}
