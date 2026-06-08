import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:prism_plurality/core/database/daos/upload_queue_dao.dart';

/// Result of a single upload attempt by [UploadQueue].
enum UploadAttemptResult {
  /// The blob was uploaded (committed/servable) — remove it from the queue.
  ok,

  /// Sync is *not configured at all* (no relay identity). With
  /// `completeLocallyWhenUnconfigured`, the queue completes the entry locally
  /// (there are no peers to upload to). NOTE: production must NOT return this
  /// for a merely-transient null handle (a configured-but-disconnected device)
  /// — that must throw, so the durable queue retries instead of dropping a send.
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

  /// Called once the blob is **durably enqueued** (persisted to the queue DB),
  /// not once it has uploaded. Because the queue is durable, a successful
  /// enqueue guarantees the blob will eventually be delivered, so callers that
  /// `await` a send (e.g. `uploadBioImageOrThrow`) can return as soon as it's
  /// queued rather than blocking on the full upload + retry schedule.
  final void Function()? onSuccess;

  /// Called only if the blob could not be **enqueued** (a DB write error).
  /// Upload-time failures are handled by the queue's retry/terminal logic, not
  /// surfaced here.
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
/// `terminal` tombstone (metadata kept, bytes dropped — never silently lost).
/// On construction the queue resumes any rows left pending by a previous
/// session.
///
/// The owning provider must keep a SINGLE long-lived instance (not rebuild it
/// when the sync handle changes), so the handle is read lazily inside the
/// injected [UploadFn] rather than captured at construction. A transient null
/// handle must make that closure THROW (so the queue retries), never report
/// `unconfigured` (which drops the send).
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

  bool _draining = false;
  // Set when a kick arrives mid-drain; the active drain loops once more so a row
  // enqueued just after the last `duePending` snapshot is never stranded.
  bool _kickPending = false;
  bool _disposed = false;
  Timer? _retryTimer;

  Stream<UploadProgress> progressStream(String mediaId) {
    _progressControllers[mediaId] ??=
        StreamController<UploadProgress>.broadcast();
    return _progressControllers[mediaId]!.stream;
  }

  /// Persist a blob to the queue and start draining. Idempotent on `mediaId`.
  ///
  /// `onSuccess` fires here, on durable enqueue (the durability guarantee is
  /// what the caller actually needs); the upload then proceeds in the
  /// background with retry. `onFailure` fires only if the enqueue itself fails.
  Future<void> enqueue(UploadTask task) async {
    try {
      await dao.upsert(
        mediaId: task.mediaId,
        contentHash: task.contentHash,
        ciphertext: task.encryptedData,
        ttlSecs: task.ttlSecs?.toInt(),
        createdAtMs: _nowMs(),
      );
    } catch (e) {
      task.onFailure?.call(e.toString());
      rethrow;
    }
    _emitProgress(task.mediaId, UploadState.pending);
    task.onSuccess?.call();
    // Fire-and-forget: the durable row is persisted, so the caller's `await
    // enqueue(...)` returns now; the upload (and any retries) proceed in the
    // background. Awaiting the drain here would re-block the caller on the full
    // upload + backoff schedule, defeating the durability guarantee.
    unawaited(_kick());
  }

  /// Trigger a drain if one isn't already running. Always called via
  /// `unawaited(...)`, so it must never let an error escape to the zone.
  Future<void> _kick() async {
    if (_disposed) return;
    if (_draining) {
      // A drain is in progress; signal it to loop once more rather than no-op,
      // so a row enqueued just after the last snapshot isn't left undrained.
      _kickPending = true;
      return;
    }
    _draining = true;
    try {
      do {
        _kickPending = false;
        await _drainAllDue();
      } while (_kickPending && !_disposed);
    } catch (_) {
      // Contain unexpected DB/drain errors (per-row upload errors are already
      // handled in _process). The drain is restarted by the next enqueue or
      // retry-timer kick, so a transient failure self-heals.
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

  Future<void> _process(UploadQueueDue row) async {
    // Load the bytes for just this row, immediately before upload, so a backlog
    // never materialises every blob in memory at once.
    final ciphertext = await dao.loadCiphertext(row.mediaId);
    if (ciphertext == null) {
      // Row vanished (completed/reaped concurrently) — nothing to do.
      return;
    }

    _emitProgress(row.mediaId, UploadState.uploading);
    try {
      final result = await _upload(
        mediaId: row.mediaId,
        contentHash: row.contentHash,
        data: ciphertext,
        ttlSecs: row.ttlSecs == null ? null : BigInt.from(row.ttlSecs!),
      );
      if (_disposed) return; // a newer instance owns the DB now
      if (result == UploadAttemptResult.unconfigured) {
        if (_completeLocallyWhenUnconfigured) {
          // Sync is genuinely not configured: no peers to upload to. Treat as
          // done (the sender keeps its own local copy).
          await dao.markCompleted(row.mediaId);
          _emitProgress(row.mediaId, UploadState.completed);
        } else {
          await _fail(row, 'Sync not configured');
        }
        return;
      }
      await dao.markCompleted(row.mediaId);
      _emitProgress(row.mediaId, UploadState.completed);
    } catch (e) {
      if (_disposed) return;
      await _fail(row, e.toString());
    }
  }

  /// Record a failed attempt: schedule a backoff retry, or move to a terminal
  /// tombstone once retries are exhausted (metadata retained, bytes dropped).
  Future<void> _fail(UploadQueueDue row, String error) async {
    final attempts = row.attempts + 1;
    if (attempts >= _maxAttempts) {
      await dao.markTerminal(
        mediaId: row.mediaId,
        attempts: attempts,
        error: error,
      );
      _emitProgress(row.mediaId, UploadState.failed, error: error);
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
    final controller = _progressControllers[mediaId];
    if (controller == null || controller.isClosed) return;
    controller.add(UploadProgress(mediaId: mediaId, state: state, error: error));
    // Free the controller once the upload reaches a terminal state. The queue is
    // a long-lived singleton (dispose ~never runs in normal use), so without
    // this the map would grow one controller per distinct media id ever streamed
    // (e.g. every image scrolled past in chat). A late subscriber to a finished
    // upload gets a fresh empty stream, which is correct — the blob is done.
    if (state == UploadState.completed || state == UploadState.failed) {
      _progressControllers.remove(mediaId);
      controller.close();
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
