// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Friend _$FriendFromJson(Map<String, dynamic> json) => _Friend(
  id: json['id'] as String,
  displayName: json['displayName'] as String,
  publicKeyHex: json['publicKeyHex'] as String,
  grantedScopes: (json['grantedScopes'] as List<dynamic>)
      .map((e) => $enumDecode(_$ShareScopeEnumMap, e))
      .toList(),
  addedAt: DateTime.parse(json['addedAt'] as String),
  lastSyncAt: json['lastSyncAt'] == null
      ? null
      : DateTime.parse(json['lastSyncAt'] as String),
  sharedSecretHex: json['sharedSecretHex'] as String?,
  isVerified: json['isVerified'] as bool? ?? false,
);

Map<String, dynamic> _$FriendToJson(_Friend instance) => <String, dynamic>{
  'id': instance.id,
  'displayName': instance.displayName,
  'publicKeyHex': instance.publicKeyHex,
  'grantedScopes': instance.grantedScopes
      .map((e) => _$ShareScopeEnumMap[e]!)
      .toList(),
  'addedAt': instance.addedAt.toIso8601String(),
  'lastSyncAt': instance.lastSyncAt?.toIso8601String(),
  'sharedSecretHex': instance.sharedSecretHex,
  'isVerified': instance.isVerified,
};

const _$ShareScopeEnumMap = {
  ShareScope.frontStatusOnly: 'frontStatusOnly',
  ShareScope.memberProfiles: 'memberProfiles',
  ShareScope.frontHistory: 'frontHistory',
  ShareScope.fullAccess: 'fullAccess',
};
