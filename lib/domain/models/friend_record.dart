import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'friend_record.freezed.dart';
part 'friend_record.g.dart';

Uint8List? _friendBytesFromJson(String? json) =>
    json == null ? null : base64Decode(json);

String? _friendBytesToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);

@freezed
abstract class FriendRecord with _$FriendRecord {
  const factory FriendRecord({
    required String id,
    required String displayName,
    String? peerSharingId,
    @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)
    Uint8List? pairwiseSecret,
    @JsonKey(fromJson: _friendBytesFromJson, toJson: _friendBytesToJson)
    Uint8List? pinnedIdentity,
    @Default(<String>[]) List<String> offeredScopes,
    required String publicKeyHex,
    String? sharedSecretHex,
    @Default(<String>[]) List<String> grantedScopes,
    @Default(false) bool isVerified,
    String? initId,
    required DateTime createdAt,
    DateTime? establishedAt,
    DateTime? lastSyncAt,
  }) = _FriendRecord;

  factory FriendRecord.fromJson(Map<String, dynamic> json) =>
      _$FriendRecordFromJson(json);
}
