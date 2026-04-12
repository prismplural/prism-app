import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/services/media/media_encryption_service.dart';

enum DownloadState { idle, downloading, decrypting, completed, failed }

class DownloadProgress {
  final String mediaId;
  final DownloadState state;
  final String? error;

  const DownloadProgress({
    required this.mediaId,
    required this.state,
    this.error,
  });
}

class DownloadManager {
  DownloadManager({
    required this.handle,
    required this.encryption,
  });

  final ffi.PrismSyncHandle? handle;
  final MediaEncryptionService encryption;

  Future<Directory>? _cacheDirFuture;

  static const _maxConcurrent = 4;
  int _activeDownloads = 0;
  final List<Completer<void>> _waiters = [];
  final Map<String, StreamController<DownloadProgress>> _progressControllers =
      {};

  Stream<DownloadProgress> progressStream(String mediaId) {
    _progressControllers[mediaId] ??=
        StreamController<DownloadProgress>.broadcast();
    return _progressControllers[mediaId]!.stream;
  }

  Future<Uint8List?> getMedia({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
    String fileExtension = '',
  }) async {
    final cacheFile = await _cacheFileFor(mediaId, fileExtension);
    if (cacheFile.existsSync()) {
      _emitProgress(mediaId, DownloadState.completed);
      return cacheFile.readAsBytes();
    }

    await _acquireSlot();
    try {
      _emitProgress(mediaId, DownloadState.downloading);

      if (handle == null) {
        throw StateError('Sync handle not available');
      }

      final ciphertext = await ffi
          .downloadMedia(
            handle: handle!,
            mediaId: mediaId,
          )
          .timeout(const Duration(seconds: 30));

      _emitProgress(mediaId, DownloadState.decrypting);

      final plaintext = await encryption.decryptMedia(
        ciphertext: ciphertext,
        key: encryptionKey,
        expectedCiphertextHash: ciphertextHash,
        expectedPlaintextHash: plaintextHash,
      );

      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(plaintext);

      _emitProgress(mediaId, DownloadState.completed);
      return plaintext;
    } catch (e) {
      _emitProgress(mediaId, DownloadState.failed, error: e.toString());
      return null;
    } finally {
      _releaseSlot();
    }
  }

  Future<File?> getMediaFile({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
  }) async {
    // Audio files need a .m4a extension so iOS AVPlayer can detect the format.
    // Android's ExoPlayer does byte-header detection and doesn't need it, but
    // using an extension is correct on both platforms.
    const ext = '.m4a';
    final bytes = await getMedia(
      mediaId: mediaId,
      encryptionKey: encryptionKey,
      ciphertextHash: ciphertextHash,
      plaintextHash: plaintextHash,
      fileExtension: ext,
    );
    if (bytes == null) return null;

    return _cacheFileFor(mediaId, ext);
  }

  Future<void> clearCache() async {
    final dir = await _cacheDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> cacheSize() async {
    final dir = await _cacheDir();
    if (!dir.existsSync()) return 0;

    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> _acquireSlot() async {
    if (_activeDownloads < _maxConcurrent) {
      _activeDownloads++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _activeDownloads++;
  }

  void _releaseSlot() {
    _activeDownloads--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  void _emitProgress(String mediaId, DownloadState state, {String? error}) {
    final controller = _progressControllers[mediaId];
    if (controller != null && !controller.isClosed) {
      controller.add(DownloadProgress(
        mediaId: mediaId,
        state: state,
        error: error,
      ));
    }
  }

  Future<Directory> _cacheDir() {
    return _cacheDirFuture ??= _resolveCacheDir();
  }

  Future<Directory> _resolveCacheDir() async {
    // Use applicationSupportDirectory (not cacheDir) so iOS applies
    // NSFileProtectionCompleteUntilFirstUserAuthentication and the media
    // files are excluded from unencrypted iTunes/Finder backups.
    final cacheBase = await getApplicationSupportDirectory();
    return Directory('${cacheBase.path}/prism_media');
  }

  Future<File> _cacheFileFor(String mediaId, [String fileExtension = '']) async {
    final dir = await _cacheDir();
    return File('${dir.path}/$mediaId$fileExtension');
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
