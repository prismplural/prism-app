// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_attachment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MediaAttachment _$MediaAttachmentFromJson(Map<String, dynamic> json) =>
    _MediaAttachment(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      mediaId: json['mediaId'] as String,
      mediaType: json['mediaType'] as String,
      encryptionKeyB64: json['encryptionKeyB64'] as String,
      contentHash: json['contentHash'] as String,
      plaintextHash: json['plaintextHash'] as String,
      mimeType: json['mimeType'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      durationMs: (json['durationMs'] as num).toInt(),
      blurhash: json['blurhash'] as String,
      waveformB64: json['waveformB64'] as String,
      thumbnailMediaId: json['thumbnailMediaId'] as String,
      sourceUrl: json['sourceUrl'] as String,
      previewUrl: json['previewUrl'] as String,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );

Map<String, dynamic> _$MediaAttachmentToJson(_MediaAttachment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'messageId': instance.messageId,
      'mediaId': instance.mediaId,
      'mediaType': instance.mediaType,
      'encryptionKeyB64': instance.encryptionKeyB64,
      'contentHash': instance.contentHash,
      'plaintextHash': instance.plaintextHash,
      'mimeType': instance.mimeType,
      'sizeBytes': instance.sizeBytes,
      'width': instance.width,
      'height': instance.height,
      'durationMs': instance.durationMs,
      'blurhash': instance.blurhash,
      'waveformB64': instance.waveformB64,
      'thumbnailMediaId': instance.thumbnailMediaId,
      'sourceUrl': instance.sourceUrl,
      'previewUrl': instance.previewUrl,
      'isDeleted': instance.isDeleted,
    };
