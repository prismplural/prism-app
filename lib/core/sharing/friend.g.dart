// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Friend _$FriendFromJson(Map<String, dynamic> json) => _Friend(
  id: json['id'] as String,
  displayName: json['displayName'] as String,
  peerSharingId: json['peerSharingId'] as String?,
  pairwiseSecret: _friendBytesFromJson(json['pairwiseSecret'] as String?),
  pinnedIdentity: _friendBytesFromJson(json['pinnedIdentity'] as String?),
  offeredScopes:
      (json['offeredScopes'] as List<dynamic>?)
          ?.map((e) => $enumDecode(_$ShareScopeEnumMap, e))
          .toList() ??
      const <ShareScope>[],
  publicKeyHex: json['publicKeyHex'] as String,
  grantedScopes: (json['grantedScopes'] as List<dynamic>)
      .map((e) => $enumDecode(_$ShareScopeEnumMap, e))
      .toList(),
  addedAt: DateTime.parse(json['addedAt'] as String),
  establishedAt: json['establishedAt'] == null
      ? null
      : DateTime.parse(json['establishedAt'] as String),
  lastSyncAt: json['lastSyncAt'] == null
      ? null
      : DateTime.parse(json['lastSyncAt'] as String),
  sharedSecretHex: json['sharedSecretHex'] as String?,
  initId: json['initId'] as String?,
  isVerified: json['isVerified'] as bool? ?? false,
);

Map<String, dynamic> _$FriendToJson(_Friend instance) => <String, dynamic>{
  'id': instance.id,
  'displayName': instance.displayName,
  'peerSharingId': instance.peerSharingId,
  'pairwiseSecret': _friendBytesToJson(instance.pairwiseSecret),
  'pinnedIdentity': _friendBytesToJson(instance.pinnedIdentity),
  'offeredScopes': instance.offeredScopes
      .map((e) => _$ShareScopeEnumMap[e]!)
      .toList(),
  'publicKeyHex': instance.publicKeyHex,
  'grantedScopes': instance.grantedScopes
      .map((e) => _$ShareScopeEnumMap[e]!)
      .toList(),
  'addedAt': instance.addedAt.toIso8601String(),
  'establishedAt': instance.establishedAt?.toIso8601String(),
  'lastSyncAt': instance.lastSyncAt?.toIso8601String(),
  'sharedSecretHex': instance.sharedSecretHex,
  'initId': instance.initId,
  'isVerified': instance.isVerified,
};

const _$ShareScopeEnumMap = {
  ShareScope.frontStatusOnly: 'frontStatusOnly',
  ShareScope.memberProfiles: 'memberProfiles',
  ShareScope.frontHistory: 'frontHistory',
  ShareScope.fullAccess: 'fullAccess',
};
