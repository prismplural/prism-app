import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:prism_plurality/core/sharing/share_scope.dart';

part 'friend.freezed.dart';
part 'friend.g.dart';

Uint8List? _friendBytesFromJson(String? json) =>
    json == null ? null : base64Decode(json);

String? _friendBytesToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);

@freezed
abstract class Friend with _$Friend {
  const factory Friend({
    required String id,
    required String displayName,

    String? peerSharingId,

    @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)
    Uint8List? pairwiseSecret,

    @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)
    Uint8List? pinnedIdentity,

    /// Scopes this friend has offered to us.
    @Default(<ShareScope>[]) List<ShareScope> offeredScopes,

    /// Legacy public identity material, hex-encoded.
    ///
    /// For Phase 4 relationships this stores the canonical identity bundle hex
    /// so older persistence/export paths still have a non-secret public value.
    required String publicKeyHex,

    /// Scopes we have granted this friend.
    required List<ShareScope> grantedScopes,

    required DateTime addedAt,
    DateTime? establishedAt,
    DateTime? lastSyncAt,

    /// Legacy shared secret mirror, hex-encoded.
    ///
    /// For Phase 4 relationships this mirrors [pairwiseSecret] in hex so older
    /// persistence/export paths still have a compatible field.
    String? sharedSecretHex,

    String? initId,

    /// Whether out-of-band verification has been completed.
    @Default(false) bool isVerified,
  }) = _Friend;

  factory Friend.fromJson(Map<String, dynamic> json) => _$FriendFromJson(json);
}
