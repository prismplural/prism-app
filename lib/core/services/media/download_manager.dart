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
  }) async {
    final cacheFile = await _cacheFileFor(mediaId);
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

      final ciphertext = await ffi.downloadMedia(
        handle: handle!,
        mediaId: mediaId,
      );

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
    final bytes = await getMedia(
      mediaId: mediaId,
      encryptionKey: encryptionKey,
      ciphertextHash: ciphertextHash,
      plaintextHash: plaintextHash,
    );
    if (bytes == null) return null;

    return _cacheFileFor(mediaId);
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
    final cacheBase = await getApplicationCacheDirectory();
    return Directory('${cacheBase.path}/prism_media');
  }

  Future<File> _cacheFileFor(String mediaId) async {
    final dir = await _cacheDir();
    return File('${dir.path}/$mediaId');
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
