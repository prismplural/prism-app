import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/data/mappers/friend_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/friend_record.dart' as domain;
import 'package:prism_plurality/domain/repositories/friends_repository.dart';

class DriftFriendsRepository with SyncRecordMixin implements FriendsRepository {
  final FriendsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  @override
  AppDatabase get syncOutboxDatabase => _dao.attachedDatabase;

  static const _table = 'friends';

  DriftFriendsRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.FriendRecord>> watchAll() {
    return _dao.watchAll().map(
      (rows) => rows.map(FriendMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.FriendRecord?> getById(String id) async {
    final row = await _dao.getById(id);
    return row != null ? FriendMapper.toDomain(row) : null;
  }

  @override
  Future<void> createFriend(domain.FriendRecord friend) async {
    // Insert + create-op intent commit atomically; dispatch post-commit
    // (FFI outside the txn — reverted-revert invariant).
    await runSyncedWrite(() async {
      final companion = FriendMapper.toCompanion(friend);
      await _dao.createFriend(companion);
      await syncRecordCreate(_table, friend.id, _friendFields(friend));
    });
  }

  @override
  Future<void> updateFriend(domain.FriendRecord friend) async {
    // Read-diff-write + update-op intent in one atomic txn (dispatch
    // post-commit, FFI outside the txn).
    await runSyncedWrite(() async {
      final existingRow = await _dao.getById(friend.id);
      if (existingRow == null || existingRow.isDeleted) return;

      final changedFields = diffSyncFields(
        _friendFieldsFromRow(existingRow),
        _friendFields(friend),
      );
      if (changedFields.isEmpty) return;

      final companion = _partialFriendCompanion(changedFields);
      await _dao.updateFriend(friend.id, companion);
      await syncRecordUpdate(_table, friend.id, changedFields);
    });
  }

  @override
  Future<void> deleteFriend(String id) async {
    // Tombstone path (unrecoverable): soft-delete + delete-op intent
    // commit atomically; dispatch post-commit (FFI outside the txn).
    await runSyncedWrite(() async {
      await _dao.softDelete(id);
      await syncRecordDelete(_table, id);
    });
  }

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC.
  @visibleForTesting
  Map<String, dynamic> debugFriendFields(domain.FriendRecord f) =>
      _friendFields(f);

  FriendsCompanion _partialFriendCompanion(Map<String, dynamic> fields) {
    return FriendsCompanion(
      displayName: fields.containsKey('display_name')
          ? Value(fields['display_name'] as String)
          : const Value.absent(),
      peerSharingId: fields.containsKey('peer_sharing_id')
          ? Value(fields['peer_sharing_id'] as String?)
          : const Value.absent(),
      pairwiseSecret: fields.containsKey('pairwise_secret')
          ? Value(_decodeBytesOrNull(fields['pairwise_secret']))
          : const Value.absent(),
      pinnedIdentity: fields.containsKey('pinned_identity')
          ? Value(_decodeBytesOrNull(fields['pinned_identity']))
          : const Value.absent(),
      offeredScopes: fields.containsKey('offered_scopes')
          ? Value(fields['offered_scopes'] as String)
          : const Value.absent(),
      publicKeyHex: fields.containsKey('public_key_hex')
          ? Value(fields['public_key_hex'] as String)
          : const Value.absent(),
      sharedSecretHex: fields.containsKey('shared_secret_hex')
          ? Value(fields['shared_secret_hex'] as String?)
          : const Value.absent(),
      grantedScopes: fields.containsKey('granted_scopes')
          ? Value(fields['granted_scopes'] as String)
          : const Value.absent(),
      isVerified: fields.containsKey('is_verified')
          ? Value(fields['is_verified'] as bool)
          : const Value.absent(),
      initId: fields.containsKey('init_id')
          ? Value(fields['init_id'] as String?)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      establishedAt: fields.containsKey('established_at')
          ? Value(_parseSyncDateTimeOrNull(fields['established_at']))
          : const Value.absent(),
      lastSyncAt: fields.containsKey('last_sync_at')
          ? Value(_parseSyncDateTimeOrNull(fields['last_sync_at']))
          : const Value.absent(),
    );
  }

  /// Mirrors [_friendFields] but reads from the stored Drift row. The blob
  /// columns are base64-encoded back to strings so the diff compares against
  /// the same shape the domain side emits, and the JSON-set columns are
  /// decoded and re-encoded through [jsonSet] for symmetric canonicalization
  /// (avoids a one-time false-positive when the stored value happens to be
  /// in non-canonical order before the first patched edit).
  Map<String, dynamic> _friendFieldsFromRow(FriendRow row) {
    return {
      'display_name': row.displayName,
      'peer_sharing_id': row.peerSharingId,
      'pairwise_secret': row.pairwiseSecret != null
          ? base64Encode(row.pairwiseSecret!)
          : null,
      'pinned_identity': row.pinnedIdentity != null
          ? base64Encode(row.pinnedIdentity!)
          : null,
      'offered_scopes': jsonSet(_decodeScopes(row.offeredScopes)),
      'public_key_hex': row.publicKeyHex,
      'shared_secret_hex': row.sharedSecretHex,
      'granted_scopes': jsonSet(_decodeScopes(row.grantedScopes)),
      'is_verified': row.isVerified,
      'init_id': row.initId,
      'created_at': toSyncUtc(row.createdAt),
      'established_at': toSyncUtcOrNull(row.establishedAt),
      'last_sync_at': toSyncUtcOrNull(row.lastSyncAt),
      'is_deleted': row.isDeleted,
    };
  }

  /// Field map for sync emissions.
  ///
  /// `offered_scopes` and `granted_scopes` are set-semantic columns —
  /// element order is incidental, not user-meaningful — so they go through
  /// [jsonSet] for canonical (sorted) encoding. This is a behaviour change
  /// for the create path too: the first emission now carries scopes in
  /// canonical order. Matches `_friendFieldsFromRow`, which canonicalizes
  /// stored values the same way on the diff path.
  Map<String, dynamic> _friendFields(domain.FriendRecord f) {
    return {
      'display_name': f.displayName,
      'peer_sharing_id': f.peerSharingId,
      'pairwise_secret': f.pairwiseSecret != null
          ? base64Encode(f.pairwiseSecret!)
          : null,
      'pinned_identity': f.pinnedIdentity != null
          ? base64Encode(f.pinnedIdentity!)
          : null,
      'offered_scopes': jsonSet(f.offeredScopes),
      'public_key_hex': f.publicKeyHex,
      'shared_secret_hex': f.sharedSecretHex,
      'granted_scopes': jsonSet(f.grantedScopes),
      'is_verified': f.isVerified,
      'init_id': f.initId,
      'created_at': toSyncUtc(f.createdAt),
      'established_at': toSyncUtcOrNull(f.establishedAt),
      'last_sync_at': toSyncUtcOrNull(f.lastSyncAt),
      'is_deleted': false,
    };
  }

  static List<String> _decodeScopes(String raw) {
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const <String>[];
    }
  }

  static Uint8List? _decodeBytesOrNull(Object? value) {
    if (value == null) return null;
    return base64Decode(value as String);
  }

  static DateTime? _parseSyncDateTimeOrNull(Object? value) {
    if (value == null) return null;
    return parseSyncDateTime(value);
  }
}
