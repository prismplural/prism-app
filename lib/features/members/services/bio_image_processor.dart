import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

// ── Result / error types ─────────────────────────────────────────────────────

class BioImageProcessResult {
  final String rewrittenMarkdown;
  final int processedCount;
  final List<BioImageError> errors;

  const BioImageProcessResult({
    required this.rewrittenMarkdown,
    required this.processedCount,
    required this.errors,
  });
}

class BioImageError {
  final String url;
  final String message;

  const BioImageError({required this.url, required this.message});
}

// ── Staged image ─────────────────────────────────────────────────────────────

/// An image that has been prepared (compressed + encrypted + cached locally)
/// but not yet uploaded to the relay or committed as a CRDT record.
class StagedBioImage {
  final String mediaId;
  final String tag;
  final MediaAttachmentData prepared;
  final Uint8List decryptedBytes;
  final String? sourceUrl;
  final String? altText;

  const StagedBioImage({
    required this.mediaId,
    required this.tag,
    required this.prepared,
    required this.decryptedBytes,
    this.sourceUrl,
    this.altText,
  });
}

// ── Processor ────────────────────────────────────────────────────────────────

class BioImageProcessor {
  final MediaService _mediaService;
  final DriftMediaAttachmentRepository _repository;

  static const _maxBytesPerImage = 5 * 1024 * 1024; // 5 MB
  static const _uuid = Uuid();

  /// Images prepared during editing but not yet committed.
  final List<StagedBioImage> staged = [];

  BioImageProcessor({
    required MediaService mediaService,
    required DriftMediaAttachmentRepository repository,
  })  : _mediaService = mediaService,
        _repository = repository;

  /// Upload a device-picked image to the library with a user-defined tag.
  /// Stages locally — not uploaded until [commitStaged].
  /// Returns the tag (for insertion into markdown as `![alt](tag)`).
  Future<String> stageDeviceImage(
    Uint8List bytes,
    String tag, {
    String? altText,
  }) async {
    final normalizedTag = normalizeTag(tag);
    if (normalizedTag.isEmpty) {
      throw StateError('Tag cannot be empty');
    }

    // Check for tag conflicts with existing library images.
    final existing = await _repository.getForMember(''); // Library images have no member
    final tagExists = existing.any((a) => a.tag == normalizedTag) ||
        staged.any((s) => s.tag == normalizedTag);
    if (tagExists) {
      throw StateError('Tag "$normalizedTag" is already in use');
    }

    final prepared = await _mediaService.prepareBioImage(bytes);

    if (prepared.sizeBytes > _maxBytesPerImage) {
      throw StateError(
        'Image too large (max ${_maxBytesPerImage ~/ (1024 * 1024)} MB)',
      );
    }

    staged.add(StagedBioImage(
      mediaId: prepared.mediaId,
      tag: normalizedTag,
      prepared: prepared,
      decryptedBytes: bytes,
      altText: altText,
    ));

    return normalizedTag;
  }

  /// Upload a URL-fetched image to the library with a user-defined tag.
  /// Stages locally — not uploaded until [commitStaged].
  Future<String> stageUrlImage(
    String url,
    String tag, {
    String? altText,
  }) async {
    final normalizedTag = normalizeTag(tag);
    if (normalizedTag.isEmpty) {
      throw StateError('Tag cannot be empty');
    }

    final bytes = await fetchRemoteImageBytes(url, maxBytes: _maxBytesPerImage);
    if (bytes == null) {
      throw StateError('Could not fetch image from URL');
    }

    final prepared = await _mediaService.prepareBioImage(bytes);

    if (prepared.sizeBytes > _maxBytesPerImage) {
      throw StateError(
        'Image too large (max ${_maxBytesPerImage ~/ (1024 * 1024)} MB)',
      );
    }

    staged.add(StagedBioImage(
      mediaId: prepared.mediaId,
      tag: normalizedTag,
      prepared: prepared,
      decryptedBytes: bytes,
      sourceUrl: url,
      altText: altText,
    ));

    return normalizedTag;
  }

  /// Upload and create CRDT records for all staged images.
  /// Library images have no member_id — they're shared across all members.
  ///
  /// Returns the tags of any images that failed to commit (upload/create
  /// error). The `![](tag)` refs were already inserted into the text, so a
  /// non-empty result means those refs will render as missing until/unless a
  /// later edit re-stages them — callers should surface that to the user
  /// (without blocking the save).
  Future<List<String>> commitStaged() async {
    final failedTags = <String>[];
    for (final image in staged) {
      try {
        await _mediaService.uploadBioImage(image.prepared);

        final attachmentId = _uuid.v4();
        await _repository.create(MediaAttachment(
          id: attachmentId,
          memberId: '',
          messageId: '',
          tag: image.tag,
          mediaId: image.mediaId,
          mediaType: 'image',
          encryptionKeyB64: base64Encode(image.prepared.encryptionKey),
          contentHash: image.prepared.contentHash,
          plaintextHash: image.prepared.plaintextHash,
          mimeType: image.prepared.mimeType,
          sizeBytes: image.prepared.sizeBytes,
          width: image.prepared.width,
          height: image.prepared.height,
          durationMs: 0,
          blurhash: image.prepared.blurhash,
          waveformB64: '',
          thumbnailMediaId: '',
          sourceUrl: image.sourceUrl ?? '',
          previewUrl: '',
        ));
      } catch (e) {
        debugPrint('[BioImageProcessor] failed to commit staged image '
            '${image.tag}: $e');
        failedTags.add(image.tag);
      }
    }
    staged.clear();
    return failedTags;
  }

  /// Discard all staged images without uploading.
  void discardStaged() {
    staged.clear();
  }

  /// Look up decrypted bytes for a staged image by mediaId.
  Uint8List? getStagedBytes(String mediaId) {
    for (final image in staged) {
      if (image.mediaId == mediaId) return image.decryptedBytes;
    }
    return null;
  }

  /// Look up decrypted bytes for a staged image by tag.
  Uint8List? getStagedByTag(String tag) {
    for (final image in staged) {
      if (image.tag == tag) return image.decryptedBytes;
    }
    return null;
  }

  /// Normalize a tag: lowercase, strip whitespace, replace spaces with hyphens,
  /// remove non-alphanumeric chars except hyphens and underscores.
  ///
  /// Critical for correctness, not just tidiness: a tag containing `)` or `#`
  /// breaks `![](tag)` parsing so every reference silently stops resolving.
  /// Every entry point that writes a tag must run it through here.
  static String normalizeTag(String tag) {
    return tag
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  }
}
