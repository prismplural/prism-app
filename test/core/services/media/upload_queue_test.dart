import 'dart:async';
import 'dart:io';
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
  final FutureOr<UploadAttemptResult> Function(int callIndex)? behavior;

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
  });

  group('enqueue semantics', () {
    test('onSuccess fires on durable enqueue, before the upload finishes', () async {
      final dao = _memDao();
      final gate = Completer<void>();
      // Upload blocks until released — proves onSuccess does NOT wait on it.
      final upload = _RecordingUpload(
        behavior: (_) async {
          await gate.future;
          return UploadAttemptResult.ok;
        },
      );
      final queue = UploadQueue(dao: dao, upload: upload.fn, resumeOnStart: false);
      addTearDown(queue.dispose);

      var enqueued = false;
      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(),
          onSuccess: () => enqueued = true,
        ),
      );

      // onSuccess already fired even though the upload is still blocked.
      expect(enqueued, isTrue);
      expect(await dao.getById('m'), isNotNull, reason: 'still uploading');

      gate.complete();
      await pumpEventQueue();
      expect(await dao.getById('m'), isNull, reason: 'deleted after upload');
    });

    test('uploads the blob and deletes the row on success', () async {
      final dao = _memDao();
      final upload = _RecordingUpload();
      final queue = UploadQueue(dao: dao, upload: upload.fn, resumeOnStart: false);
      addTearDown(queue.dispose);

      await queue.enqueue(
        UploadTask(mediaId: 'm', contentHash: 'h', encryptedData: _bytes()),
      );
      await pumpEventQueue();

      expect(upload.calls.map((c) => c.mediaId), ['m']);
      expect(await dao.getById('m'), isNull);
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
    test('a throwing attempt does NOT delete the row; it retries then succeeds', () async {
      final dao = _memDao();
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

      await queue.enqueue(
        UploadTask(mediaId: 'm', contentHash: 'h', encryptedData: _bytes()),
      );
      // The row survived the first failure.
      expect(await dao.getById('m'), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(upload.calls.length, 3);
      expect(await dao.getById('m'), isNull);
    });

    test('exhausting retries → terminal tombstone, retained but bytes dropped', () async {
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

      await queue.enqueue(
        UploadTask(
          mediaId: 'm',
          contentHash: 'h',
          encryptedData: _bytes(64),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(upload.calls.length, 3, reason: 'exactly maxAttempts tries');
      final row = await dao.getById('m');
      expect(row, isNotNull, reason: 'terminal row retained, not dropped');
      expect(row!.state, UploadQueueDao.stateTerminal);
      expect(row.ciphertext, isEmpty, reason: 'bytes dropped to bound DB growth');
      expect(row.lastError, contains('always'));
      expect(await dao.terminalCount(), 1);
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

      await queue.enqueue(
        UploadTask(mediaId: 'm', contentHash: 'h', encryptedData: _bytes()),
      );
      await pumpEventQueue();
      expect(await dao.getById('m'), isNull, reason: 'completed locally');
    });

    test('a transient throw (e.g. null handle) retries — never drops the row', () async {
      final dao = _memDao();
      // Always throws (models a configured-but-disconnected handle). The row
      // must persist and back off, NOT be deleted.
      final upload = _RecordingUpload(behavior: (_) => throw StateError('disconnected'));
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        baseBackoff: const Duration(seconds: 30), // park after first failure
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      await queue.enqueue(
        UploadTask(mediaId: 'm', contentHash: 'h', encryptedData: _bytes()),
      );
      await pumpEventQueue();

      final row = await dao.getById('m');
      expect(row, isNotNull, reason: 'a disconnect must not drop a configured send');
      expect(row!.state, UploadQueueDao.statePending);
      expect(row.attempts, 1);
    });
  });

  group('resume across restart', () {
    test('resumes a row persisted to a file DB by a prior "session"', () async {
      final dir = await Directory.systemTemp.createTemp('uq_resume');
      addTearDown(() => dir.delete(recursive: true));
      final dbFile = File('${dir.path}/app.db');

      // Session 1: persist a pending row, then "close the app".
      final db1 = AppDatabase(NativeDatabase(dbFile));
      await db1.uploadQueueDao.upsert(
        mediaId: 'persisted',
        contentHash: 'h',
        ciphertext: _bytes(),
        createdAtMs: 1,
      );
      await db1.close();

      // Session 2: reopen the same file; the queue resumes on construction.
      final db2 = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db2.close);
      final upload = _RecordingUpload();
      final queue = UploadQueue(dao: db2.uploadQueueDao, upload: upload.fn);
      addTearDown(queue.dispose);
      await pumpEventQueue();

      expect(upload.calls.map((c) => c.mediaId), ['persisted']);
      expect(await db2.uploadQueueDao.getById('persisted'), isNull);
    });
  });

  group('ordering + idempotency', () {
    test('drains multiple blobs in FIFO enqueue order', () async {
      final dao = _memDao();
      final upload = _RecordingUpload();
      final queue = UploadQueue(dao: dao, upload: upload.fn, resumeOnStart: false);
      addTearDown(queue.dispose);

      for (final id in ['a', 'b', 'c']) {
        await dao.upsert(
          mediaId: id,
          contentHash: 'h',
          ciphertext: _bytes(),
          // createdAt ascending so FIFO is well-defined.
          createdAtMs: id.codeUnitAt(0),
        );
      }
      await queue.enqueue(
        UploadTask(mediaId: 'd', contentHash: 'h', encryptedData: _bytes()),
      );
      await pumpEventQueue();

      expect(upload.calls.map((c) => c.mediaId), ['a', 'b', 'c', 'd']);
    });

    test('re-enqueuing the same mediaId leaves no duplicate pending row', () async {
      final dao = _memDao();
      final upload = _RecordingUpload(behavior: (_) => throw StateError('parked'));
      final queue = UploadQueue(
        dao: dao,
        upload: upload.fn,
        baseBackoff: const Duration(seconds: 30),
        resumeOnStart: false,
      );
      addTearDown(queue.dispose);

      await queue.enqueue(
        UploadTask(mediaId: 'dup', contentHash: 'h', encryptedData: _bytes()),
      );
      await queue.enqueue(
        UploadTask(mediaId: 'dup', contentHash: 'h', encryptedData: _bytes(3)),
      );

      final row = await dao.getById('dup');
      expect(row, isNotNull);
      expect(await dao.pendingCount(), 1);
    });
  });
}
