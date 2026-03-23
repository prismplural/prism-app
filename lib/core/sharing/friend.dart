import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:prism_plurality/core/sharing/share_scope.dart';

part 'friend.freezed.dart';
part 'friend.g.dart';

@freezed
abstract class Friend with _$Friend {
  const factory Friend({
    required String id,
    required String displayName,

    /// Their X25519 public key, hex-encoded.
    required String publicKeyHex,

    /// Scopes we have granted this friend.
    required List<ShareScope> grantedScopes,

    required DateTime addedAt,
    DateTime? lastSyncAt,

    /// ECDH-derived shared secret, hex-encoded. Stored encrypted at rest.
    String? sharedSecretHex,

    /// Whether SAS verification has been completed.
    @Default(false) bool isVerified,
  }) = _Friend;

  factory Friend.fromJson(Map<String, dynamic> json) =>
      _$FriendFromJson(json);
}
