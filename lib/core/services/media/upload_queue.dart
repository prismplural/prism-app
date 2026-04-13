import 'dart:async';
import 'dart:typed_data';

import 'package:prism_sync/generated/api.dart' as ffi;

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

  const UploadTask({
    required this.mediaId,
    required this.contentHash,
    required this.encryptedData,
    this.onSuccess,
    this.onFailure,
  });
}

class UploadQueue {
  UploadQueue({required this.handle});

  final ffi.PrismSyncHandle? handle;
  final List<UploadTask> _queue = [];
  bool _processing = false;
  final Map<String, StreamController<UploadProgress>> _progressControllers = {};

  Stream<UploadProgress> progressStream(String mediaId) {
    _progressControllers[mediaId] ??= StreamController<UploadProgress>.broadcast();
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

        if (handle == null) {
          throw StateError('Sync handle not available');
        }

        await ffi.uploadMedia(
          handle: handle!,
          mediaId: task.mediaId,
          contentHash: task.contentHash,
          data: task.encryptedData,
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

  void _emitProgress(String mediaId, UploadState state, {String? error}) {
    final controller = _progressControllers[mediaId];
    if (controller != null && !controller.isClosed) {
      controller.add(UploadProgress(
        mediaId: mediaId,
        state: state,
        error: error,
      ));
    }
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
