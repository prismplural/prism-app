// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationCategory _$ConversationCategoryFromJson(
  Map<String, dynamic> json,
) => _ConversationCategory(
  id: json['id'] as String,
  name: json['name'] as String,
  displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
  createdAt: DateTime.parse(json['createdAt'] as String),
  modifiedAt: DateTime.parse(json['modifiedAt'] as String),
);

Map<String, dynamic> _$ConversationCategoryToJson(
  _ConversationCategory instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'displayOrder': instance.displayOrder,
  'createdAt': instance.createdAt.toIso8601String(),
  'modifiedAt': instance.modifiedAt.toIso8601String(),
};
