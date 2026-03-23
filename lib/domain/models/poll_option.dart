import 'package:freezed_annotation/freezed_annotation.dart';

import 'poll_vote.dart';

part 'poll_option.freezed.dart';
part 'poll_option.g.dart';

@freezed
abstract class PollOption with _$PollOption {
  const factory PollOption({
    required String id,
    required String text,
    @Default(0) int sortOrder,
    @Default(false) bool isOtherOption,
    String? colorHex,
    @Default([]) List<PollVote> votes,
  }) = _PollOption;

  factory PollOption.fromJson(Map<String, dynamic> json) =>
      _$PollOptionFromJson(json);
}
