import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_reaction.freezed.dart';
part 'message_reaction.g.dart';

@freezed
abstract class MessageReaction with _$MessageReaction {
  const factory MessageReaction({
    required String id,
    required String emoji,
    required String memberId,
    required DateTime timestamp,
  }) = _MessageReaction;

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      _$MessageReactionFromJson(json);
}
