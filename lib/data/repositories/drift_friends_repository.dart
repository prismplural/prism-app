import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/data/mappers/friend_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/friend_record.dart' as domain;
import 'package:prism_plurality/domain/repositories/friends_repository.dart';

class DriftFriendsRepository with SyncRecordMixin implements FriendsRepository {
  final FriendsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

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
    final companion = FriendMapper.toCompanion(friend);
    await _dao.createFriend(companion);
    await syncRecordCreate(_table, friend.id, _friendFields(friend));
  }

  @override
  Future<void> updateFriend(domain.FriendRecord friend) async {
    final companion = FriendMapper.toCompanion(friend);
    await _dao.updateFriend(friend.id, companion);
    await syncRecordUpdate(_table, friend.id, _friendFields(friend));
  }

  @override
  Future<void> deleteFriend(String id) async {
    await _dao.softDelete(id);
    await syncRecordDelete(_table, id);
  }

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
      'offered_scopes': jsonEncode(f.offeredScopes),
      'public_key_hex': f.publicKeyHex,
      'shared_secret_hex': f.sharedSecretHex,
      'granted_scopes': jsonEncode(f.grantedScopes),
      'is_verified': f.isVerified,
      'init_id': f.initId,
      'created_at': f.createdAt.toIso8601String(),
      'established_at': f.establishedAt?.toIso8601String(),
      'last_sync_at': f.lastSyncAt?.toIso8601String(),
      'is_deleted': false,
    };
  }
}
