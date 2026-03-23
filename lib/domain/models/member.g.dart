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
};
