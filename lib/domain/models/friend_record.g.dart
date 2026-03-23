// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FriendRecord _$FriendRecordFromJson(Map<String, dynamic> json) =>
    _FriendRecord(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      publicKeyHex: json['publicKeyHex'] as String,
      sharedSecretHex: json['sharedSecretHex'] as String?,
      grantedScopes:
          (json['grantedScopes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      isVerified: json['isVerified'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastSyncAt: json['lastSyncAt'] == null
          ? null
          : DateTime.parse(json['lastSyncAt'] as String),
    );

Map<String, dynamic> _$FriendRecordToJson(_FriendRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'publicKeyHex': instance.publicKeyHex,
      'sharedSecretHex': instance.sharedSecretHex,
      'grantedScopes': instance.grantedScopes,
      'isVerified': instance.isVerified,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastSyncAt': instance.lastSyncAt?.toIso8601String(),
    };
