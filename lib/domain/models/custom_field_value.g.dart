// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_field_value.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CustomFieldValue _$CustomFieldValueFromJson(Map<String, dynamic> json) =>
    _CustomFieldValue(
      id: json['id'] as String,
      customFieldId: json['customFieldId'] as String,
      memberId: json['memberId'] as String,
      value: json['value'] as String,
    );

Map<String, dynamic> _$CustomFieldValueToJson(_CustomFieldValue instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customFieldId': instance.customFieldId,
      'memberId': instance.memberId,
      'value': instance.value,
    };
