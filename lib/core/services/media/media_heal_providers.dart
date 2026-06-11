import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/media/ephemeral_signal.dart';
import 'package:prism_plurality/core/services/media/media_heal_requester.dart';
import 'package:prism_plurality/core/services/media/media_heal_responder.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/chat/providers/media_available_provider.dart';

/// Short TTL (seconds) for a re-supply upload — 48 h, longer than the pairing
/// snapshot's 24 h so slower media still catches up, and short enough that the
/// relay sheds the re-supplied blob quickly (the ephemerality goal).
const int kResupplyTtlSecs = 48 * 3600;

/// batch-exists via the current sync handle. Throws (no handle / old relay)
/// so callers treat "can't confirm" as a no-op rather than "all absent".
Future<List<String>> _batchExists(Ref ref, List<String> mediaIds) async {
  final handle = ref.read(prismSyncHandleProvider).value;
  if (handle == null) {
    throw StateError('sync handle unavailable for batch-exists');
  }
  return ffi.mediaExists(handle: handle, mediaIds: mediaIds);
}

/// The demand-driven heal's requester, wired to the live DB + relay + ephemeral lane.
/// `keepAlive` so the missing-media cadence state isn't rebuilt on every
/// transient sync-handle flip.
final mediaHealRequesterProvider = Provider<MediaHealRequester>((ref) {
  ref.keepAlive();
  final sender = ref.watch(ephemeralSignalSenderProvider);
  return MediaHealRequester(
    dao: ref.watch(databaseProvider).missingMediaDao,
    batchExists: (ids) => _batchExists(ref, ids),
    sendMediaRequest: (mediaId) =>
        sender.send(kind: mediaRequestKind, mediaId: mediaId),
  );
});

/// The demand-driven heal's responder, wired to the local cache + relay + ephemeral lane
/// lane. Re-uploads a held blob's cached ciphertext (short TTL, idempotent on
/// the relay) and announces `media_uploaded` only on a committed upload.
final mediaHealResponderProvider = Provider<MediaHealResponder>((ref) {
  ref.keepAlive();
  final downloadManager = ref.watch(downloadManagerProvider);
  final attachmentsDao = ref.watch(databaseProvider).mediaAttachmentsDao;
  final sender = ref.watch(ephemeralSignalSenderProvider);
  return MediaHealResponder(
    holdsBlob: downloadManager.isCached,
    batchExists: (ids) => _batchExists(ref, ids),
    reUpload: (mediaId) async {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) return ReUploadResult.failed;
      // Re-upload the exact cached ciphertext — no decrypt/re-encrypt; the
      // relay's idempotent upsert coalesces concurrent responders.
      final ciphertext = await downloadManager.readCachedCiphertext(mediaId);
      if (ciphertext == null) return ReUploadResult.failed; // raced out of cache
      // The request may target a thumbnail, which lives in `thumbnail_media_id`
      // on its parent row (no row of its own) — resolve by either id and pick
      // the matching ciphertext hash.
      final attachment = await attachmentsDao.getByAnyMediaId(mediaId);
      if (attachment == null) return ReUploadResult.failed;
      final contentHash = attachment.mediaId == mediaId
          ? attachment.contentHash
          : attachment.thumbnailContentHash;
      if (contentHash.isEmpty) return ReUploadResult.failed;
      final outcome = await ffi.uploadMedia(
        handle: handle,
        mediaId: mediaId,
        contentHash: contentHash,
        data: ciphertext,
        ttlSecs: BigInt.from(kResupplyTtlSecs),
        pairingPush: false,
      );
      if (outcome.committed) return ReUploadResult.committed;
      if (outcome.inProgress) return ReUploadResult.inProgress;
      return ReUploadResult.failed;
    },
    sendMediaUploaded: (mediaId) =>
        sender.send(kind: mediaUploadedKind, mediaId: mediaId),
  );
});

/// Run the heal cadence and re-download any blob it found back on the relay
/// (heal-completion). Shared by the per-pull reactor and the user-initiated
/// "Request Missing Media" action.
Future<void> runHealCadence(
  MediaHealRequester requester,
  MediaHydrator hydrator,
) async {
  final healed = await requester.runCadence();
  for (final mediaId in healed) {
    unawaited(hydrator.retry(mediaId));
  }
}

/// User-initiated "Request Missing Media": re-arm every entry (pending AND
/// terminal) for an immediate retry, then run the cadence now. Best-effort.
Future<void> requestAllMissingMedia({
  required MissingMediaDao dao,
  required MediaHealRequester requester,
  required MediaHydrator hydrator,
  required int nowMs,
}) async {
  await dao.requestAllNow(nowMs);
  await runHealCadence(requester, hydrator);
}

/// The media heal reactor — the live wiring that drives the heal loop. Inert until
/// activated (a `ref.watch`/`ref.listen` in `app.dart`); `keepAlive` so it
/// outlives transient widget rebuilds.
///
/// - A peer's `media_request` ⇒ the responder re-supplies the blob if held.
/// - A peer's `media_uploaded` ⇒ heal-completion: re-download the just-supplied
///   blob (emits `MediaAvailableEvent` → the UI refreshes).
/// - Each completed sync pull ⇒ the requester's cadence re-checks the
///   missing-media set (coalesced batch-exists; re-request / shed / terminal).
final mediaHealReactorProvider = Provider<void>((ref) {
  ref.keepAlive();

  ref.listen<AsyncValue<EphemeralMessage>>(ephemeralMessageStreamProvider, (
    _,
    next,
  ) {
    final msg = next.value;
    if (msg == null) return;
    // `.catchError` on each fire-and-forget: the responder's holds-check / send
    // and the hydrator's retry can throw (null handle, transient relay error),
    // and an unawaited throw would surface as an unhandled zone error.
    if (msg.kind == mediaRequestKind) {
      unawaited(
        ref
            .read(mediaHealResponderProvider)
            .onMediaRequest(msg.mediaId)
            .catchError((_) {}),
      );
    } else if (msg.kind == mediaUploadedKind) {
      unawaited(
        ref.read(mediaHydratorProvider).retry(msg.mediaId).catchError((_) {}),
      );
    }
  });

  // A blob that just landed in cache (a re-download succeeded) is no longer
  // missing — drop it from the set. Removal is **success-driven** (not
  // batch-exists-present-driven), so a flapping short-TTL re-supply can't reset
  // the entry's terminal clock / backoff.
  ref.listen<AsyncValue<MediaAvailableEvent>>(mediaAvailableProvider, (_, next) {
    final mediaId = next.value?.mediaId;
    if (mediaId != null) {
      unawaited(
        ref
            .read(databaseProvider)
            .missingMediaDao
            .remove(mediaId)
            .catchError((_) {}),
      );
    }
  });

  ref.listen<AsyncValue<SyncEvent>>(syncEventStreamProvider, (_, next) {
    final event = next.value;
    if (event != null && event.isSyncCompleted) {
      unawaited(
        runHealCadence(
          ref.read(mediaHealRequesterProvider),
          ref.read(mediaHydratorProvider),
        ).catchError((_) {}),
      );
    }
  });
});
