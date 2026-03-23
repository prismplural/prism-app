import 'dart:convert';
import 'dart:typed_data';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

class DriftMemberRepository with SyncRecordMixin implements MemberRepository {
  final MembersDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'members';

  DriftMemberRepository(this._dao, this._syncHandle);

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
    await _dao.softDeleteMember(id);
    await syncRecordDelete(_table, id);
  }

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async {
    final rows = await _dao.getMembersByIds(ids);
    return rows.map(MemberMapper.toDomain).toList();
  }

  @override
  Future<int> getCount() => _dao.getCount();

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
