import 'package:freezed_annotation/freezed_annotation.dart';

part 'poll_vote.freezed.dart';
part 'poll_vote.g.dart';

@freezed
abstract class PollVote with _$PollVote {
  const factory PollVote({
    required String id,
    required String memberId,
    required DateTime votedAt,
    String? responseText,
  }) = _PollVote;

  factory PollVote.fromJson(Map<String, dynamic> json) =>
      _$PollVoteFromJson(json);
}
