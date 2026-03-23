import 'package:freezed_annotation/freezed_annotation.dart';

import 'poll_option.dart';

part 'poll.freezed.dart';
part 'poll.g.dart';

@freezed
abstract class Poll with _$Poll {
  const factory Poll({
    required String id,
    required String question,
    String? description,
    @Default(false) bool isAnonymous,
    @Default(false) bool allowsMultipleVotes,
    @Default(false) bool isClosed,
    DateTime? expiresAt,
    required DateTime createdAt,
    @Default([]) List<PollOption> options,
  }) = _Poll;

  factory Poll.fromJson(Map<String, dynamic> json) => _$PollFromJson(json);
}
