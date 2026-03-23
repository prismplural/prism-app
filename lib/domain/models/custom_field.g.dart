// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_field.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CustomField _$CustomFieldFromJson(Map<String, dynamic> json) => _CustomField(
  id: json['id'] as String,
  name: json['name'] as String,
  fieldType: $enumDecode(_$CustomFieldTypeEnumMap, json['fieldType']),
  datePrecision: $enumDecodeNullable(
    _$DatePrecisionEnumMap,
    json['datePrecision'],
  ),
  displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$CustomFieldToJson(_CustomField instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'fieldType': _$CustomFieldTypeEnumMap[instance.fieldType]!,
      'datePrecision': _$DatePrecisionEnumMap[instance.datePrecision],
      'displayOrder': instance.displayOrder,
      'createdAt': instance.createdAt.toIso8601String(),
    };

const _$CustomFieldTypeEnumMap = {
  CustomFieldType.text: 'text',
  CustomFieldType.color: 'color',
  CustomFieldType.date: 'date',
};

const _$DatePrecisionEnumMap = {
  DatePrecision.full: 'full',
  DatePrecision.monthYear: 'monthYear',
  DatePrecision.monthDay: 'monthDay',
  DatePrecision.month: 'month',
  DatePrecision.year: 'year',
  DatePrecision.timestamp: 'timestamp',
};
