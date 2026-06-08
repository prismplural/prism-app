import 'dart:async';
import 'dart:typed_data';

import 'package:prism_sync/generated/api.dart' as ffi;

typedef UploadMediaFn =
    Future<void> Function({
      required ffi.PrismSyncHandle handle,
      required String mediaId,
      required String contentHash,
      required Uint8List data,
      BigInt? ttlSecs,
    });

enum UploadState { pending, uploading, completed, failed }

class UploadProgress {
  final String mediaId;
  final UploadState state;
  final String? error;

  const UploadProgress({
    required this.mediaId,
    required this.state,
    this.error,
  });
}

class UploadTask {
  final String mediaId;
  final String contentHash;
  final Uint8List encryptedData;
  final void Function()? onSuccess;
  final void Function(String error)? onFailure;

  /// Optional per-blob TTL (seconds) for the relay's short-TTL upload variant
  /// (re-supply / pairing push). `null` ⇒ fresh send ⇒ the relay's default
  /// retention. The relay clamps the value; an old relay ignores it.
  final BigInt? ttlSecs;

  const UploadTask({
    required this.mediaId,
    required this.contentHash,
    required this.encryptedData,
    this.onSuccess,
    this.onFailure,
    this.ttlSecs,
  });
}

class UploadQueue {
  UploadQueue({
    required this.handle,
    Future<ffi.PrismSyncHandle?>? handleFuture,
    bool completeLocallyWhenUnconfigured = false,
    UploadMediaFn? uploadMediaFn,
  }) : _handleFuture = handleFuture,
       _completeLocallyWhenUnconfigured = completeLocallyWhenUnconfigured,
       _uploadMediaFn = uploadMediaFn ?? _defaultUploadMediaFn;

  final ffi.PrismSyncHandle? handle;
  final Future<ffi.PrismSyncHandle?>? _handleFuture;
  final bool _completeLocallyWhenUnconfigured;
  final UploadMediaFn _uploadMediaFn;
  final List<UploadTask> _queue = [];
  bool _processing = false;
  final Map<String, StreamController<UploadProgress>> _progressControllers = {};

  Stream<UploadProgress> progressStream(String mediaId) {
    _progressControllers[mediaId] ??=
        StreamController<UploadProgress>.broadcast();
    return _progressControllers[mediaId]!.stream;
  }

  Future<void> enqueue(UploadTask task) async {
    _queue.add(task);
    _emitProgress(task.mediaId, UploadState.pending);
    if (!_processing) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeAt(0);
        await _uploadSingle(task);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _uploadSingle(UploadTask task) async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 1);

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        _emitProgress(task.mediaId, UploadState.uploading);

        final resolvedHandle = await _resolveHandle();
        if (resolvedHandle == null) {
          if (_completeLocallyWhenUnconfigured) {
            _emitProgress(task.mediaId, UploadState.completed);
            task.onSuccess?.call();
            return;
          }
          throw StateError('Sync handle not available');
        }

        await _uploadMediaFn(
          handle: resolvedHandle,
          mediaId: task.mediaId,
          contentHash: task.contentHash,
          data: task.encryptedData,
          ttlSecs: task.ttlSecs,
        );

        _emitProgress(task.mediaId, UploadState.completed);
        task.onSuccess?.call();
        return;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          _emitProgress(task.mediaId, UploadState.failed, error: e.toString());
          task.onFailure?.call(e.toString());
          return;
        }
        await Future<void>.delayed(baseDelay * (1 << attempt));
      }
    }
  }

  Future<ffi.PrismSyncHandle?> _resolveHandle() {
    final currentHandle = handle;
    if (currentHandle != null) {
      return Future.value(currentHandle);
    }
    return _handleFuture ?? Future.value(null);
  }

  static Future<void> _defaultUploadMediaFn({
    required ffi.PrismSyncHandle handle,
    required String mediaId,
    required String contentHash,
    required Uint8List data,
    BigInt? ttlSecs,
  }) async {
    // Fresh sends ignore the outcome (a brand-new media_id never returns a 202
    // in-progress). The committed/in-progress distinction is consumed by the media heal's
    // re-supply responder, not this queue.
    await ffi.uploadMedia(
      handle: handle,
      mediaId: mediaId,
      contentHash: contentHash,
      data: data,
      ttlSecs: ttlSecs,
    );
  }

  void _emitProgress(String mediaId, UploadState state, {String? error}) {
    // ignore: close_sinks
    final controller = _progressControllers[mediaId];
    if (controller != null && !controller.isClosed) {
      controller.add(
        UploadProgress(mediaId: mediaId, state: state, error: error),
      );
    }
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
