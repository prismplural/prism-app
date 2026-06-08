import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:prism_plurality/core/database/app_database.dart'
    show UploadQueueEntry;
import 'package:prism_plurality/core/database/daos/upload_queue_dao.dart';

/// Result of a single upload attempt by [UploadQueue].
enum UploadAttemptResult {
  /// The blob was uploaded (committed/servable) — remove it from the queue.
  ok,

  /// Sync isn't configured (no relay handle). Depending on
  /// `completeLocallyWhenUnconfigured`, the queue either completes the entry
  /// locally (there are no peers to upload to) or treats it as a failure.
  unconfigured,
}

/// Performs one upload. Returns [UploadAttemptResult]; throws on a transient or
/// terminal upload error (the queue records the failure and retries/backs off).
/// Decoupled from the FFI handle type so the queue is unit-testable; the
/// production closure (built in the provider) captures the relay handle.
typedef UploadFn =
    Future<UploadAttemptResult> Function({
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

/// Durable, resumable media upload queue (durable media upload queue).
///
/// Replaces the old in-memory queue that dropped a send after 3 retries and
/// lost everything on app restart. Each enqueued blob is persisted (bytes and
/// all) in the encrypted app DB via [UploadQueueDao]; the queue drains pending
/// rows, uploading with exponential backoff. A successful (committed) upload
/// deletes the row; a blob that exhausts its retries moves to a retained
/// `terminal` state (never silently dropped) so it can be surfaced or retried.
/// On construction the queue resumes any rows left pending by a previous
/// session.
///
/// `onSuccess`/`onFailure` callbacks are best-effort and only fire for tasks
/// enqueued in the current process (callers that need to await a send use them);
/// rows resumed from a prior session upload fire-and-forget.
class UploadQueue {
  UploadQueue({
    required this.dao,
    required UploadFn upload,
    bool completeLocallyWhenUnconfigured = false,
    int maxAttempts = 8,
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    bool resumeOnStart = true,
  }) : _upload = upload,
       _completeLocallyWhenUnconfigured = completeLocallyWhenUnconfigured,
       _maxAttempts = maxAttempts,
       _baseBackoff = baseBackoff,
       _maxBackoff = maxBackoff {
    if (resumeOnStart) {
      // Pick up rows persisted by a previous session (or before this provider
      // was first watched). Fire-and-forget; errors are handled per-row.
      unawaited(_kick());
    }
  }

  final UploadQueueDao dao;
  final UploadFn _upload;
  final bool _completeLocallyWhenUnconfigured;
  final int _maxAttempts;
  final Duration _baseBackoff;
  final Duration _maxBackoff;

  final Map<String, StreamController<UploadProgress>> _progressControllers = {};
  // In-process completion callbacks, keyed by media id. Only set for tasks
  // enqueued this session.
  final Map<String, UploadTask> _pendingCallbacks = {};

  bool _draining = false;
  bool _disposed = false;
  Timer? _retryTimer;

  Stream<UploadProgress> progressStream(String mediaId) {
    _progressControllers[mediaId] ??=
        StreamController<UploadProgress>.broadcast();
    return _progressControllers[mediaId]!.stream;
  }

  /// Persist a blob to the queue and start draining. Idempotent on `mediaId`.
  Future<void> enqueue(UploadTask task) async {
    if (task.onSuccess != null || task.onFailure != null) {
      _pendingCallbacks[task.mediaId] = task;
    }
    await dao.upsert(
      mediaId: task.mediaId,
      contentHash: task.contentHash,
      ciphertext: task.encryptedData,
      ttlSecs: task.ttlSecs?.toInt(),
      createdAtMs: _nowMs(),
    );
    _emitProgress(task.mediaId, UploadState.pending);
    await _kick();
  }

  /// Trigger a drain if one isn't already running.
  Future<void> _kick() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      await _drainAllDue();
    } finally {
      _draining = false;
    }
    if (!_disposed) _scheduleNextRetry();
  }

  /// Upload every currently-due pending row, looping so rows enqueued during the
  /// pass are picked up before we yield.
  Future<void> _drainAllDue() async {
    while (!_disposed) {
      final due = await dao.duePending(_nowMs());
      if (due.isEmpty) return;
      for (final row in due) {
        if (_disposed) return;
        await _process(row);
      }
    }
  }

  Future<void> _process(UploadQueueEntry row) async {
    _emitProgress(row.mediaId, UploadState.uploading);
    try {
      final result = await _upload(
        mediaId: row.mediaId,
        contentHash: row.contentHash,
        data: row.ciphertext,
        ttlSecs: row.ttlSecs == null ? null : BigInt.from(row.ttlSecs!),
      );
      if (result == UploadAttemptResult.unconfigured) {
        if (_completeLocallyWhenUnconfigured) {
          // Sync isn't configured: no peers to upload to. Treat as done (the
          // sender keeps its own local copy) — matches pre-upload queue behavior.
          await dao.markCompleted(row.mediaId);
          _succeed(row.mediaId);
        } else {
          await _fail(row, 'Sync handle not available');
        }
        return;
      }
      await dao.markCompleted(row.mediaId);
      _succeed(row.mediaId);
    } catch (e) {
      await _fail(row, e.toString());
    }
  }

  void _succeed(String mediaId) {
    _emitProgress(mediaId, UploadState.completed);
    final task = _pendingCallbacks.remove(mediaId);
    task?.onSuccess?.call();
  }

  /// Record a failed attempt: schedule a backoff retry, or move to terminal
  /// once retries are exhausted (the row is retained, never dropped).
  Future<void> _fail(UploadQueueEntry row, String error) async {
    final attempts = row.attempts + 1;
    if (attempts >= _maxAttempts) {
      await dao.markTerminal(
        mediaId: row.mediaId,
        attempts: attempts,
        error: error,
      );
      _emitProgress(row.mediaId, UploadState.failed, error: error);
      final task = _pendingCallbacks.remove(row.mediaId);
      task?.onFailure?.call(error);
      return;
    }
    await dao.recordFailure(
      mediaId: row.mediaId,
      attempts: attempts,
      nextAttemptAtMs: _nowMs() + _backoffMs(attempts),
      error: error,
    );
  }

  /// Exponential backoff for the Nth attempt, capped at [_maxBackoff].
  int _backoffMs(int attempts) {
    final base = _baseBackoff.inMilliseconds;
    final cap = _maxBackoff.inMilliseconds;
    // attempts >= 1; first retry waits base, then doubles.
    final shift = math.min(attempts - 1, 30); // avoid overflow on 1<<n
    final delay = base * (1 << shift);
    return math.min(delay, cap);
  }

  /// Arm a single timer for the soonest future retry so we don't busy-poll.
  void _scheduleNextRetry() {
    unawaited(() async {
      final next = await dao.earliestFutureAttempt(_nowMs());
      if (next == null || _disposed) return;
      final delay = Duration(milliseconds: math.max(0, next - _nowMs()));
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () => unawaited(_kick()));
    }());
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

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
    _disposed = true;
    _retryTimer?.cancel();
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
    _pendingCallbacks.clear();
  }
}
