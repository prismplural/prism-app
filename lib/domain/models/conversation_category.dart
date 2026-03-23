import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_category.freezed.dart';
part 'conversation_category.g.dart';

@freezed
abstract class ConversationCategory with _$ConversationCategory {
  const factory ConversationCategory({
    required String id,
    required String name,
    @Default(0) int displayOrder,
    required DateTime createdAt,
    required DateTime modifiedAt,
  }) = _ConversationCategory;

  factory ConversationCategory.fromJson(Map<String, dynamic> json) =>
      _$ConversationCategoryFromJson(json);
}
