import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/upload_queue_dao.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';

/// Records every upload attempt and lets a test script the per-call outcome.
class _RecordingUpload {
  final List<({String mediaId, BigInt? ttl})> calls = [];

  /// `behavior(callIndex)` returns the result for that attempt, or throws to
  /// simulate an upload error. Defaults to always-ok.
  final UploadAttemptResult Function(int callIndex)? behavior;

  _RecordingUpload({this.behavior});

  UploadFn get fn => ({
    required String mediaId,
    required String contentHash,
    required Uint8List data,
    BigInt? ttlSecs,
  }) async {
    final idx = calls.length;
    calls.add((mediaId: mediaId, ttl: ttlSecs));
    if (behavior != null) return behavior!(idx);
    return UploadAttemptResult.ok;
  };
}

UploadQueueDao _memDao() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db.uploadQueueDao;
}

Uint8List _bytes([int n = 8]) =>
    Uint8List.fromList(List<int>.generate(n, (i) => i & 0xff));

void main() {
  group('UploadTask / UploadProgress', () {
    test('UploadTask stores fields incl. optional ttlSecs', () {
      final task = UploadTask(
        mediaId: 'm',
        contentHash: 'h',
        encryptedData: _bytes(),
        ttlSecs: BigInt.from(172800),
      );
      expect(task.mediaId, 'm');
      expect(task.ttlSecs, BigInt.from(172800));
      expect(task.onSuccess, isNull);
    });

    test('UploadProgress stores state + error', () {
      const p = UploadProgress(
        mediaId: 'm',
        state: UploadState.failed,
        error: 'boom',
      );
      expect(p.state, UploadState.failed);
      expect(p.error, 'boom');
    });
  });

  group('happy path', () {
    test('uploads on enqueue, deletes the row, fires onSuccess', () async {
      final dao = _memDao();
      final upload = _RecordingUpload();
      final queue = UploadQueue(dao: dao, upload: upload.fn, resumeOnStart: false);
      addTearDown(queue.dispose);

      var ok = false;
      final events = <UploadState>[];
      final sub = queue.progressStream('m').listen((e) => events.add(e.state));
      addTearDown(sub.cancel);

      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          onSuccess: () => ok = true,
        ),
      );
      await pumpEventQueue();

      expect(upload.calls.map((c) => c.mediaId), ['m']);
      expect(await dao.getById('m'), isNull, reason: 'row removed on success');
      expect(ok, isTrue);
      expect(events, containsAllInOrder([UploadState.pending, UploadState.uploading, UploadState.completed]));
    });

    test('threads ttlSecs through to the upload fn', () async {
      final dao = _memDao();
      final upload = _RecordingUpload();
      final queue = UploadQueue(dao: dao, upload: upload.fn, resumeOnStart: false);
      addTearDown(queue.dispose);

      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          ttlSecs: BigInt.from(172800),
        ),
      );
      await pumpEventQueue();
      expect(upload.calls.single.ttl, BigInt.from(172800));
    });
  });

  group('retry + backoff', () {
    test('retries with backoff then succeeds', () async {
      final dao = _memDao();
      // Throw on the first two attempts, succeed on the third.
      final upload = _RecordingUpload(
        behavior: (i) {
          if (i < 2) throw StateError('transient $i');
          return UploadAttemptResult.ok;
        },
      );
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        baseBackoff: const Duration(milliseconds: 10),
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      var ok = false;
      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          onSuccess: () => ok = true,
        ),
      );
      // First attempt failed during enqueue; wait for the two backoff retries.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(upload.calls.length, 3);
      expect(await dao.getById('m'), isNull);
      expect(ok, isTrue);
    });

    test('exhausting retries marks terminal and never drops the row', () async {
      final dao = _memDao();
      final upload = _RecordingUpload(behavior: (_) => throw StateError('always'));
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        maxAttempts: 3,
        baseBackoff: const Duration(milliseconds: 5),
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      String? failure;
      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          onFailure: (e) => failure = e,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(upload.calls.length, 3, reason: 'exactly maxAttempts tries');
      final row = await dao.getById('m');
      expect(row, isNotNull, reason: 'terminal row is retained, not dropped');
      expect(row!.state, UploadQueueDao.stateTerminal);
      expect(await dao.terminalCount(), 1);
      expect(failure, contains('always'));
    });
  });

  group('unconfigured sync', () {
    test('completeLocallyWhenUnconfigured completes without a real upload', () async {
      final dao = _memDao();
      final upload = _RecordingUpload(behavior: (_) => UploadAttemptResult.unconfigured);
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        completeLocallyWhenUnconfigured: true,
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      var ok = false;
      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          onSuccess: () => ok = true,
        ),
      );
      await pumpEventQueue();

      expect(ok, isTrue);
      expect(await dao.getById('m'), isNull, reason: 'completed locally');
    });

    test('unconfigured without local-complete eventually goes terminal', () async {
      final dao = _memDao();
      final upload = _RecordingUpload(behavior: (_) => UploadAttemptResult.unconfigured);
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        completeLocallyWhenUnconfigured: false,
        maxAttempts: 2,
        baseBackoff: const Duration(milliseconds: 5),
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      String? failure;
      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          onFailure: (e) => failure = e,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final row = await dao.getById('m');
      expect(row?.state, UploadQueueDao.stateTerminal);
      expect(failure, isNotNull);
    });
  });

  group('resume', () {
    test('resumes rows persisted before construction', () async {
      final dao = _memDao();
      // Simulate a row left pending by a prior session.
      await dao.upsert(
        mediaId: 'left-over',
        contentHash: 'h',
        ciphertext: _bytes(),
        createdAtMs: 1,
      );
      expect(await dao.pendingCount(), 1);

      final upload = _RecordingUpload();
      final queue = UploadQueue(dao: dao, upload: upload.fn); // resumeOnStart: true
      addTearDown(queue.dispose);
      await pumpEventQueue();

      expect(upload.calls.map((c) => c.mediaId), ['left-over']);
      expect(await dao.getById('left-over'), isNull, reason: 'resumed + uploaded');
    });
  });

  group('idempotency', () {
    test('re-enqueuing the same mediaId leaves no duplicate pending row', () async {
      final dao = _memDao();
      // Never resolves "ok" immediately: hold uploads so both enqueues persist
      // before either completes.
      final upload = _RecordingUpload(behavior: (_) => UploadAttemptResult.unconfigured);
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        completeLocallyWhenUnconfigured: false,
        baseBackoff: const Duration(seconds: 30), // park after the first failure
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      await queue.enqueue(
        UploadTask(mediaId: 'dup', contentHash: 'h', encryptedData: _bytes()),
      );
      await queue.enqueue(
        UploadTask(mediaId: 'dup', contentHash: 'h', encryptedData: _bytes(3)),
      );

      // Exactly one row for the media_id (PK), still pending after the re-enqueue
      // reset it.
      final row = await dao.getById('dup');
      expect(row, isNotNull);
      expect(row!.state, UploadQueueDao.statePending);
      expect(await dao.pendingCount(), 1);
    });
  });
}
