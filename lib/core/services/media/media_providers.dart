import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
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
  final handle = ref.watch(prismSyncHandleProvider).value;
  final queue = UploadQueue(handle: handle);
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
