// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_reaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MessageReaction _$MessageReactionFromJson(Map<String, dynamic> json) =>
    _MessageReaction(
      id: json['id'] as String,
      emoji: json['emoji'] as String,
      memberId: json['memberId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$MessageReactionToJson(_MessageReaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'emoji': instance.emoji,
      'memberId': instance.memberId,
      'timestamp': instance.timestamp.toIso8601String(),
    };
