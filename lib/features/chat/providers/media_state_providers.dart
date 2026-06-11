import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_heal_providers.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_available_provider.dart';

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

/// Removes the in-memory decrypted-bytes entry for [mediaId], if present.
///
/// Call this when a record is repointed away from [mediaId] (e.g. "replace
/// image") so a stale plaintext bitmap for the old, now-orphaned blob doesn't
/// linger in the session cache.
void evictMediaCache(String mediaId) {
  _imageMemoryCache.remove(mediaId);
}

final mediaFileProvider = FutureProvider.autoDispose
    .family<Uint8List?, MediaFileParams>((ref, params) async {
      // Repaint when background hydration pulls *this* blob into the cache.
      // A first resolve that returned null (placeholder) re-runs and now finds
      // the freshly-downloaded `.enc` file. The listener is torn down with the
      // provider (autoDispose), so off-screen images stop listening for free.
      ref.listen(mediaAvailableProvider, (previous, next) {
        if (next.value?.mediaId == params.mediaId) {
          ref.invalidateSelf();
        }
      });

      // Return from memory cache if available — no disk read or decryption needed.
      final cached = _imageMemoryCache[params.mediaId];
      if (cached != null) return cached;

      final manager = ref.watch(downloadManagerProvider);
      final encryptionKey = Uint8List.fromList(
        base64Decode(params.encryptionKeyB64),
      );
      final result = await manager.getMedia(
        mediaId: params.mediaId,
        encryptionKey: encryptionKey,
        ciphertextHash: params.ciphertextHash,
        plaintextHash: params.plaintextHash,
      );

      // A local decrypt / integrity failure surfaces as the provider's error
      // state (callers render a generic error) — re-fetching can't fix a local
      // key/integrity fault. Everything else — the relay no longer holds it
      // (TTL expiry), a transient transport failure, a missing blob — is
      // "unavailable": return `null` so callers render the graceful expired/
      // placeholder state (e.g. BioImageWidget's "Image expired"). The media heal
      // request for a missing blob is wired in a follow-up.
      if (result is! MediaFetchOk) {
        if (result.isDecryptFailure) {
          throw StateError('media integrity failure: ${params.mediaId}');
        }
        // On-view miss for a referenced blob: nudge the media heal (it confirms via
        // batch-exists + requests a re-supply, gated by cooldown). When a peer
        // re-supplies it, the mediaAvailable listener above re-resolves this
        // provider. Best-effort — never let the heal break the placeholder
        // render (e.g. if the requester's deps aren't available).
        try {
          unawaited(
            ref
                .read(mediaHealRequesterProvider)
                .onReferencedAbsent(
                  params.mediaId,
                  // TODO(media-heal follow-up): heal member/profile images at
                  // priorityProfile. The priority mechanism (cooldown ordering)
                  // is built + tested, but threading the role through
                  // MediaFileParams is deferred; all on-view heals currently use
                  // chat priority. The heal still works for profile images.
                  priority: MissingMediaDao.priorityChat,
                  // A relay-confirmed 404 forces the heal past the batch-exists
                  // gate (the committed-but-fileless repair case).
                  fromNotFound: result.isNotFound,
                )
                .catchError((_) {}),
          );
        } catch (_) {}
        return null;
      }
      final bytes = result.bytes;

      // The blob is present — clear any stale missing-media entry from a prior
      // on-view miss. This success path emits no MediaAvailableEvent, so the media heal
      // reactor wouldn't otherwise drop it. Best-effort; idempotent.
      try {
        unawaited(
          ref
              .read(mediaHealRequesterProvider)
              .markResolved(params.mediaId)
              .catchError((_) {}),
        );
      } catch (_) {}

      // Evict oldest entry when at capacity (FIFO).
      if (_imageMemoryCache.length >= _maxImageCacheEntries) {
        _imageMemoryCache.remove(_imageMemoryCache.keys.first);
      }
      _imageMemoryCache[params.mediaId] = bytes;

      return bytes;
    });
