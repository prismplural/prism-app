import 'dart:convert';
import 'dart:io';
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
    final encryptionKey = Uint8List.fromList(base64Decode(params.encryptionKeyB64));
    return manager.getMedia(
      mediaId: params.mediaId,
      encryptionKey: encryptionKey,
      ciphertextHash: params.ciphertextHash,
      plaintextHash: params.plaintextHash,
    );
  },
);

/// Returns a decrypted audio [File] on disk, suitable for [AudioSource.file].
/// Unlike [mediaFileProvider] which returns raw bytes, this returns the cached
/// file path so just_audio can stream from it directly.
final mediaAudioFileProvider =
    FutureProvider.autoDispose.family<File?, MediaFileParams>(
  (ref, params) {
    final manager = ref.watch(downloadManagerProvider);
    final encryptionKey =
        Uint8List.fromList(base64Decode(params.encryptionKeyB64));
    return manager.getMediaFile(
      mediaId: params.mediaId,
      encryptionKey: encryptionKey,
      ciphertextHash: params.ciphertextHash,
      plaintextHash: params.plaintextHash,
    );
  },
);
