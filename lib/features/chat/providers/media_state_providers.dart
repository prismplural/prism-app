import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';

typedef MediaFileParams = ({
  String mediaId,
  String encryptionKeyB64,
  String ciphertextHash,
  String plaintextHash,
});

final uploadProgressProvider = StreamProvider.autoDispose
    .family<UploadProgress, String>((ref, mediaId) {
      final queue = ref.watch(uploadQueueProvider);
      return queue.progressStream(mediaId);
    });

final downloadProgressProvider = StreamProvider.autoDispose
    .family<DownloadProgress, String>((ref, mediaId) {
      final manager = ref.watch(downloadManagerProvider);
      return manager.progressStream(mediaId);
    });

// ── Image in-memory cache ─────────────────────────────────────────────────────
//
// [mediaFileProvider] is autoDispose.family, so Riverpod evicts a provider
// instance when no widget is watching it (e.g. when a message scrolls off
// screen). Without this cache, scrolling back into view triggers a fresh
// .enc-file read + decrypt cycle on every rebuild.
//
// The cache stores decrypted [Uint8List] keyed by mediaId. It is module-level
// (lives for the app session) and is bounded to [_maxImageCacheEntries] to
// prevent unbounded memory growth. Eviction uses a simple FIFO policy — the
// oldest inserted entry is removed when the limit is reached.
//
// The cache is keyed only by mediaId (not by the full [MediaFileParams]) on
// the assumption that a given mediaId always corresponds to the same plaintext
// content. If a media item is updated its mediaId changes.
const _maxImageCacheEntries = 50;
final _imageMemoryCache = <String, Uint8List>{};

final mediaFileProvider = FutureProvider.autoDispose
    .family<Uint8List?, MediaFileParams>((ref, params) async {
      // Return from memory cache if available — no disk read or decryption needed.
      final cached = _imageMemoryCache[params.mediaId];
      if (cached != null) return cached;

      final manager = ref.watch(downloadManagerProvider);
      final encryptionKey = Uint8List.fromList(
        base64Decode(params.encryptionKeyB64),
      );
      final bytes = await manager.getMedia(
        mediaId: params.mediaId,
        encryptionKey: encryptionKey,
        ciphertextHash: params.ciphertextHash,
        plaintextHash: params.plaintextHash,
      );

      if (bytes == null) {
        throw StateError('Failed to download media: ${params.mediaId}');
      }

      // Evict oldest entry when at capacity (FIFO).
      if (_imageMemoryCache.length >= _maxImageCacheEntries) {
        _imageMemoryCache.remove(_imageMemoryCache.keys.first);
      }
      _imageMemoryCache[params.mediaId] = bytes;

      return bytes;
    });

/// Returns decrypted voice-note bytes in memory so playback never needs to
/// write plaintext audio to disk.
final mediaAudioBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, MediaFileParams>((ref, params) {
      final manager = ref.watch(downloadManagerProvider);
      final encryptionKey = Uint8List.fromList(
        base64Decode(params.encryptionKeyB64),
      );
      return manager.getMedia(
        mediaId: params.mediaId,
        encryptionKey: encryptionKey,
        ciphertextHash: params.ciphertextHash,
        plaintextHash: params.plaintextHash,
      );
    });
