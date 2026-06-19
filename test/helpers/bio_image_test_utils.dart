import 'dart:typed_data';

import 'package:drift/native.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';

class TestBioImageInfra {
  TestBioImageInfra._({
    required this.database,
    required this.uploadQueue,
    required this.downloadManager,
    required this.mediaService,
  });

  final AppDatabase database;
  final UploadQueue uploadQueue;
  final DownloadManager downloadManager;
  final MediaService mediaService;

  factory TestBioImageInfra.create() {
    final database = AppDatabase(NativeDatabase.memory());
    final encryption = MediaEncryptionService();
    final uploadQueue = UploadQueue(
      dao: database.uploadQueueDao,
      upload:
          ({
            required mediaId,
            required contentHash,
            required data,
            ttlSecs,
          }) async => UploadAttemptResult.ok,
      resumeOnStart: false,
    );
    final downloadManager = DownloadManager(
      handle: null,
      encryption: encryption,
    );
    return TestBioImageInfra._(
      database: database,
      uploadQueue: uploadQueue,
      downloadManager: downloadManager,
      mediaService: MediaService(
        compression: ImageCompressionService(),
        encryption: encryption,
        uploadQueue: uploadQueue,
        downloadManager: downloadManager,
      ),
    );
  }

  Future<void> close() async {
    uploadQueue.dispose();
    downloadManager.dispose();
    await database.close();
  }
}

StagedBioImage testStagedBioImage({
  String mediaId = 'media-staged',
  String tag = 'staged-image',
}) {
  return StagedBioImage(
    mediaId: mediaId,
    tag: tag,
    prepared: MediaAttachmentData(
      mediaId: mediaId,
      thumbnailMediaId: '',
      encryptedImage: Uint8List.fromList(const [1]),
      encryptedThumbnail: Uint8List(0),
      encryptionKey: Uint8List.fromList(const [2]),
      contentHash: 'content-hash',
      plaintextHash: 'plaintext-hash',
      thumbnailContentHash: '',
      thumbnailPlaintextHash: '',
      width: 1,
      height: 1,
      sizeBytes: 1,
      blurhash: '',
      mimeType: 'image/png',
    ),
    decryptedBytes: Uint8List.fromList(const [3]),
  );
}
