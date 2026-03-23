import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_result.freezed.dart';

@freezed
abstract class MessageSearchResult with _$MessageSearchResult {
  const factory MessageSearchResult({
    required String messageId,
    required String conversationId,
    required String snippet,
    required DateTime timestamp,
    String? authorId,
    String? authorName,
    String? authorEmoji,
    Uint8List? authorAvatarData,
    bool? authorCustomColorEnabled,
    String? authorCustomColorHex,
    String? conversationTitle,
    String? conversationEmoji,
  }) = _MessageSearchResult;
}
