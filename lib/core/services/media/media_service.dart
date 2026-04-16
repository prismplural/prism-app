import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';

class MediaAttachmentData {
  final String mediaId;
  final String thumbnailMediaId;
  final Uint8List encryptedImage;
  final Uint8List encryptedThumbnail;
  final Uint8List encryptionKey;
  final String contentHash;
  final String plaintextHash;
  final String thumbnailContentHash;
  final int width;
  final int height;
  final int sizeBytes;
  final String blurhash;
  final String mimeType;

  const MediaAttachmentData({
    required this.mediaId,
    required this.thumbnailMediaId,
    required this.encryptedImage,
    required this.encryptedThumbnail,
    required this.encryptionKey,
    required this.contentHash,
    required this.plaintextHash,
    required this.thumbnailContentHash,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.blurhash,
    required this.mimeType,
  });
}

class VoiceAttachmentData {
  const VoiceAttachmentData({
    required this.mediaId,
    required this.encryptedAudio,
    required this.encryptionKey,
    required this.contentHash,
    required this.plaintextHash,
    required this.durationMs,
    required this.waveformB64,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String mediaId;
  final Uint8List encryptedAudio;
  final Uint8List encryptionKey;
  final String contentHash;
  final String plaintextHash;
  final int durationMs;
  final String waveformB64;
  final int sizeBytes;
  final String mimeType;
}

class MediaService {
  MediaService({
    required this.compression,
    required this.encryption,
    required this.uploadQueue,
    required this.downloadManager,
  });

  final ImageCompressionService compression;
  final MediaEncryptionService encryption;
  final UploadQueue uploadQueue;
  final DownloadManager downloadManager;

  static const _uuid = Uuid();

  Future<MediaAttachmentData> prepareImage(Uint8List imageBytes) async {
    final compressed = await compression.compressImage(imageBytes);
    final thumbnail = await compression.generateThumbnail(imageBytes);

    final encryptedImage = await encryption.encryptMedia(compressed.bytes);
    final encryptedThumbnail = await encryption.encryptMediaWithKey(
      thumbnail,
      encryptedImage.key,
    );

    final mediaId = _uuid.v4();
    final thumbnailMediaId = _uuid.v4();

    return MediaAttachmentData(
      mediaId: mediaId,
      thumbnailMediaId: thumbnailMediaId,
      encryptedImage: encryptedImage.ciphertext,
      encryptedThumbnail: encryptedThumbnail.ciphertext,
      encryptionKey: encryptedImage.key,
      contentHash: encryptedImage.ciphertextHash,
      plaintextHash: encryptedImage.plaintextHash,
      thumbnailContentHash: encryptedThumbnail.ciphertextHash,
      width: compressed.width,
      height: compressed.height,
      sizeBytes: compressed.bytes.length,
      blurhash: compressed.blurhash,
      mimeType: 'image/webp',
    );
  }

  Future<void> uploadPrepared(MediaAttachmentData data) async {
    await uploadQueue.enqueue(
      UploadTask(
        mediaId: data.mediaId,
        contentHash: data.contentHash,
        encryptedData: data.encryptedImage,
      ),
    );
    await uploadQueue.enqueue(
      UploadTask(
        mediaId: data.thumbnailMediaId,
        contentHash: data.thumbnailContentHash,
        encryptedData: data.encryptedThumbnail,
      ),
    );
  }

  Future<VoiceAttachmentData> prepareVoiceNote(
    Uint8List audioBytes,
    int durationMs,
    String waveformB64,
  ) async {
    final encrypted = await encryption.encryptMedia(audioBytes);
    final mediaId = _uuid.v4();

    return VoiceAttachmentData(
      mediaId: mediaId,
      encryptedAudio: encrypted.ciphertext,
      encryptionKey: encrypted.key,
      contentHash: encrypted.ciphertextHash,
      plaintextHash: encrypted.plaintextHash,
      durationMs: durationMs,
      waveformB64: waveformB64,
      sizeBytes: audioBytes.length,
      mimeType: 'audio/mp4',
    );
  }

  Future<void> uploadVoice(VoiceAttachmentData data) async {
    await uploadQueue.enqueue(
      UploadTask(
        mediaId: data.mediaId,
        contentHash: data.contentHash,
        encryptedData: data.encryptedAudio,
      ),
    );
  }

  /// Like [uploadPrepared] but throws [StateError] if either upload fails.
  /// Uses per-task Completers so it works whether the queue is idle or busy.
  Future<void> uploadPreparedOrThrow(MediaAttachmentData data) async {
    final imageCompleter = Completer<void>();
    final thumbCompleter = Completer<void>();

    await uploadQueue.enqueue(
      UploadTask(
        mediaId: data.mediaId,
        contentHash: data.contentHash,
        encryptedData: data.encryptedImage,
        onSuccess: imageCompleter.complete,
        onFailure: (e) => imageCompleter.completeError(StateError(e)),
      ),
    );
    await uploadQueue.enqueue(
      UploadTask(
        mediaId: data.thumbnailMediaId,
        contentHash: data.thumbnailContentHash,
        encryptedData: data.encryptedThumbnail,
        onSuccess: thumbCompleter.complete,
        onFailure: (e) => thumbCompleter.completeError(StateError(e)),
      ),
    );

    await imageCompleter.future;
    await thumbCompleter.future;
  }

  /// Like [uploadVoice] but throws [StateError] if the upload fails.
  Future<void> uploadVoiceOrThrow(VoiceAttachmentData data) async {
    final completer = Completer<void>();

    await uploadQueue.enqueue(
      UploadTask(
        mediaId: data.mediaId,
        contentHash: data.contentHash,
        encryptedData: data.encryptedAudio,
        onSuccess: completer.complete,
        onFailure: (e) => completer.completeError(StateError(e)),
      ),
    );

    await completer.future;
  }

  Future<Uint8List?> getMedia({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
  }) {
    return downloadManager.getMedia(
      mediaId: mediaId,
      encryptionKey: encryptionKey,
      ciphertextHash: ciphertextHash,
      plaintextHash: plaintextHash,
    );
  }

  Future<File?> getMediaFile({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
  }) {
    return downloadManager.getMediaFile(
      mediaId: mediaId,
      encryptionKey: encryptionKey,
      ciphertextHash: ciphertextHash,
      plaintextHash: plaintextHash,
    );
  }

  Stream<UploadProgress> uploadProgress(String mediaId) {
    return uploadQueue.progressStream(mediaId);
  }

  Stream<DownloadProgress> downloadProgress(String mediaId) {
    return downloadManager.progressStream(mediaId);
  }
}
