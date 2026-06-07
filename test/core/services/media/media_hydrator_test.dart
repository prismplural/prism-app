import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';

/// Minimal stand-in so [DownloadManager]'s constructor is satisfied; the fake
/// overrides every method the hydrator touches, so this is never invoked.
class _NoopEncryption extends MediaEncryptionService {}

/// Fake [DownloadManager] that bypasses the un-constructable-in-tests
/// `PrismSyncHandle` + real FFI/decrypt path while preserving the contract the
/// hydrator depends on: [isCached] reports disk presence; [getMedia] returns
/// the plaintext (and writes a `.enc` cache file) on success, or `null` for a
/// transient miss — matching production, where getMedia swallows download
/// failures and returns null.
class _FakeDownloadManager extends DownloadManager {
  _FakeDownloadManager(this._mediaDir)
      : super(handle: null, encryption: _NoopEncryption());

  final Directory _mediaDir;
  final Set<String> cached = {};
  final Map<String, int> calls = {};

  /// Per-id: leading calls that return null (transient miss) before success.
  final Map<String, int> failFirst = {};

  /// Ids that always return null (e.g. never uploaded → relay 404).
  final Set<String> neverAvailable = {};

  @override
  Future<bool> isCached(String mediaId, {String fileExtension = ''}) async {
    return cached.contains(mediaId);
  }

  @override
  Future<Uint8List?> getMedia({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
    String fileExtension = '',
  }) async {
    final n = (calls[mediaId] ?? 0) + 1;
    calls[mediaId] = n;

    if (neverAvailable.contains(mediaId)) return null;
    if (n <= (failFirst[mediaId] ?? 0)) return null;

    await _mediaDir.create(recursive: true);
    await File(p.join(_mediaDir.path, '$mediaId.enc'))
        .writeAsBytes(Uint8List.fromList([n]));
    cached.add(mediaId);
    return Uint8List.fromList([n]);
  }
}

void main() {
  late Directory tempDir;
  late Directory mediaDir;
  late AppDatabase db;
  late _FakeDownloadManager downloads;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media-hydrator-');
    mediaDir = Directory(p.join(tempDir.path, 'prism_media'));
    db = AppDatabase(NativeDatabase.memory());
    downloads = _FakeDownloadManager(mediaDir);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ── helpers ───────────────────────────────────────────────────────────────

  Future<void> seedRow(
    String mediaId, {
    String? id,
    bool isDeleted = false,
  }) {
    return db.into(db.mediaAttachments).insert(
          MediaAttachmentsCompanion(
            id: Value(id ?? 'att-$mediaId'),
            mediaId: Value(mediaId),
            mediaType: const Value('image'),
            encryptionKeyB64: const Value('a2V5'), // base64("key")
            contentHash: Value('ch-$mediaId'),
            plaintextHash: Value('ph-$mediaId'),
            isDeleted: Value(isDeleted),
          ),
        );
  }

  bool cacheFileExists(String mediaId) =>
      File(p.join(mediaDir.path, '$mediaId.enc')).existsSync();

  MediaHydrator makeHydrator({int maxAttempts = 5, void Function(String)? log}) {
    return MediaHydrator(
      attachmentsDao: db.mediaAttachmentsDao,
      downloadManager: downloads,
      maxAttempts: maxAttempts,
      // Run retries on a microtask (no real timer) so backoff tests are
      // instant and deterministic, and dispose has no timers to cancel.
      scheduleRetry: (_, run) => Future<void>.microtask(run),
      log: log ?? (_) {},
    );
  }

  /// The hydrator emits a [MediaAvailableEvent] only after the blob is written
  /// to disk, so awaiting [count] events is a deterministic signal that the
  /// downloads finished — no polling.
  Future<List<String>> landed(MediaHydrator hydrator, int count) {
    return hydrator.events
        .map((e) => e.mediaId)
        .take(count)
        .toList()
        .timeout(const Duration(seconds: 5));
  }

  group('enqueuePending', () {
    test('downloads every missing blob, caches it, and emits an event',
        () async {
      await seedRow('media-a');
      await seedRow('media-b');

      final hydrator = makeHydrator();
      final got = landed(hydrator, 2);

      await hydrator.enqueuePending();
      final ids = await got;

      expect(ids.toSet(), {'media-a', 'media-b'});
      expect(cacheFileExists('media-a'), isTrue);
      expect(cacheFileExists('media-b'), isTrue);
      expect(downloads.calls.keys.toSet(), {'media-a', 'media-b'});

      hydrator.dispose();
    });

    test('skips blobs already present in the local cache', () async {
      await seedRow('media-cached');
      downloads.cached.add('media-cached');

      final hydrator = makeHydrator();
      await hydrator.enqueuePending();
      await pumpEventQueue();

      expect(downloads.calls, isEmpty,
          reason: 'an already-cached blob must not be downloaded again');
      hydrator.dispose();
    });

    test('does not walk soft-deleted rows', () async {
      await seedRow('media-live');
      await seedRow('media-deleted', isDeleted: true);

      final hydrator = makeHydrator();
      final got = landed(hydrator, 1);

      await hydrator.enqueuePending();
      final ids = await got;

      expect(ids, ['media-live']);
      expect(downloads.calls.keys, ['media-live']);
      hydrator.dispose();
    });

    test('skips rows lacking the fields needed to download', () async {
      // A "sending" placeholder row: empty media id + hashes.
      await db.into(db.mediaAttachments).insert(
            const MediaAttachmentsCompanion(
              id: Value('att-placeholder'),
              mediaId: Value(''),
              mediaType: Value('image'),
            ),
          );
      // A row with a media id but no hashes (can't download without them).
      await db.into(db.mediaAttachments).insert(
            const MediaAttachmentsCompanion(
              id: Value('att-no-hash'),
              mediaId: Value('media-no-hash'),
              mediaType: Value('image'),
              encryptionKeyB64: Value('a2V5'),
            ),
          );

      final hydrator = makeHydrator();
      await hydrator.enqueuePending();
      await pumpEventQueue();

      expect(downloads.calls, isEmpty);
      hydrator.dispose();
    });
  });

  group('enqueueIfMissing', () {
    test('dedups concurrent enqueues for the same media id', () async {
      final hydrator = makeHydrator();
      final got = landed(hydrator, 1);

      void enqueue() => hydrator.enqueueIfMissing(
            mediaId: 'media-dup',
            encryptionKeyB64: 'a2V5',
            contentHash: 'ch',
            plaintextHash: 'ph',
          );
      enqueue();
      enqueue();

      final ids = await got;
      expect(ids, ['media-dup']);
      expect(downloads.calls['media-dup'], 1,
          reason: 'a second enqueue for an in-flight id must be a no-op');
      hydrator.dispose();
    });
  });

  group('retry & give-up', () {
    test('retries a transient miss with backoff, then succeeds', () async {
      await seedRow('media-flaky');
      downloads.failFirst['media-flaky'] = 2; // 2 misses, then success

      final hydrator = makeHydrator(maxAttempts: 5);
      final got = landed(hydrator, 1);

      await hydrator.enqueuePending();
      final ids = await got;

      expect(ids, ['media-flaky']);
      expect(downloads.calls['media-flaky'], 3,
          reason: '2 transient failures + 1 success');
      expect(cacheFileExists('media-flaky'), isTrue);
      hydrator.dispose();
    });

    test('gives up after maxAttempts and does not re-attempt on a re-walk',
        () async {
      await seedRow('media-missing');
      downloads.neverAvailable.add('media-missing');
      final logs = <String>[];
      final hydrator = makeHydrator(maxAttempts: 3, log: logs.add);

      await hydrator.enqueuePending();
      await pumpEventQueue(); // drain the (microtask) retry chain to give-up

      expect(downloads.calls['media-missing'], 3);
      expect(cacheFileExists('media-missing'), isFalse);
      expect(
        logs.any((l) => l.contains('unavailable after 3 attempts')),
        isTrue,
      );

      // A re-walk in the same session must NOT hammer the relay again — the
      // given-up skip is synchronous, so no further attempts can be scheduled.
      await hydrator.enqueuePending();
      await pumpEventQueue();
      expect(downloads.calls['media-missing'], 3,
          reason: 'given-up ids are skipped until the next launch');

      hydrator.dispose();
    });
  });
}
