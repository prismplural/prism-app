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
    // When true, every active member is implicitly a participant — avoids
    // a sync op per member on toggle and on every membership change after.
    @Default(false) bool includesAllMembers,
    @Default([]) List<String> archivedByMemberIds,
    // Convo-level archive (vs the per-member archivedByMemberIds). Separate
    // field so a per-member archive can't clobber it under field-level LWW.
    @Default(false) bool archivedForEveryone,
    @Default([]) List<String> mutedByMemberIds,
    @Default({}) Map<String, DateTime> lastReadTimestamps,
    String? description,
    String? categoryId,
    @Default(0) int displayOrder,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);
}
