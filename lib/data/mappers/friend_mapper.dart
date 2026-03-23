import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/friend_record.dart' as domain;

class FriendMapper {
  FriendMapper._();

  static domain.FriendRecord toDomain(FriendRow row) {
    List<String> scopes;
    try {
      scopes = (jsonDecode(row.grantedScopes) as List).cast<String>();
    } catch (_) {
      scopes = [];
    }

    return domain.FriendRecord(
      id: row.id,
      displayName: row.displayName,
      publicKeyHex: row.publicKeyHex,
      sharedSecretHex: row.sharedSecretHex,
      grantedScopes: scopes,
      isVerified: row.isVerified,
      createdAt: row.createdAt,
      lastSyncAt: row.lastSyncAt,
    );
  }

  static FriendsCompanion toCompanion(domain.FriendRecord model) {
    return FriendsCompanion(
      id: Value(model.id),
      displayName: Value(model.displayName),
      publicKeyHex: Value(model.publicKeyHex),
      sharedSecretHex: Value(model.sharedSecretHex),
      grantedScopes: Value(jsonEncode(model.grantedScopes)),
      isVerified: Value(model.isVerified),
      createdAt: Value(model.createdAt),
      lastSyncAt: Value(model.lastSyncAt),
    );
  }
}
