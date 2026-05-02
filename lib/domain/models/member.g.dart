// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Member _$MemberFromJson(Map<String, dynamic> json) => _Member(
  id: json['id'] as String,
  name: json['name'] as String,
  pronouns: json['pronouns'] as String?,
  emoji: json['emoji'] as String? ?? '❔',
  age: (json['age'] as num?)?.toInt(),
  bio: json['bio'] as String?,
  avatarImageData: _uint8ListFromJson(json['avatarImageData'] as String?),
  isActive: json['isActive'] as bool? ?? true,
  createdAt: DateTime.parse(json['createdAt'] as String),
  displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
  isAdmin: json['isAdmin'] as bool? ?? false,
  customColorEnabled: json['customColorEnabled'] as bool? ?? false,
  customColorHex: json['customColorHex'] as String?,
  parentSystemId: json['parentSystemId'] as String?,
  pluralkitUuid: json['pluralkitUuid'] as String?,
  pluralkitId: json['pluralkitId'] as String?,
  markdownEnabled: json['markdownEnabled'] as bool? ?? false,
  displayName: json['displayName'] as String?,
  birthday: json['birthday'] as String?,
  proxyTagsJson: json['proxyTagsJson'] as String?,
  pkBannerUrl: json['pkBannerUrl'] as String?,
  profileHeaderSource:
      $enumDecodeNullable(
        _$MemberProfileHeaderSourceEnumMap,
        json['profileHeaderSource'],
      ) ??
      MemberProfileHeaderSource.prism,
  profileHeaderLayout:
      $enumDecodeNullable(
        _$MemberProfileHeaderLayoutEnumMap,
        json['profileHeaderLayout'],
      ) ??
      MemberProfileHeaderLayout.compactBackground,
  profileHeaderVisible: json['profileHeaderVisible'] as bool? ?? true,
  nameStyleFont:
      $enumDecodeNullable(_$MemberNameFontEnumMap, json['nameStyleFont']) ??
      MemberNameFont.standard,
  nameStyleBold: json['nameStyleBold'] as bool? ?? true,
  nameStyleItalic: json['nameStyleItalic'] as bool? ?? false,
  nameStyleColorMode:
      $enumDecodeNullable(
        _$MemberNameColorModeEnumMap,
        json['nameStyleColorMode'],
      ) ??
      MemberNameColorMode.standard,
  nameStyleColorHex: json['nameStyleColorHex'] as String?,
  profileHeaderImageData: _uint8ListFromJson(
    json['profileHeaderImageData'] as String?,
  ),
  pkBannerImageData: _uint8ListFromJson(json['pkBannerImageData'] as String?),
  pkBannerCachedUrl: json['pkBannerCachedUrl'] as String?,
  pluralkitSyncIgnored: json['pluralkitSyncIgnored'] as bool? ?? false,
  isDeleted: json['isDeleted'] as bool? ?? false,
  deleteIntentEpoch: (json['deleteIntentEpoch'] as num?)?.toInt(),
  deletePushStartedAt: (json['deletePushStartedAt'] as num?)?.toInt(),
  isAlwaysFronting: json['isAlwaysFronting'] as bool? ?? false,
);

Map<String, dynamic> _$MemberToJson(_Member instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'pronouns': instance.pronouns,
  'emoji': instance.emoji,
  'age': instance.age,
  'bio': instance.bio,
  'avatarImageData': _uint8ListToJson(instance.avatarImageData),
  'isActive': instance.isActive,
  'createdAt': instance.createdAt.toIso8601String(),
  'displayOrder': instance.displayOrder,
  'isAdmin': instance.isAdmin,
  'customColorEnabled': instance.customColorEnabled,
  'customColorHex': instance.customColorHex,
  'parentSystemId': instance.parentSystemId,
  'pluralkitUuid': instance.pluralkitUuid,
  'pluralkitId': instance.pluralkitId,
  'markdownEnabled': instance.markdownEnabled,
  'displayName': instance.displayName,
  'birthday': instance.birthday,
  'proxyTagsJson': instance.proxyTagsJson,
  'pkBannerUrl': instance.pkBannerUrl,
  'profileHeaderSource':
      _$MemberProfileHeaderSourceEnumMap[instance.profileHeaderSource]!,
  'profileHeaderLayout':
      _$MemberProfileHeaderLayoutEnumMap[instance.profileHeaderLayout]!,
  'profileHeaderVisible': instance.profileHeaderVisible,
  'nameStyleFont': _$MemberNameFontEnumMap[instance.nameStyleFont]!,
  'nameStyleBold': instance.nameStyleBold,
  'nameStyleItalic': instance.nameStyleItalic,
  'nameStyleColorMode':
      _$MemberNameColorModeEnumMap[instance.nameStyleColorMode]!,
  'nameStyleColorHex': instance.nameStyleColorHex,
  'profileHeaderImageData': _uint8ListToJson(instance.profileHeaderImageData),
  'pkBannerImageData': _uint8ListToJson(instance.pkBannerImageData),
  'pkBannerCachedUrl': instance.pkBannerCachedUrl,
  'pluralkitSyncIgnored': instance.pluralkitSyncIgnored,
  'isDeleted': instance.isDeleted,
  'deleteIntentEpoch': instance.deleteIntentEpoch,
  'deletePushStartedAt': instance.deletePushStartedAt,
  'isAlwaysFronting': instance.isAlwaysFronting,
};

const _$MemberProfileHeaderSourceEnumMap = {
  MemberProfileHeaderSource.pluralKit: 'pluralKit',
  MemberProfileHeaderSource.prism: 'prism',
};

const _$MemberProfileHeaderLayoutEnumMap = {
  MemberProfileHeaderLayout.compactBackground: 'compactBackground',
  MemberProfileHeaderLayout.classicOverlap: 'classicOverlap',
};

const _$MemberNameFontEnumMap = {
  MemberNameFont.standard: 'standard',
  MemberNameFont.display: 'display',
  MemberNameFont.serif: 'serif',
  MemberNameFont.mono: 'mono',
  MemberNameFont.rounded: 'rounded',
};

const _$MemberNameColorModeEnumMap = {
  MemberNameColorMode.standard: 'standard',
  MemberNameColorMode.accent: 'accent',
  MemberNameColorMode.custom: 'custom',
};
