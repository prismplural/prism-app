import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_heal_providers.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';

final imageCompressionServiceProvider = Provider<ImageCompressionService>(
  (ref) => ImageCompressionService(),
);

final mediaEncryptionServiceProvider = Provider<MediaEncryptionService>(
  (ref) => MediaEncryptionService(),
);

final uploadQueueProvider = Provider<UploadQueue>((ref) {
  // ONE long-lived worker. Crucially it does NOT watch the sync handle: that
  // handle flips to null intermittently (the documented iOS "Sync disconnected"
  // blip), and rebuilding the queue on every flip would dispose it mid-upload —
  // double-sending rows and stranding awaited sends. keepAlive + lazy handle
  // read keeps a single stable instance.
  ref.keepAlive();
  final queue = UploadQueue(
    dao: ref.watch(databaseProvider).uploadQueueDao,
    upload: ({
      required String mediaId,
      required String contentHash,
      required Uint8List data,
      BigInt? ttlSecs,
    }) async {
      // Resolve the handle lazily, per attempt, from the CURRENT value only —
      // never `await`-ing the handle future. Awaiting it would park the single
      // drain loop (with `_draining` held) behind a still-loading handle and
      // strand every other due upload. A null/loading handle instead THROWS, so
      // the durable queue records a failure, backs off, and re-reads the value
      // on the next attempt — it never drops a configured user's send.
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        throw StateError('sync handle unavailable; will retry');
      }
      // Fresh sends ignore the outcome (a brand-new media_id never returns a
      // 202 in-progress); the committed/in-progress distinction is for media heal.
      await ffi.uploadMedia(
        handle: handle,
        mediaId: mediaId,
        contentHash: contentHash,
        data: data,
        ttlSecs: ttlSecs,
      );
      return UploadAttemptResult.ok;
    },
  );
  ref.onDispose(queue.dispose);
  return queue;
});

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final handle = ref.watch(prismSyncHandleProvider).value;
  final encryption = ref.watch(mediaEncryptionServiceProvider);
  final manager = DownloadManager(handle: handle, encryption: encryption);
  ref.onDispose(manager.dispose);
  return manager;
});

final mediaServiceProvider = Provider<MediaService>((ref) {
  return MediaService(
    compression: ref.watch(imageCompressionServiceProvider),
    encryption: ref.watch(mediaEncryptionServiceProvider),
    uploadQueue: ref.watch(uploadQueueProvider),
    downloadManager: ref.watch(downloadManagerProvider),
  );
});

/// Background eager-hydration service. Rebuilt whenever the download manager is
/// (i.e. when the sync handle changes), which is desirable: a freshly-paired
/// device gets a hydrator wired to a working handle, and its dedup state
/// starts clean so the post-bootstrap walk re-attempts anything a prior
/// handle-less hydrator gave up on.
final mediaHydratorProvider = Provider<MediaHydrator>((ref) {
  final db = ref.watch(databaseProvider);
  final downloadManager = ref.watch(downloadManagerProvider);
  final hydrator = MediaHydrator(
    attachmentsDao: db.mediaAttachmentsDao,
    downloadManager: downloadManager,
    // On give-up (the relay confirms a referenced blob missing, or retries
    // exhaust), hand off to the media heal: confirm via batch-exists and request a
    // re-supply. Fire-and-forget; the requester gates + coalesces. The hydrator
    // walks attachments uniformly, so it heals at chat priority — profile-
    // priority heals come from the on-view UI path.
    onReferencedAbsent: (mediaId) {
      unawaited(
        ref
            .read(mediaHealRequesterProvider)
            .onReferencedAbsent(mediaId, priority: MissingMediaDao.priorityChat)
            // Never let a transient heal failure surface as an unhandled async
            // error (the send/batch-exists paths already no-op internally).
            .catchError((_) {}),
      );
    },
  );
  ref.onDispose(hydrator.dispose);
  return hydrator;
});

/// Startup / fallback entry point for eager hydration, mirroring the orphan-
/// and bio-media reconcilers' `run…FromRef` wrappers. Resolves the
/// [MediaHydrator] and kicks off a background walk of every referenced blob
/// that isn't already cached.
///
/// This is the on-load fallback. The pairing-snapshot and live-sync paths
/// hydrate via the post-batch trigger in `syncEventStreamProvider`; this covers
/// the case with no fresh pairing and no inbound batch — an already-paired
/// device whose cache is incomplete (cache cleared, a prior hydration was
/// interrupted, or rows synced on a previous launch but their blobs were never
/// pulled) still fetches the missing blobs on next launch.
///
/// Self-swallowing: never throws into the caller (startup must not fail because
/// of media hydration). [MediaHydrator.enqueuePending] already swallows its own
/// load/query errors; this guard only catches a failure to resolve the provider
/// (e.g. the database not being ready yet).
Future<void> runMediaHydrationFromRef(WidgetRef ref) async {
  try {
    await ref.read(mediaHydratorProvider).enqueuePending();
  } catch (e) {
    ErrorReportingService.instance.report(
      'Media hydration startup walk failed to resolve dependencies '
      '(non-fatal): $e',
      severity: ErrorSeverity.info,
    );
  }
}
