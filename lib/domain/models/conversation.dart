import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

@freezed
abstract class Conversation with _$Conversation {
  const factory Conversation({
    required String id,
    required DateTime createdAt,
    required DateTime lastActivityAt,
    String? title,
    String? emoji,
    @Default(false) bool isDirectMessage,
    String? creatorId,
    @Default([]) List<String> participantIds,
    @Default([]) List<String> archivedByMemberIds,
    @Default([]) List<String> mutedByMemberIds,
    @Default({}) Map<String, DateTime> lastReadTimestamps,
    String? description,
    String? categoryId,
    @Default(0) int displayOrder,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);
}
