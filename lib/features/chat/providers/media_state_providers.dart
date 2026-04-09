import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';

typedef MediaFileParams = ({
  String mediaId,
  Uint8List encryptionKey,
  String ciphertextHash,
  String plaintextHash,
});

final uploadProgressProvider =
    StreamProvider.autoDispose.family<UploadProgress, String>(
  (ref, mediaId) {
    final queue = ref.watch(uploadQueueProvider);
    return queue.progressStream(mediaId);
  },
);

final downloadProgressProvider =
    StreamProvider.autoDispose.family<DownloadProgress, String>(
  (ref, mediaId) {
    final manager = ref.watch(downloadManagerProvider);
    return manager.progressStream(mediaId);
  },
);

final mediaFileProvider =
    FutureProvider.autoDispose.family<Uint8List?, MediaFileParams>(
  (ref, params) {
    final manager = ref.watch(downloadManagerProvider);
    return manager.getMedia(
      mediaId: params.mediaId,
      encryptionKey: params.encryptionKey,
      ciphertextHash: params.ciphertextHash,
      plaintextHash: params.plaintextHash,
    );
  },
);
