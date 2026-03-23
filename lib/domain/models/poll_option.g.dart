// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poll_option.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PollOption _$PollOptionFromJson(Map<String, dynamic> json) => _PollOption(
  id: json['id'] as String,
  text: json['text'] as String,
  sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
  isOtherOption: json['isOtherOption'] as bool? ?? false,
  colorHex: json['colorHex'] as String?,
  votes:
      (json['votes'] as List<dynamic>?)
          ?.map((e) => PollVote.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$PollOptionToJson(_PollOption instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'sortOrder': instance.sortOrder,
      'isOtherOption': instance.isOtherOption,
      'colorHex': instance.colorHex,
      'votes': instance.votes,
    };
