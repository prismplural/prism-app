import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_attachment.freezed.dart';
part 'media_attachment.g.dart';

@freezed
abstract class MediaAttachment with _$MediaAttachment {
  const factory MediaAttachment({
    required String id,
    required String messageId,
    required String mediaId,
    required String mediaType,
    required String encryptionKeyB64,
    required String contentHash,
    required String plaintextHash,
    required String mimeType,
    required int sizeBytes,
    required int width,
    required int height,
    required int durationMs,
    required String blurhash,
    required String waveformB64,
    required String thumbnailMediaId,
    required String sourceUrl,
    required String previewUrl,
    @Default(false) bool isDeleted,
  }) = _MediaAttachment;

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      _$MediaAttachmentFromJson(json);
}
