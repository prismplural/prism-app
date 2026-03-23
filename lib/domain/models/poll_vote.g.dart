// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poll_vote.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PollVote _$PollVoteFromJson(Map<String, dynamic> json) => _PollVote(
  id: json['id'] as String,
  memberId: json['memberId'] as String,
  votedAt: DateTime.parse(json['votedAt'] as String),
  responseText: json['responseText'] as String?,
);

Map<String, dynamic> _$PollVoteToJson(_PollVote instance) => <String, dynamic>{
  'id': instance.id,
  'memberId': instance.memberId,
  'votedAt': instance.votedAt.toIso8601String(),
  'responseText': instance.responseText,
};
