import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
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
  final handleAsync = ref.watch(prismSyncHandleProvider);
  final queue = UploadQueue(
    handle: handleAsync.value,
    handleFuture: ref.watch(prismSyncHandleProvider.future),
    completeLocallyWhenUnconfigured: true,
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
