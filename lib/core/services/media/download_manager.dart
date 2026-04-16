import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/services/backup_exclusion.dart';
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

/// Typedef for the FFI download function. Allows injection in tests without
/// hitting the real flutter_rust_bridge native layer.
typedef DownloadMediaFn =
    Future<Uint8List> Function({
      required ffi.PrismSyncHandle handle,
      required String mediaId,
    });

class DownloadManager {
  DownloadManager({
    required this.handle,
    required this.encryption,
    Directory? cacheDirOverride,
    DownloadMediaFn? downloadMediaFn,
  }) : _cacheDirOverride = cacheDirOverride,
       _downloadMediaFn = downloadMediaFn ?? _defaultDownloadMediaFn;

  final ffi.PrismSyncHandle? handle;
  final MediaEncryptionService encryption;

  /// Optional override for the cache directory; used in tests to avoid
  /// requiring the path_provider platform channel.
  final Directory? _cacheDirOverride;

  /// Injectable download function; defaults to [ffi.downloadMedia].
  /// Swap out in tests to avoid hitting the real FFI layer.
  final DownloadMediaFn _downloadMediaFn;

  static Future<Uint8List> _defaultDownloadMediaFn({
    required ffi.PrismSyncHandle handle,
    required String mediaId,
  }) {
    return ffi.downloadMedia(handle: handle, mediaId: mediaId);
  }

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
    // 1. Check encrypted cache (.enc file). If it exists, decrypt and return.
    final encFile = await _cacheFileFor(
      mediaId,
      fileExtension: fileExtension,
      encrypted: true,
    );
    if (encFile.existsSync()) {
      _emitProgress(mediaId, DownloadState.decrypting);
      final ciphertext = encFile.readAsBytesSync();
      return _decryptMedia(
        ciphertext: ciphertext,
        key: encryptionKey,
        ciphertextHash: ciphertextHash,
        plaintextHash: plaintextHash,
      );
    }

    // 2. Delete old plaintext cache if present. Security invariant: we never
    //    serve plaintext from disk — always re-download as ciphertext instead.
    final plainFile = await _cacheFileFor(
      mediaId,
      fileExtension: fileExtension,
      encrypted: false,
    );
    if (plainFile.existsSync()) {
      await plainFile.delete();
    }

    await _acquireSlot();
    try {
      _emitProgress(mediaId, DownloadState.downloading);

      if (handle == null) {
        throw StateError('Sync handle not available');
      }

      final ciphertext = await _downloadMediaFn(
        handle: handle!,
        mediaId: mediaId,
      ).timeout(const Duration(seconds: 30));

      _emitProgress(mediaId, DownloadState.decrypting);

      final plaintext = await _decryptMedia(
        ciphertext: ciphertext,
        key: encryptionKey,
        ciphertextHash: ciphertextHash,
        plaintextHash: plaintextHash,
      );

      // Cache ciphertext, NOT plaintext. Plaintext lives only in memory.
      await encFile.parent.create(recursive: true);
      await encFile.writeAsBytes(ciphertext);

      _emitProgress(mediaId, DownloadState.completed);
      return plaintext;
    } catch (e) {
      _emitProgress(mediaId, DownloadState.failed, error: e.toString());
      return null;
    } finally {
      _releaseSlot();
    }
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
    // ignore: close_sinks
    final controller = _progressControllers[mediaId];
    if (controller != null && !controller.isClosed) {
      controller.add(
        DownloadProgress(mediaId: mediaId, state: state, error: error),
      );
    }
  }

  Future<Directory> _cacheDir() {
    if (_cacheDirOverride != null) {
      return Future.value(_cacheDirOverride);
    }
    return _cacheDirFuture ??= _resolveCacheDir();
  }

  Future<Directory> _resolveCacheDir() async {
    // Use applicationSupportDirectory (not cacheDir) so iOS applies
    // NSFileProtectionCompleteUntilFirstUserAuthentication and the media
    // files are excluded from unencrypted iTunes/Finder backups.
    final cacheBase = await getApplicationSupportDirectory();
    final dir = Directory('${cacheBase.path}/prism_media');
    await excludeFromiCloudBackup(dir.path);
    return dir;
  }

  Future<File> _cacheFileFor(
    String mediaId, {
    String fileExtension = '',
    bool encrypted = false,
  }) async {
    final dir = await _cacheDir();
    final suffix = encrypted ? '.enc' : '';
    return File('${dir.path}/$mediaId$fileExtension$suffix');
  }

  /// Decrypts [ciphertext] using [MediaEncryptionService].
  ///
  /// NOTE: [MediaEncryptionService.decryptMedia] calls [ffi.decryptXchacha]
  /// via flutter_rust_bridge (FRB). FRB manages its own Dart isolate and does
  /// NOT support being called from a [compute()] isolate — doing so causes a
  /// "Cannot use native extensions from an isolate not spawned by the VM"
  /// error. Therefore, decryption runs directly on the main isolate. For
  /// typical media sizes this is fast enough (XChaCha20-Poly1305 is ~1 GB/s
  /// on modern hardware) and keeps the code correct.
  Future<Uint8List> _decryptMedia({
    required Uint8List ciphertext,
    required Uint8List key,
    required String ciphertextHash,
    required String plaintextHash,
  }) async {
    return encryption.decryptMedia(
      ciphertext: ciphertext,
      key: key,
      expectedCiphertextHash: ciphertextHash,
      expectedPlaintextHash: plaintextHash,
    );
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
