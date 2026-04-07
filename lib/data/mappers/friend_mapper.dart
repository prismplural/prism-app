import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/friend_record.dart' as domain;

class FriendMapper {
  FriendMapper._();

  static domain.FriendRecord toDomain(FriendRow row) {
    final grantedScopes = _decodeScopes(row.grantedScopes);
    final offeredScopes = _decodeScopes(row.offeredScopes);

    return domain.FriendRecord(
      id: row.id,
      displayName: row.displayName,
      peerSharingId: row.peerSharingId,
      pairwiseSecret: row.pairwiseSecret != null
          ? Uint8List.fromList(row.pairwiseSecret!)
          : null,
      pinnedIdentity: row.pinnedIdentity != null
          ? Uint8List.fromList(row.pinnedIdentity!)
          : null,
      offeredScopes: offeredScopes,
      publicKeyHex: row.publicKeyHex,
      sharedSecretHex: row.sharedSecretHex,
      grantedScopes: grantedScopes,
      isVerified: row.isVerified,
      initId: row.initId,
      createdAt: row.createdAt,
      establishedAt: row.establishedAt,
      lastSyncAt: row.lastSyncAt,
    );
  }

  static FriendsCompanion toCompanion(domain.FriendRecord model) {
    return FriendsCompanion(
      id: Value(model.id),
      displayName: Value(model.displayName),
      peerSharingId: Value(model.peerSharingId),
      pairwiseSecret: Value(model.pairwiseSecret),
      pinnedIdentity: Value(model.pinnedIdentity),
      offeredScopes: Value(jsonEncode(model.offeredScopes)),
      publicKeyHex: Value(model.publicKeyHex),
      sharedSecretHex: Value(model.sharedSecretHex),
      grantedScopes: Value(jsonEncode(model.grantedScopes)),
      isVerified: Value(model.isVerified),
      initId: Value(model.initId),
      createdAt: Value(model.createdAt),
      establishedAt: Value(model.establishedAt),
      lastSyncAt: Value(model.lastSyncAt),
    );
  }

  static List<String> _decodeScopes(String raw) {
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }
}
