import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_attachment.freezed.dart';
part 'media_attachment.g.dart';

@freezed
abstract class MediaAttachment with _$MediaAttachment {
  const factory MediaAttachment({
    required String id,

    /// The ID of the chat message this attachment belongs to.
    required String messageId,

    /// Media type: 'image', 'voice', 'video', 'file'.
    required String mediaType,

    /// Server-side media ID for download.
    required String mediaId,

    /// MIME type (e.g. 'image/jpeg', 'audio/aac').
    String? mimeType,

    /// Original filename.
    String? fileName,

    /// File size in bytes.
    int? sizeBytes,

    /// Image/video width in pixels.
    int? width,

    /// Image/video height in pixels.
    int? height,

    /// BlurHash placeholder string for progressive image loading.
    @Default('') String blurhash,

    /// Voice note / video duration in milliseconds.
    int? durationMs,

    /// Base64-encoded encryption key for this media blob.
    @Default('') String encryptionKeyB64,

    /// SHA-256 hash of the ciphertext blob.
    @Default('') String contentHash,

    /// SHA-256 hash of the plaintext.
    @Default('') String plaintextHash,

    /// Display sort order within a message (for multi-image).
    @Default(0) int sortOrder,

    /// Whether the media has expired on the relay and is no longer downloadable.
    @Default(false) bool isExpired,

    required DateTime createdAt,
  }) = _MediaAttachment;

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      _$MediaAttachmentFromJson(json);
}
