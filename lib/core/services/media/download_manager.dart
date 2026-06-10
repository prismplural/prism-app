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
/// hitting the real flutter_rust_bridge native layer. Returns the FFI's typed
/// [ffi.MediaDownloadOutcome] (`bytes` xor `error`).
typedef DownloadMediaFn =
    Future<ffi.MediaDownloadOutcome> Function({
      required ffi.PrismSyncHandle handle,
      required String mediaId,
    });

/// The typed outcome of [DownloadManager.getMedia] (media heal). The
/// heal acts on the failure [MediaFetchFailure.kind]: `notFound` (or a
/// persistent transport failure) ⇒ request a re-supply; `decrypt` ⇒ a local
/// integrity error that won't self-heal ⇒ drop, never request.
sealed class MediaFetchResult {
  const MediaFetchResult();
}

class MediaFetchOk extends MediaFetchResult {
  const MediaFetchOk(this.bytes);
  final Uint8List bytes;
}

class MediaFetchFailure extends MediaFetchResult {
  const MediaFetchFailure(this.kind);
  final ffi.MediaFetchErrorKind kind;
}

extension MediaFetchResultX on MediaFetchResult {
  /// The decoded bytes, or `null` for any failure.
  Uint8List? get bytesOrNull =>
      this is MediaFetchOk ? (this as MediaFetchOk).bytes : null;

  /// A local decrypt / integrity failure — won't self-heal on retry, so callers
  /// drop the blob rather than re-requesting it.
  bool get isDecryptFailure =>
      this is MediaFetchFailure &&
      (this as MediaFetchFailure).kind == ffi.MediaFetchErrorKind.decrypt;

  /// The relay reported the blob missing — the heal's request trigger.
  bool get isNotFound =>
      this is MediaFetchFailure &&
      (this as MediaFetchFailure).kind == ffi.MediaFetchErrorKind.notFound;
}

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

  static Future<ffi.MediaDownloadOutcome> _defaultDownloadMediaFn({
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

  /// Fetch + decrypt the blob for [mediaId], returning a typed
  /// [MediaFetchResult]. Total — it never throws; every failure path returns a
  /// [MediaFetchFailure] with the relevant kind so the media heal can act on it
  /// (a `decrypt`/integrity failure is local and won't self-heal; a `notFound`
  /// or persistent transport failure is a re-supply trigger).
  Future<MediaFetchResult> getMedia({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
    String fileExtension = '',
  }) async {
    try {
      // 1. Encrypted cache (.enc) hit: decrypt and return.
      final encFile = await _cacheFileFor(
        mediaId,
        fileExtension: fileExtension,
        encrypted: true,
      );
      if (encFile.existsSync()) {
        _emitProgress(mediaId, DownloadState.decrypting);
        final ciphertext = encFile.readAsBytesSync();
        try {
          final plaintext = await _decryptMedia(
            ciphertext: ciphertext,
            key: encryptionKey,
            ciphertextHash: ciphertextHash,
            plaintextHash: plaintextHash,
          );
          return MediaFetchOk(plaintext);
        } catch (e) {
          _emitProgress(mediaId, DownloadState.failed, error: e.toString());
          return const MediaFetchFailure(ffi.MediaFetchErrorKind.decrypt);
        }
      }

      // 2. Delete old plaintext cache if present. Security invariant: we never
      //    serve plaintext from disk — always re-download as ciphertext.
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
          _emitProgress(mediaId, DownloadState.failed, error: 'no sync handle');
          return const MediaFetchFailure(ffi.MediaFetchErrorKind.other);
        }

        final ffi.MediaDownloadOutcome outcome;
        try {
          outcome = await _downloadMediaFn(
            handle: handle!,
            mediaId: mediaId,
          ).timeout(const Duration(seconds: 30));
        } on TimeoutException {
          _emitProgress(mediaId, DownloadState.failed, error: 'timeout');
          return const MediaFetchFailure(ffi.MediaFetchErrorKind.timeout);
        }

        final ciphertext = outcome.bytes;
        if (ciphertext == null) {
          final kind = outcome.error ?? ffi.MediaFetchErrorKind.other;
          _emitProgress(mediaId, DownloadState.failed, error: '$kind');
          return MediaFetchFailure(kind);
        }

        _emitProgress(mediaId, DownloadState.decrypting);
        final Uint8List plaintext;
        try {
          plaintext = await _decryptMedia(
            ciphertext: ciphertext,
            key: encryptionKey,
            ciphertextHash: ciphertextHash,
            plaintextHash: plaintextHash,
          );
        } catch (e) {
          // A freshly-downloaded blob that fails to decrypt is most likely
          // corrupt/truncated bytes from the relay (transient) — treat it as
          // RETRYABLE (`server`), not a terminal `decrypt`. A genuine local
          // key/integrity fault re-surfaces on the cache-hit path (which IS
          // terminal). This restores the pre-media heal retry behaviour for a bad
          // download while keeping a cached-but-corrupt blob terminal.
          _emitProgress(mediaId, DownloadState.failed, error: e.toString());
          return const MediaFetchFailure(ffi.MediaFetchErrorKind.server);
        }

        // Cache ciphertext, NOT plaintext. Plaintext lives only in memory.
        await encFile.parent.create(recursive: true);
        await encFile.writeAsBytes(ciphertext);

        _emitProgress(mediaId, DownloadState.completed);
        return MediaFetchOk(plaintext);
      } finally {
        _releaseSlot();
      }
    } catch (e) {
      // Defensive: an unexpected error (e.g. cache I/O) is a generic failure,
      // never a crash out of this total method.
      _emitProgress(mediaId, DownloadState.failed, error: e.toString());
      return const MediaFetchFailure(ffi.MediaFetchErrorKind.other);
    }
  }

  /// Whether the encrypted blob for [mediaId] is already present in the local
  /// `.enc` cache. Lets background hydration skip a needless download + decrypt
  /// for media that's already on disk, using the exact same path resolution
  /// (including the test cache-dir override) that [getMedia] uses.
  Future<bool> isCached(String mediaId, {String fileExtension = ''}) async {
    final encFile = await _cacheFileFor(
      mediaId,
      fileExtension: fileExtension,
      encrypted: true,
    );
    return encFile.existsSync();
  }

  /// The locally-cached **encrypted** bytes for [mediaId] (the `<mediaId>.enc`
  /// file), or `null` if it isn't cached. The media heal responder uses this to
  /// re-supply a blob it holds — re-uploading the exact cached ciphertext
  /// (idempotent on the relay) without decrypting/re-encrypting.
  Future<Uint8List?> readCachedCiphertext(
    String mediaId, {
    String fileExtension = '',
  }) async {
    final encFile = await _cacheFileFor(
      mediaId,
      fileExtension: fileExtension,
      encrypted: true,
    );
    if (!encFile.existsSync()) return null;
    return encFile.readAsBytes();
  }

  /// Pre-caches [ciphertext] locally so that a subsequent [getMedia] call
  /// for [mediaId] can decrypt from disk without hitting the relay.
  /// Used after encrypting a locally-created media item (voice note, image)
  /// so the sender can play it back immediately.
  Future<void> cacheEncrypted({
    required String mediaId,
    required Uint8List ciphertext,
    String fileExtension = '',
  }) async {
    final encFile = await _cacheFileFor(
      mediaId,
      fileExtension: fileExtension,
      encrypted: true,
    );
    await encFile.parent.create(recursive: true);
    await encFile.writeAsBytes(ciphertext);
  }

  /// Evicts the locally-cached encrypted blob for [mediaId] (the
  /// `<mediaId>.enc` file, plus any stale plaintext file). Best-effort: a
  /// missing file or transient I/O error is ignored.
  ///
  /// Used when a record is repointed to a new mediaId (e.g. "replace image")
  /// so the now-orphaned old blob doesn't linger in the local cache. The
  /// startup orphan-media reconciler would eventually catch it, but this
  /// reclaims the space immediately.
  Future<void> evictEncrypted(
    String mediaId, {
    String fileExtension = '',
  }) async {
    try {
      final encFile = await _cacheFileFor(
        mediaId,
        fileExtension: fileExtension,
        encrypted: true,
      );
      if (encFile.existsSync()) await encFile.delete();
      final plainFile = await _cacheFileFor(
        mediaId,
        fileExtension: fileExtension,
        encrypted: false,
      );
      if (plainFile.existsSync()) await plainFile.delete();
    } catch (_) {
      // Best-effort cache hygiene — never throw from eviction.
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
