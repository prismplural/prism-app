import 'package:freezed_annotation/freezed_annotation.dart';

part 'friend_record.freezed.dart';
part 'friend_record.g.dart';

@freezed
abstract class FriendRecord with _$FriendRecord {
  const factory FriendRecord({
    required String id,
    required String displayName,
    required String publicKeyHex,
    String? sharedSecretHex,
    @Default(<String>[]) List<String> grantedScopes,
    @Default(false) bool isVerified,
    required DateTime createdAt,
    DateTime? lastSyncAt,
  }) = _FriendRecord;

  factory FriendRecord.fromJson(Map<String, dynamic> json) =>
      _$FriendRecordFromJson(json);
}
