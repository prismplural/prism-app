// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MemberGroup _$MemberGroupFromJson(Map<String, dynamic> json) => _MemberGroup(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  colorHex: json['colorHex'] as String?,
  emoji: json['emoji'] as String?,
  displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
  parentGroupId: json['parentGroupId'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$MemberGroupToJson(_MemberGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'colorHex': instance.colorHex,
      'emoji': instance.emoji,
      'displayOrder': instance.displayOrder,
      'parentGroupId': instance.parentGroupId,
      'createdAt': instance.createdAt.toIso8601String(),
    };
