import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/data/mappers/conversation_mapper.dart';
import 'package:prism_plurality/core/database/sqlite_constraint.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_profile_preference_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/conversation.dart'
    as conversation_domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

class DriftMemberRepository with SyncRecordMixin implements MemberRepository {
  final MembersDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;
  // Plan 02 R1: optional — when wired, `deleteMember` stamps the current PK
  // link epoch onto the tombstone so push-time can gate stale intents.
  final PluralKitSyncDao? _pkSyncDao;
  final ConversationsDao? _conversationsDao;
  final MemberGroupsDao? _memberGroupsDao;
  final PreferenceValuesDao? _preferenceValuesDao;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'members';

  DriftMemberRepository(
    this._dao,
    this._syncHandle, {
    PluralKitSyncDao? pkSyncDao,
    ConversationsDao? conversationsDao,
    MemberGroupsDao? memberGroupsDao,
    PreferenceValuesDao? preferenceValuesDao,
  }) : _pkSyncDao = pkSyncDao,
       _conversationsDao = conversationsDao,
       _memberGroupsDao = memberGroupsDao,
       _preferenceValuesDao = preferenceValuesDao;

  @override
  Future<List<domain.Member>> getAllMembers() async {
    final rows = await _dao.getAllMembers();
    return rows.map(MemberMapper.toDomain).toList();
  }

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async {
    final rows = await _dao.getAllMembersIncludingDeleted();
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
    await syncRecordCreate(
      _table,
      normalizedMember.id,
      _memberFields(normalizedMember),
    );
  }

  @override
  Future<void> updateMember(domain.Member member) async {
    final normalizedMember = _normalizeMember(member);
    final patch = _memberFields(normalizedMember);
    await _updateMemberFieldsWithIntent(
      normalizedMember.id,
      patch,
      allowPluralKitLinkMutation: false,
      allowResumeSyncIgnored: false,
    );
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) => _updateMemberFieldsWithIntent(
    id,
    changedFields,
    allowPluralKitLinkMutation: false,
    allowResumeSyncIgnored: false,
  );

  @override
  Future<int> applyPluralKitLink(
    String memberId,
    Map<String, dynamic> patch,
  ) async {
    // Runtime validation (not `assert`) so release builds enforce the
    // contract — these methods are part of a security boundary the
    // call-site guards depend on; a buggy caller silently bypassing
    // intent in production would corrupt the invariant.
    if (!patch.containsKey('pluralkit_uuid') &&
        !patch.containsKey('pluralkit_id')) {
      throw ArgumentError(
        'applyPluralKitLink requires pluralkit_uuid or pluralkit_id',
      );
    }
    // pluralkit_sync_ignored MAY be present if and only if the value
    // is false (idempotent with the method's force-injection below).
    // This allows callers that build their patch via
    // `member.copyWith(pluralkit_sync_ignored: false, ...)` diffed
    // against the DB row to pass through without per-site narrow-patch
    // construction. Rejects `true` because that would contradict the
    // method's "link AND resume sync" semantic.
    if (patch.containsKey('pluralkit_sync_ignored') &&
        patch['pluralkit_sync_ignored'] != false) {
      throw ArgumentError(
        'applyPluralKitLink: pluralkit_sync_ignored must be false or absent',
      );
    }
    _validatePkPatchAllowlist(patch);
    final mergedPatch = {...patch, 'pluralkit_sync_ignored': false};
    return _updateMemberFieldsWithIntent(
      memberId,
      mergedPatch,
      allowPluralKitLinkMutation: true,
      allowResumeSyncIgnored: true,
    );
  }

  @override
  Future<int> recordPluralKitIdentity(
    String memberId,
    Map<String, dynamic> patch,
  ) async {
    // Runtime validation (not `assert`) for the same reason as
    // applyPluralKitLink above.
    if (!patch.containsKey('pluralkit_uuid') &&
        !patch.containsKey('pluralkit_id')) {
      throw ArgumentError(
        'recordPluralKitIdentity requires pluralkit_uuid or pluralkit_id',
      );
    }
    if (patch.containsKey('pluralkit_sync_ignored')) {
      throw ArgumentError(
        'recordPluralKitIdentity does not change sync state — '
        'pluralkit_sync_ignored must be absent from the patch',
      );
    }
    _validatePkPatchAllowlist(patch);
    return _updateMemberFieldsWithIntent(
      memberId,
      patch,
      allowPluralKitLinkMutation: true,
      allowResumeSyncIgnored: false,
    );
  }

  @override
  Future<int> excludePluralKitSync(String memberId) =>
      _updateMemberFieldsWithIntent(
        memberId,
        {'pluralkit_sync_ignored': true},
        allowPluralKitLinkMutation: false,
        allowResumeSyncIgnored: false,
      );

  @override
  Future<int> resumePluralKitSync(String memberId) =>
      _updateMemberFieldsWithIntent(
        memberId,
        {'pluralkit_sync_ignored': false},
        allowPluralKitLinkMutation: false,
        allowResumeSyncIgnored: true,
      );

  Future<int> _updateMemberFieldsWithIntent(
    String id,
    Map<String, dynamic> changedFields, {
    required bool allowPluralKitLinkMutation,
    required bool allowResumeSyncIgnored,
  }) async {
    final existingRow = await _dao.getMemberByIdRow(id);
    if (existingRow == null || existingRow.isDeleted) return 0;

    final patch = diffSyncFields(
      _memberFieldsFromRow(existingRow),
      _knownMemberFields(changedFields),
    );

    if (existingRow.pluralkitSyncIgnored && !allowPluralKitLinkMutation) {
      _stripPkLinkFields(patch, id);
    }
    if (existingRow.pluralkitSyncIgnored && !allowResumeSyncIgnored) {
      _stripResumeSyncIgnored(patch, id);
    }

    if (patch.isEmpty) return 1; // no-op success
    final companion = _partialMemberCompanion(patch);
    final affected = await _dao.updateMemberById(id, companion);
    if (affected != 1) return affected;
    await syncRecordUpdate(_table, id, patch);
    return affected;
  }

  void _stripPkLinkFields(Map<String, dynamic> patch, String id) {
    final stripped = <String>[];
    // Rule A: on excluded rows, generic updateMember cannot mutate PK
    // identity or banner fields — including null clears. A stale
    // full-domain updateMember(stale.copyWith(...)) where `stale`
    // predates the link would otherwise wipe the link the exclude is
    // supposed to preserve. The PkStaleLinkException clear at
    // pk_bidirectional_service.dart:115 is upstream-guarded by the
    // per-local sync_ignored skip, so it doesn't reach here on
    // excluded rows.
    //
    // pluralkit_display_name is intentionally NOT stripped: the
    // add/edit member sheet exposes it for user editing on excluded
    // members.
    for (final key in const [
      'pluralkit_uuid',
      'pluralkit_id',
      'pk_avatar_cached_url',
      'pk_banner_url',
      'pk_banner_image_data',
      'pk_banner_cached_url',
    ]) {
      if (patch.containsKey(key)) {
        patch.remove(key);
        stripped.add(key);
      }
    }
    // profile_header_source: strip ONLY when patch sets it to
    // pluralKit. Other sources (prism, custom upload) are user-driven
    // and pass through.
    const headerSourceKey = 'profile_header_source';
    if (patch[headerSourceKey] ==
        domain.MemberProfileHeaderSource.pluralKit.index) {
      patch.remove(headerSourceKey);
      stripped.add(headerSourceKey);
    }
    if (stripped.isNotEmpty) {
      debugPrint(
        '[PK_REPO] stripped PK writes on excluded member $id: $stripped',
      );
    }
  }

  void _stripResumeSyncIgnored(Map<String, dynamic> patch, String id) {
    // Rule B: on excluded rows, generic updateMember cannot transition
    // sync_ignored from true to false. Closes the stale-full-domain
    // write race where a sync loop's stale Member object carries the
    // pre-exclude sync_ignored=false and would silently reactivate
    // via diff. `== false` not `containsKey` because true is always a
    // no-op against an already-excluded row.
    if (patch['pluralkit_sync_ignored'] == false) {
      patch.remove('pluralkit_sync_ignored');
      debugPrint(
        '[PK_REPO] stripped sync_ignored resume on excluded member $id',
      );
    }
  }

  // PK-link methods accept the full member-patch allowlist because
  // `_applyLink` and `_importMembers` intentionally pull PK-side
  // conditional metadata (pronouns, bio, banner) in the same atomic
  // write as identity. The method names signal intent; misuse is
  // caught at review.
  void _validatePkPatchAllowlist(Map<String, dynamic> patch) {
    for (final key in patch.keys) {
      if (!_memberPatchKeys.contains(key)) {
        throw ArgumentError('Unknown member patch key: $key');
      }
    }
  }

  /// Apply freshly-fetched avatar bytes to many members in one Drift batch
  /// and emit one `syncRecordUpdate` per member.
  ///
  /// Replaces the per-member `updateMember(...)` loop the SP importer used
  /// during the avatar phase. The DAO write fuses into a single batch
  /// statement; per-member emission is preserved so the wire-level event
  /// shape (one `record_update` per successful avatar) is unchanged.
  ///
  /// Normalization is applied per member (same as `updateMember`) so a
  /// caller passing raw HTTP bytes gets identical on-disk + on-wire bytes
  /// to today.
  ///
  /// Members whose `avatarImageData` is null after normalization are
  /// silently skipped — they have nothing to write.
  Future<void> batchUpdateAvatars(List<domain.Member> membersWithBytes) async {
    if (membersWithBytes.isEmpty) return;

    // The DAO writes ONLY `avatar_image_data` for each row (see
    // `MembersDao.batchUpdateAvatars`). Emit a one-field patch per member
    // to match what the DAO actually persists. Going through the full
    // `_memberFields` diff would surface any stale non-avatar field from
    // the supplied domain object (timezone offset, display order, anything
    // bumped on another device between the caller's read and this write)
    // and emit it as a phantom edit — local DB stays correct, but peers
    // would clobber on those stale columns.
    final bytesById = <String, Uint8List>{};
    final normalizedIds = <String>[];
    for (final member in membersWithBytes) {
      final n = _normalizeMember(member);
      final bytes = n.avatarImageData;
      if (bytes == null) continue;

      final existingRow = await _dao.getMemberByIdRow(n.id);
      if (existingRow == null || existingRow.isDeleted) continue;

      // Skip rows where the stored avatar already matches — no local write,
      // no sync emission.
      final encoded = base64Encode(bytes);
      if (existingRow.avatarImageData != null &&
          base64Encode(existingRow.avatarImageData!) == encoded) {
        continue;
      }

      bytesById[n.id] = bytes;
      normalizedIds.add(n.id);
    }
    if (bytesById.isEmpty) return;

    await _dao.batchUpdateAvatars(bytesById);
    for (final id in normalizedIds) {
      await syncRecordUpdate(_table, id, {
        'avatar_image_data': base64Encode(bytesById[id]!),
      });
    }
  }

  /// Reorder members with one database write, then emit the corresponding
  /// sync updates for the rows whose `displayOrder` changed.
  Future<void> reorderMembers(List<domain.Member> members) async {
    final changedMembers = <domain.Member>[];
    final displayOrders = <String, int>{};

    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      if (member.displayOrder == i) continue;
      final updated = member.copyWith(displayOrder: i);
      changedMembers.add(updated);
      displayOrders[updated.id] = i;
    }

    if (changedMembers.isEmpty) return;

    await _dao.bulkUpdateDisplayOrders(displayOrders);
    for (final member in changedMembers) {
      await syncRecordUpdate(_table, member.id, {
        'display_order': member.displayOrder,
      });
    }
  }

  @override
  Future<void> deleteMember(String id) async {
    // Refuse to delete the Unknown sentinel — it backs orphan-classified
    // fronting rows ("Front as Unknown" + importer/migration fallbacks). If
    // a user could delete it, those rows would render as broken-looking
    // until ensureUnknownSentinelMember auto-recreates on next use. The
    // member-list UI already filters this id out via userVisibleMembersProvider,
    // but the repository guard is the durable invariant — covers any path
    // (test, debug, future UI) that reaches deleteMember directly.
    if (id == unknownSentinelMemberId) {
      throw StateError('Unknown sentinel cannot be deleted');
    }

    // Plan 02 R1: if this member has a PK link and a sync DAO is wired,
    // stamp the current link epoch on the tombstone in the same transaction
    // so the PK push path can distinguish "tombstoned under this link" from
    // "tombstoned under a prior link / while disconnected." Members without
    // a PK link skip the stamp — there's nothing to push anyway.
    int? epoch;
    final pkDao = _pkSyncDao;
    final existing = await _dao.getMemberById(id);
    final isLinked =
        existing != null &&
        ((existing.pluralkitId != null && existing.pluralkitId!.isNotEmpty) ||
            (existing.pluralkitUuid != null &&
                existing.pluralkitUuid!.isNotEmpty));
    if (pkDao != null && isLinked) {
      epoch = await pkDao.getLinkEpoch();
    }

    await _removeDeletedMemberFromGroups(id);
    await _dao.softDeleteMember(id);
    if (epoch != null) {
      await _dao.stampDeleteIntent(id, epoch);
    }
    await _resetDeletedMemberProfilePreferences(id);
    await _removeDeletedMemberFromConversations(id);
    await syncRecordDelete(_table, id);
  }

  Future<void> _resetDeletedMemberProfilePreferences(String memberId) async {
    final preferenceValuesDao = _preferenceValuesDao;
    if (preferenceValuesDao == null) return;

    final preferenceRepo = DriftMemberProfilePreferenceRepository(
      preferenceValuesDao,
      _syncHandle,
    );
    await preferenceRepo.resetAllForMember(memberId);
  }

  Future<void> _removeDeletedMemberFromGroups(String memberId) async {
    final groupsDao = _memberGroupsDao;
    if (groupsDao == null) return;

    final entries = await groupsDao.activeEntriesForMember(memberId);
    if (entries.isEmpty) return;

    final groupRepo = DriftMemberGroupsRepository(
      groupsDao,
      _syncHandle,
      memberRepository: this,
    );
    for (final entry in entries) {
      await groupRepo.removeMemberFromGroup(entry.groupId, memberId);
    }
  }

  Future<void> _removeDeletedMemberFromConversations(String memberId) async {
    final conversationsDao = _conversationsDao;
    if (conversationsDao == null) return;

    final conversationRepo = DriftConversationRepository(
      conversationsDao,
      _syncHandle,
    );
    final rows = await conversationsDao.getAllConversations();
    for (final row in rows) {
      final conversation = ConversationMapper.toDomain(row);
      final updated = _withoutDeletedMember(conversation, memberId);
      if (updated == conversation) continue;
      await conversationRepo.updateConversation(updated);
    }
  }

  conversation_domain.Conversation _withoutDeletedMember(
    conversation_domain.Conversation conversation,
    String memberId,
  ) {
    final participantIds = conversation.participantIds
        .where((id) => id != memberId)
        .toList();
    final archivedByMemberIds = conversation.archivedByMemberIds
        .where((id) => id != memberId)
        .toList();
    final mutedByMemberIds = conversation.mutedByMemberIds
        .where((id) => id != memberId)
        .toList();
    final lastReadTimestamps = Map<String, DateTime>.from(
      conversation.lastReadTimestamps,
    )..remove(memberId);
    final creatorId = conversation.creatorId == memberId
        ? participantIds.firstOrNull
        : conversation.creatorId;

    if (_listEquals(participantIds, conversation.participantIds) &&
        _listEquals(archivedByMemberIds, conversation.archivedByMemberIds) &&
        _listEquals(mutedByMemberIds, conversation.mutedByMemberIds) &&
        _mapEquals(lastReadTimestamps, conversation.lastReadTimestamps) &&
        creatorId == conversation.creatorId) {
      return conversation;
    }

    return conversation.copyWith(
      participantIds: participantIds,
      archivedByMemberIds: archivedByMemberIds,
      mutedByMemberIds: mutedByMemberIds,
      lastReadTimestamps: lastReadTimestamps,
      creatorId: creatorId,
    );
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
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
    await syncRecordUpdate(_table, id, {'delete_push_started_at': timestampMs});
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
    // Determinism contract: `unknownSentinelMemberId` is a UUIDv5 derived
    // from a fixed namespace + literal name (see
    // `core/constants/fronting_namespaces.dart`). The id is byte-
    // identical across devices and across fresh AppDatabase instances,
    // so paired peers that ensure-the-sentinel under sync suppression
    // converge on the same member row without a sync op carrying the id.
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
    try {
      await createMember(sentinel);
      return (member: sentinel, wasCreated: true);
    } catch (e) {
      // Two concurrent callers can both observe missing and race to insert.
      // Drift serializes writes on a single connection in practice, so this
      // is a defense-in-depth path — but the helper's documented contract
      // is "idempotent ensure," and an upsert would silently overwrite the
      // winning row's name/emoji/isActive on every call. Catch the
      // constraint, refetch the winner, and report wasCreated=false.
      //
      // The collision surfaces as SQLITE_CONSTRAINT_PRIMARYKEY (1555) on
      // the members table since `id` is the PK; broaden to UNIQUE (2067)
      // for paranoia in case future schema changes add a unique index.
      if (!isUniqueOrPrimaryKeyConstraintViolation(e)) rethrow;
      final raced = await getMemberById(unknownSentinelMemberId);
      if (raced == null) rethrow; // genuinely something else
      return (member: raced, wasCreated: false);
    }
  }

  domain.Member _normalizeMember(domain.Member member) {
    final normalizedAvatar = AvatarNormalizer.normalize(member.avatarImageData);
    if (normalizedAvatar == member.avatarImageData) {
      return member;
    }
    return member.copyWith(avatarImageData: normalizedAvatar);
  }

  Map<String, dynamic> _memberFields(domain.Member m) => memberFields(m);

  /// Field-map builder for member sync emissions.
  ///
  /// Public so the Phase 6 batch-member capture path in `sp_importer.dart`
  /// can construct byte-identical `fields` payloads when it bypasses
  /// `createMember()` for the bulk insert. Single source of truth per
  /// entity is mandatory (codex v2 finding). See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> memberFields(domain.Member m) {
    final Uint8List? avatar = m.avatarImageData;
    return {
      'name': m.name,
      'pronouns': m.pronouns,
      'emoji': m.emoji,
      'age': m.age,
      'bio': m.bio,
      'avatar_image_data': avatar != null ? base64Encode(avatar) : null,
      'pk_avatar_cached_url': m.pkAvatarCachedUrl,
      'is_active': m.isActive,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      'display_order': m.displayOrder,
      'is_admin': m.isAdmin,
      'custom_color_enabled': m.customColorEnabled,
      'custom_color_hex': m.customColorHex,
      'parent_system_id': m.parentSystemId,
      'pluralkit_uuid': m.pluralkitUuid,
      'pluralkit_id': m.pluralkitId,
      'pluralkit_display_name': m.pluralkitDisplayName,
      'markdown_enabled': m.markdownEnabled,
      'display_name': m.displayName,
      'birthday': m.birthday,
      'proxy_tags_json': m.proxyTagsJson,
      'pk_banner_url': m.pkBannerUrl,
      'profile_header_source': m.profileHeaderSource.index,
      'profile_header_layout': m.profileHeaderLayout.index,
      'profile_header_visible': m.profileHeaderVisible,
      'name_style_font': m.nameStyleFont.index,
      'name_style_bold': m.nameStyleBold,
      'name_style_italic': m.nameStyleItalic,
      'name_style_color_mode': m.nameStyleColorMode.index,
      'name_style_color_hex': m.nameStyleColorHex,
      'profile_header_image_data': m.profileHeaderImageData != null
          ? base64Encode(m.profileHeaderImageData!)
          : null,
      'pk_banner_image_data': m.pkBannerImageData != null
          ? base64Encode(m.pkBannerImageData!)
          : null,
      'pk_banner_cached_url': m.pkBannerCachedUrl,
      'pluralkit_sync_ignored': m.pluralkitSyncIgnored,
      'is_always_fronting': m.isAlwaysFronting,
      'is_deleted': false,
    };
  }

  /// Mirror of [memberFields] keyed off the raw Drift row. Used by the
  /// patch-style update path to diff the stored row against the
  /// incoming domain object so the wire-side emission only contains
  /// fields the writer actually changed.
  ///
  /// `board_last_read_at` is intentionally **not** included here. The
  /// column lives on the members table but is owned by the board-posts
  /// repo's `markInboxOpenedFor` flow — it routes through
  /// `updateMemberFields(id, {'board_last_read_at': ...})` and is
  /// diffed against `previous[key] = null` (absent), which surfaces a
  /// patch entry on the first write. Keeping it out of the per-domain
  /// field map prevents `updateMember(domain)` (which lacks the field
  /// on the domain model) from accidentally clearing it.
  Map<String, dynamic> _memberFieldsFromRow(db.Member m) {
    final avatar = m.avatarImageData;
    return {
      'name': m.name,
      'pronouns': m.pronouns,
      'emoji': m.emoji,
      'age': m.age,
      'bio': m.bio,
      'avatar_image_data': avatar != null ? base64Encode(avatar) : null,
      'pk_avatar_cached_url': m.pkAvatarCachedUrl,
      'is_active': m.isActive,
      'created_at': toSyncUtc(m.createdAt),
      'display_order': m.displayOrder,
      'is_admin': m.isAdmin,
      'custom_color_enabled': m.customColorEnabled,
      'custom_color_hex': m.customColorHex,
      'parent_system_id': m.parentSystemId,
      'pluralkit_uuid': m.pluralkitUuid,
      'pluralkit_id': m.pluralkitId,
      'pluralkit_display_name': m.pluralkitDisplayName,
      'markdown_enabled': m.markdownEnabled,
      'display_name': m.displayName,
      'birthday': m.birthday,
      // proxy_tags_json is ORDERED — the user's preferred order matters.
      // Keep it as the stored text (matches the static memberFields()
      // builder which does `m.proxyTagsJson` straight through). Do NOT
      // canonicalize via jsonSet.
      'proxy_tags_json': m.proxyTagsJson,
      'pk_banner_url': m.pkBannerUrl,
      'profile_header_source': m.profileHeaderSource,
      'profile_header_layout': m.profileHeaderLayout,
      'profile_header_visible': m.profileHeaderVisible,
      'name_style_font': m.nameStyleFont,
      'name_style_bold': m.nameStyleBold,
      'name_style_italic': m.nameStyleItalic,
      'name_style_color_mode': m.nameStyleColorMode,
      'name_style_color_hex': m.nameStyleColorHex,
      'profile_header_image_data': m.profileHeaderImageData != null
          ? base64Encode(m.profileHeaderImageData!)
          : null,
      'pk_banner_image_data': m.pkBannerImageData != null
          ? base64Encode(m.pkBannerImageData!)
          : null,
      'pk_banner_cached_url': m.pkBannerCachedUrl,
      'pluralkit_sync_ignored': m.pluralkitSyncIgnored,
      'is_always_fronting': m.isAlwaysFronting,
      'is_deleted': m.isDeleted,
    };
  }

  /// Allow-list of column keys that the keyed [updateMemberFields]
  /// entry point accepts. Anything else passed by a caller is silently
  /// filtered before the diff so a typo'd key doesn't reach the
  /// partial-companion builder.
  ///
  /// `delete_intent_epoch` and `delete_push_started_at` are deliberately
  /// excluded — they're delete-push bookkeeping, stamped exclusively by
  /// `stampDeletePushStartedAt` and the unlink flow. Letting the generic
  /// keyed entry point write them would let a caller smuggle a delete
  /// intent onto an active member.
  static const _memberPatchKeys = {
    'name',
    'pronouns',
    'emoji',
    'age',
    'bio',
    'avatar_image_data',
    'pk_avatar_cached_url',
    'is_active',
    'created_at',
    'display_order',
    'is_admin',
    'custom_color_enabled',
    'custom_color_hex',
    'parent_system_id',
    'pluralkit_uuid',
    'pluralkit_id',
    'pluralkit_display_name',
    'markdown_enabled',
    'display_name',
    'birthday',
    'proxy_tags_json',
    'pk_banner_url',
    'profile_header_source',
    'profile_header_layout',
    'profile_header_visible',
    'name_style_font',
    'name_style_bold',
    'name_style_italic',
    'name_style_color_mode',
    'name_style_color_hex',
    'profile_header_image_data',
    'pk_banner_image_data',
    'pk_banner_cached_url',
    'pluralkit_sync_ignored',
    'is_always_fronting',
    'board_last_read_at',
  };

  Map<String, dynamic> _knownMemberFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    for (final entry in fields.entries) {
      if (_memberPatchKeys.contains(entry.key)) {
        out[entry.key] = _normalizePatchValue(entry.key, entry.value);
      }
    }
    return out;
  }

  Object? _normalizePatchValue(String key, Object? value) {
    if ((key == 'created_at' || key == 'board_last_read_at') &&
        value is DateTime) {
      return toSyncUtc(value);
    }
    return value;
  }

  db.MembersCompanion _partialMemberCompanion(Map<String, dynamic> fields) {
    return db.MembersCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      pronouns: fields.containsKey('pronouns')
          ? Value(fields['pronouns'] as String?)
          : const Value.absent(),
      emoji: fields.containsKey('emoji')
          ? Value(fields['emoji'] as String)
          : const Value.absent(),
      age: fields.containsKey('age')
          ? Value(fields['age'] as String?)
          : const Value.absent(),
      bio: fields.containsKey('bio')
          ? Value(fields['bio'] as String?)
          : const Value.absent(),
      avatarImageData: fields.containsKey('avatar_image_data')
          ? Value(_decodeAvatarBlob(fields['avatar_image_data']))
          : const Value.absent(),
      pkAvatarCachedUrl: fields.containsKey('pk_avatar_cached_url')
          ? Value(fields['pk_avatar_cached_url'] as String?)
          : const Value.absent(),
      isActive: fields.containsKey('is_active')
          ? Value(fields['is_active'] as bool)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      displayOrder: fields.containsKey('display_order')
          ? Value(fields['display_order'] as int)
          : const Value.absent(),
      isAdmin: fields.containsKey('is_admin')
          ? Value(fields['is_admin'] as bool)
          : const Value.absent(),
      customColorEnabled: fields.containsKey('custom_color_enabled')
          ? Value(fields['custom_color_enabled'] as bool)
          : const Value.absent(),
      customColorHex: fields.containsKey('custom_color_hex')
          ? Value(fields['custom_color_hex'] as String?)
          : const Value.absent(),
      parentSystemId: fields.containsKey('parent_system_id')
          ? Value(fields['parent_system_id'] as String?)
          : const Value.absent(),
      pluralkitUuid: fields.containsKey('pluralkit_uuid')
          ? Value(fields['pluralkit_uuid'] as String?)
          : const Value.absent(),
      pluralkitId: fields.containsKey('pluralkit_id')
          ? Value(fields['pluralkit_id'] as String?)
          : const Value.absent(),
      pluralkitDisplayName: fields.containsKey('pluralkit_display_name')
          ? Value(fields['pluralkit_display_name'] as String?)
          : const Value.absent(),
      markdownEnabled: fields.containsKey('markdown_enabled')
          ? Value(fields['markdown_enabled'] as bool)
          : const Value.absent(),
      displayName: fields.containsKey('display_name')
          ? Value(fields['display_name'] as String?)
          : const Value.absent(),
      birthday: fields.containsKey('birthday')
          ? Value(fields['birthday'] as String?)
          : const Value.absent(),
      proxyTagsJson: fields.containsKey('proxy_tags_json')
          ? Value(fields['proxy_tags_json'] as String?)
          : const Value.absent(),
      pkBannerUrl: fields.containsKey('pk_banner_url')
          ? Value(fields['pk_banner_url'] as String?)
          : const Value.absent(),
      profileHeaderSource: fields.containsKey('profile_header_source')
          ? Value(fields['profile_header_source'] as int)
          : const Value.absent(),
      profileHeaderLayout: fields.containsKey('profile_header_layout')
          ? Value(fields['profile_header_layout'] as int)
          : const Value.absent(),
      profileHeaderVisible: fields.containsKey('profile_header_visible')
          ? Value(fields['profile_header_visible'] as bool)
          : const Value.absent(),
      nameStyleFont: fields.containsKey('name_style_font')
          ? Value(fields['name_style_font'] as int)
          : const Value.absent(),
      nameStyleBold: fields.containsKey('name_style_bold')
          ? Value(fields['name_style_bold'] as bool)
          : const Value.absent(),
      nameStyleItalic: fields.containsKey('name_style_italic')
          ? Value(fields['name_style_italic'] as bool)
          : const Value.absent(),
      nameStyleColorMode: fields.containsKey('name_style_color_mode')
          ? Value(fields['name_style_color_mode'] as int)
          : const Value.absent(),
      nameStyleColorHex: fields.containsKey('name_style_color_hex')
          ? Value(fields['name_style_color_hex'] as String?)
          : const Value.absent(),
      profileHeaderImageData: fields.containsKey('profile_header_image_data')
          ? Value(_decodeAvatarBlob(fields['profile_header_image_data']))
          : const Value.absent(),
      pkBannerImageData: fields.containsKey('pk_banner_image_data')
          ? Value(_decodeAvatarBlob(fields['pk_banner_image_data']))
          : const Value.absent(),
      pkBannerCachedUrl: fields.containsKey('pk_banner_cached_url')
          ? Value(fields['pk_banner_cached_url'] as String?)
          : const Value.absent(),
      pluralkitSyncIgnored: fields.containsKey('pluralkit_sync_ignored')
          ? Value(fields['pluralkit_sync_ignored'] as bool)
          : const Value.absent(),
      isAlwaysFronting: fields.containsKey('is_always_fronting')
          ? Value(fields['is_always_fronting'] as bool)
          : const Value.absent(),
      boardLastReadAt: fields.containsKey('board_last_read_at')
          ? Value(_parseSyncDateTimeOrNull(fields['board_last_read_at']))
          : const Value.absent(),
      deleteIntentEpoch: fields.containsKey('delete_intent_epoch')
          ? Value(fields['delete_intent_epoch'] as int?)
          : const Value.absent(),
      deletePushStartedAt: fields.containsKey('delete_push_started_at')
          ? Value(fields['delete_push_started_at'] as int?)
          : const Value.absent(),
    );
  }

  /// Decode a base64 avatar blob coming off the patch map back into
  /// bytes for the Drift `avatarImageData` column. The patch map carries
  /// the field as a base64 string (matching `memberFields` which is
  /// also the sync wire format); converting it here keeps the call
  /// sites of `updateMemberFields(id, Map)` agnostic of the encoding.
  /// Accepts a `Uint8List` directly too in case a caller skips the
  /// encode/decode round-trip (e.g. an internal Dart caller).
  Uint8List? _decodeAvatarBlob(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    return Uint8List.fromList(base64Decode(value as String));
  }

  DateTime? _parseSyncDateTimeOrNull(Object? value) {
    if (value == null) return null;
    return parseSyncDateTime(value);
  }
}
