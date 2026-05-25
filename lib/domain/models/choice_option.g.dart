// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'choice_option.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChoiceOption _$ChoiceOptionFromJson(Map<String, dynamic> json) =>
    _ChoiceOption(
      id: json['id'] as String,
      label: json['label'] as String,
      colorHex: json['colorHex'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );

Map<String, dynamic> _$ChoiceOptionToJson(_ChoiceOption instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'colorHex': instance.colorHex,
      'sortOrder': instance.sortOrder,
      'isDeleted': instance.isDeleted,
    };
