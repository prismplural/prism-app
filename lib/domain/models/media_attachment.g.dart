// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_attachment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MediaAttachment _$MediaAttachmentFromJson(Map<String, dynamic> json) =>
    _MediaAttachment(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      mediaType: json['mediaType'] as String,
      mediaId: json['mediaId'] as String,
      mimeType: json['mimeType'] as String?,
      fileName: json['fileName'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      blurhash: json['blurhash'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt(),
      encryptionKeyB64: json['encryptionKeyB64'] as String? ?? '',
      contentHash: json['contentHash'] as String? ?? '',
      plaintextHash: json['plaintextHash'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isExpired: json['isExpired'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$MediaAttachmentToJson(_MediaAttachment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'messageId': instance.messageId,
      'mediaType': instance.mediaType,
      'mediaId': instance.mediaId,
      'mimeType': instance.mimeType,
      'fileName': instance.fileName,
      'sizeBytes': instance.sizeBytes,
      'width': instance.width,
      'height': instance.height,
      'blurhash': instance.blurhash,
      'durationMs': instance.durationMs,
      'encryptionKeyB64': instance.encryptionKeyB64,
      'contentHash': instance.contentHash,
      'plaintextHash': instance.plaintextHash,
      'sortOrder': instance.sortOrder,
      'isExpired': instance.isExpired,
      'createdAt': instance.createdAt.toIso8601String(),
    };
