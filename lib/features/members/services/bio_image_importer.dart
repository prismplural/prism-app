import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

/// Processes external image URLs in imported bios (e.g. from Simply Plural),
/// fetching and encrypting each into the shared image library and rewriting
/// the markdown to reference the library by tag.
///
/// `![alt](https://host/img.png#200x150)` becomes `![alt](img-ab12cd34#200x150)`
/// — the `#WxH` sizing fragment is preserved so ported layouts stay intact.
///
/// Create one instance per import run so identical URLs (shared across many
/// members) dedupe to a single library entry.
class BioImageImporter {
  BioImageImporter({
    required MediaService mediaService,
    required DriftMediaAttachmentRepository repository,
  })  : _mediaService = mediaService,
        _repository = repository;

  final MediaService _mediaService;
  final DriftMediaAttachmentRepository _repository;

  static const _uuid = Uuid();
  static const _maxBytesPerImage = 5 * 1024 * 1024;

  // url → tag, populated as images are imported so repeats reuse one entry.
  final Map<String, String> _urlToTag = {};

  /// Matches `![alt](url)` where url starts with http:// or https://.
  /// Captures: 1=alt, 2=full url (may include #fragment).
  static final _imagePattern =
      RegExp(r'!\[([^\]]*)\]\((https?://[^)\s]+)\)');

  int get importedCount => _urlToTag.length;

  /// Process a single bio, returning the rewritten markdown. External image
  /// URLs are fetched, encrypted into the library, and replaced with tags.
  /// URLs that fail to fetch are left untouched (will render as missing).
  Future<String> processBio(String? bio) async {
    if (bio == null || bio.isEmpty) return bio ?? '';
    if (!bio.contains('http')) return bio;

    final matches = _imagePattern.allMatches(bio).toList();
    if (matches.isEmpty) return bio;

    var result = bio;

    for (final match in matches) {
      final alt = match.group(1) ?? '';
      final fullUrl = match.group(2)!;

      // Split off any #WxH sizing fragment so it survives the rewrite.
      final hashIdx = fullUrl.indexOf('#');
      final url = hashIdx >= 0 ? fullUrl.substring(0, hashIdx) : fullUrl;
      final fragment = hashIdx >= 0 ? fullUrl.substring(hashIdx) : '';

      final tag = await _importUrl(url);
      if (tag == null) continue; // fetch failed — leave the original URL

      result = result.replaceFirst(
        match.group(0)!,
        '![$alt]($tag$fragment)',
      );
    }

    return result;
  }

  /// Fetch + encrypt + store one URL, returning its library tag (or null on
  /// failure). Deduplicates by URL within this import run.
  Future<String?> _importUrl(String url) async {
    final cached = _urlToTag[url];
    if (cached != null) return cached;

    try {
      final bytes = await fetchRemoteImageBytes(url, maxBytes: _maxBytesPerImage);
      if (bytes == null) return null;

      final prepared = await _mediaService.prepareBioImage(bytes);
      if (prepared.sizeBytes > _maxBytesPerImage) return null;

      // Dedup by plaintext hash too — same image at different URLs.
      final existing = await _repository.getForMember('');
      final dup = existing
          .where((a) => a.plaintextHash == prepared.plaintextHash && a.tag.isNotEmpty)
          .toList();
      if (dup.isNotEmpty) {
        _urlToTag[url] = dup.first.tag;
        return dup.first.tag;
      }

      await _mediaService.uploadBioImage(prepared);

      final tag = 'img-${_uuid.v4().substring(0, 8)}';
      await _repository.create(MediaAttachment(
        id: _uuid.v4(),
        memberId: '',
        messageId: '',
        tag: tag,
        mediaId: prepared.mediaId,
        mediaType: 'image',
        encryptionKeyB64: base64Encode(prepared.encryptionKey),
        contentHash: prepared.contentHash,
        plaintextHash: prepared.plaintextHash,
        mimeType: prepared.mimeType,
        sizeBytes: prepared.sizeBytes,
        width: prepared.width,
        height: prepared.height,
        durationMs: 0,
        blurhash: prepared.blurhash,
        waveformB64: '',
        thumbnailMediaId: '',
        sourceUrl: url, // keep original for backup/export
        previewUrl: '',
      ));

      _urlToTag[url] = tag;
      return tag;
    } catch (e) {
      debugPrint('[BioImageImporter] failed to import $url: $e');
      return null;
    }
  }
}
