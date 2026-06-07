import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';

/// Broadcast when the hydrator pulls a media blob into the local encrypted
/// cache. UI providers listen for this so a placeholder repaints with the
/// real image the moment its bytes land — without the user scrolling it back
/// into view.
class MediaAvailableEvent {
  const MediaAvailableEvent(this.mediaId);

  final String mediaId;
}

/// Eagerly downloads referenced media in the background so a freshly-paired or
/// reinstalled device caches all of its media, instead of showing blurhash
/// placeholders forever for anything it didn't send itself.
///
/// The queue is in-memory by design: the work list is derivable — every
/// non-deleted `media_attachments` row whose blob isn't in the on-disk `.enc`
/// cache — so a kill mid-hydration loses nothing; the next [enqueuePending]
/// walk reconstructs it. (The upload queue, whose intent-to-send isn't recorded
/// elsewhere, does need persistence; a download's intent is the synced row.)
///
/// Callers trigger [enqueuePending] on app start and after a sync batch applies
/// `media_attachments` rows. Re-walks are cheap — already-cached, in-flight, or
/// given-up ids are skipped via the in-memory dedup sets. A worker pool bounds
/// concurrency; [DownloadManager]'s own cap bounds relay pressure.
///
/// A null from [DownloadManager.getMedia] is a transient miss, retried with
/// jittered backoff up to [maxAttempts] then given up until the next launch; a
/// thrown error is an integrity failure that won't self-heal, so it's dropped.
class MediaHydrator {
  MediaHydrator({
    required MediaAttachmentsDao attachmentsDao,
    required DownloadManager downloadManager,
    int maxConcurrent = 3,
    int maxAttempts = 5,
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    void Function(Duration delay, void Function() run)? scheduleRetry,
    void Function(String message)? log,
    Random? random,
  })  : _attachmentsDao = attachmentsDao,
        _downloadManager = downloadManager,
        _maxConcurrent = maxConcurrent,
        _maxAttempts = maxAttempts,
        _baseBackoff = baseBackoff,
        _maxBackoff = maxBackoff,
        _scheduleRetryOverride = scheduleRetry,
        _log = log ?? _defaultLog,
        _random = random ?? Random();

  final MediaAttachmentsDao _attachmentsDao;
  final DownloadManager _downloadManager;
  final int _maxConcurrent;
  final int _maxAttempts;
  final Duration _baseBackoff;
  final Duration _maxBackoff;

  /// Test seam for scheduling a retry without a real timer. Default path uses
  /// a tracked [Timer] (see [_scheduleRetry]).
  final void Function(Duration delay, void Function() run)?
      _scheduleRetryOverride;
  final void Function(String message) _log;
  final Random _random;

  /// Pending retry timers, so [dispose] can cancel them instead of leaving
  /// them to fire (harmlessly, but as dangling timers) up to [_maxBackoff]
  /// later — which would also trip "Timer still pending" assertions in tests.
  final Set<Timer> _retryTimers = {};

  final _events = StreamController<MediaAvailableEvent>.broadcast();

  /// Media ids confirmed present in the local cache this session (either it
  /// was already cached, or we just downloaded it). Never re-enqueued.
  final Set<String> _cached = {};

  /// Media ids currently queued, in-flight, or waiting out a retry backoff.
  /// Kept populated across the whole lifecycle so a concurrent re-walk dedups.
  final Set<String> _inProgress = {};

  /// Media ids whose download exhausted retries (or was un-downloadable) this
  /// session. Skipped on re-walk; a fresh hydrator (next launch / handle
  /// change) clears this and tries again.
  final Set<String> _givenUp = {};

  final List<_HydrationTask> _queue = [];
  int _active = 0;
  bool _disposed = false;

  /// Emits once per media id whenever its blob lands in the local cache.
  Stream<MediaAvailableEvent> get events => _events.stream;

  /// Walk every non-deleted `media_attachments` row and enqueue a background
  /// download for any primary blob not already cached. Idempotent and cheap
  /// to call repeatedly. Never throws — failures are logged and swallowed so
  /// callers (startup hooks, the sync stream) can fire-and-forget.
  Future<void> enqueuePending() async {
    if (_disposed) return;
    final List<MediaAttachment> rows;
    try {
      rows = await _attachmentsDao.getAll();
    } catch (e) {
      _log('MediaHydrator.enqueuePending: failed to load rows (non-fatal): $e');
      return;
    }
    for (final row in rows) {
      enqueueIfMissing(
        mediaId: row.mediaId,
        encryptionKeyB64: row.encryptionKeyB64,
        contentHash: row.contentHash,
        plaintextHash: row.plaintextHash,
      );
    }
  }

  /// Schedule a background download for a single primary blob, unless it is
  /// already cached, already being worked on, or already given up on this
  /// session. Rows lacking the fields needed to download (e.g. a "sending"
  /// placeholder with an empty media id, or a thumbnail-only reference) are
  /// silently skipped — thumbnails carry no synced content/plaintext hash, so
  /// they remain blurhash placeholders until the full image is opened, same
  /// as before.
  void enqueueIfMissing({
    required String mediaId,
    required String encryptionKeyB64,
    required String contentHash,
    required String plaintextHash,
  }) {
    if (_disposed) return;
    if (mediaId.isEmpty ||
        encryptionKeyB64.isEmpty ||
        contentHash.isEmpty ||
        plaintextHash.isEmpty) {
      return;
    }
    if (_cached.contains(mediaId) ||
        _inProgress.contains(mediaId) ||
        _givenUp.contains(mediaId)) {
      return;
    }

    // Reserve the id immediately (synchronously) so a re-walk that races the
    // async cache check below can't double-enqueue it.
    _inProgress.add(mediaId);
    unawaited(
      _scheduleIfReallyMissing(
        _HydrationTask(
          mediaId: mediaId,
          encryptionKeyB64: encryptionKeyB64,
          contentHash: contentHash,
          plaintextHash: plaintextHash,
        ),
      ),
    );
  }

  Future<void> _scheduleIfReallyMissing(_HydrationTask task) async {
    bool cached;
    try {
      cached = await _downloadManager.isCached(task.mediaId);
    } catch (_) {
      cached = false;
    }
    if (_disposed) {
      _inProgress.remove(task.mediaId);
      return;
    }
    if (cached) {
      _inProgress.remove(task.mediaId);
      _cached.add(task.mediaId);
      return;
    }
    _queue.add(task);
    _pump();
  }

  void _pump() {
    while (!_disposed && _active < _maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _active++;
      unawaited(
        _process(task).whenComplete(() {
          _active--;
          _pump();
        }),
      );
    }
  }

  Future<void> _process(_HydrationTask task) async {
    if (_disposed) return;

    Uint8List key;
    try {
      key = Uint8List.fromList(base64Decode(task.encryptionKeyB64));
    } catch (e) {
      _log('MediaHydrator: ${task.mediaId} has an undecodable key; skipping');
      _finishGivenUp(task.mediaId);
      return;
    }

    Uint8List? bytes;
    try {
      bytes = await _downloadManager.getMedia(
        mediaId: task.mediaId,
        encryptionKey: key,
        ciphertextHash: task.contentHash,
        plaintextHash: task.plaintextHash,
      );
    } catch (e) {
      // Decrypt / integrity failure — getMedia only throws for these, and they
      // will not resolve on retry. Drop it.
      _log('MediaHydrator: ${task.mediaId} failed integrity check; dropping: $e');
      _finishGivenUp(task.mediaId);
      return;
    }
    if (_disposed) return;

    if (bytes != null) {
      _inProgress.remove(task.mediaId);
      _cached.add(task.mediaId);
      if (!_events.isClosed) {
        _events.add(MediaAvailableEvent(task.mediaId));
      }
      return;
    }

    // null == transient miss. Retry with backoff, or give up after the cap.
    final nextAttempt = task.attempt + 1;
    if (nextAttempt >= _maxAttempts) {
      _log(
        'MediaHydrator: ${task.mediaId} unavailable after $_maxAttempts '
        'attempts; will retry on next launch',
      );
      _finishGivenUp(task.mediaId);
      return;
    }

    // The id stays in `_inProgress` across the wait so a concurrent re-walk
    // keeps deduping it. Release the worker slot now (we return) and re-queue
    // after the backoff.
    _scheduleRetry(task, nextAttempt);
  }

  void _scheduleRetry(_HydrationTask task, int nextAttempt) {
    final backoff = _backoffFor(nextAttempt);
    final override = _scheduleRetryOverride;
    if (override != null) {
      override(backoff, () => _runRetry(task, nextAttempt));
      return;
    }
    late final Timer timer;
    timer = Timer(backoff, () {
      _retryTimers.remove(timer);
      _runRetry(task, nextAttempt);
    });
    _retryTimers.add(timer);
  }

  void _runRetry(_HydrationTask task, int nextAttempt) {
    if (_disposed) return;
    // If it was completed or given up by another path, don't requeue.
    if (!_inProgress.contains(task.mediaId)) return;
    _queue.add(task.withAttempt(nextAttempt));
    _pump();
  }

  void _finishGivenUp(String mediaId) {
    _inProgress.remove(mediaId);
    _givenUp.add(mediaId);
  }

  Duration _backoffFor(int attempt) {
    // Jitter so a fresh pair's many simultaneous misses don't retry in lockstep.
    final exp = _baseBackoff.inMilliseconds * (1 << (attempt - 1));
    final capped = exp.clamp(0, _maxBackoff.inMilliseconds).toInt();
    final jitter = _random.nextInt(1000);
    return Duration(milliseconds: capped + jitter);
  }

  void dispose() {
    _disposed = true;
    for (final timer in _retryTimers) {
      timer.cancel();
    }
    _retryTimers.clear();
    _queue.clear();
    _inProgress.clear();
    if (!_events.isClosed) {
      _events.close();
    }
  }

  static void _defaultLog(String message) {
    ErrorReportingService.instance.report(
      message,
      severity: ErrorSeverity.info,
    );
  }
}

class _HydrationTask {
  const _HydrationTask({
    required this.mediaId,
    required this.encryptionKeyB64,
    required this.contentHash,
    required this.plaintextHash,
    this.attempt = 0,
  });

  final String mediaId;
  final String encryptionKeyB64;
  final String contentHash;
  final String plaintextHash;
  final int attempt;

  _HydrationTask withAttempt(int attempt) => _HydrationTask(
        mediaId: mediaId,
        encryptionKeyB64: encryptionKeyB64,
        contentHash: contentHash,
        plaintextHash: plaintextHash,
        attempt: attempt,
      );
}
