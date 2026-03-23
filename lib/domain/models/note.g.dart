// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Note _$NoteFromJson(Map<String, dynamic> json) => _Note(
  id: json['id'] as String,
  title: json['title'] as String,
  body: json['body'] as String,
  colorHex: json['colorHex'] as String?,
  memberId: json['memberId'] as String?,
  date: DateTime.parse(json['date'] as String),
  createdAt: DateTime.parse(json['createdAt'] as String),
  modifiedAt: DateTime.parse(json['modifiedAt'] as String),
);

Map<String, dynamic> _$NoteToJson(_Note instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'body': instance.body,
  'colorHex': instance.colorHex,
  'memberId': instance.memberId,
  'date': instance.date.toIso8601String(),
  'createdAt': instance.createdAt.toIso8601String(),
  'modifiedAt': instance.modifiedAt.toIso8601String(),
};
