// On-load (fallback) hydration coverage. Proves the startup path actually
// hydrates, end-to-end through the real providers:
//
//   app.dart (DB-ready branch)  →  runMediaHydrationFromRef(ref)
//                               →  mediaHydratorProvider.enqueuePending()
//                               →  walks media_attachments + downloads missing
//
// Test 1 covers the real provider assembly + DB walk + download dispatch.
// Test 2 covers the WidgetRef glue (the exact call app.dart makes on load).
// Test 3 is a source-assertion that app.dart wires the trigger into the
// DB-ready branch with the listen + peek pattern, matching the reconcilers.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prism_plurality/core/async/yield_control.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';

class _NoopEncryption extends MediaEncryptionService {}

/// Fake [DownloadManager] (no FFI / handle): records getMedia calls and writes
/// a `.enc` file on success, mirroring production's cache-on-download.
class _FakeDownloadManager extends DownloadManager {
  _FakeDownloadManager(this._mediaDir)
    : super(handle: null, encryption: _NoopEncryption());

  final Directory _mediaDir;
  final Set<String> cached = {};
  final Map<String, int> calls = {};

  @override
  Future<bool> isCached(String mediaId, {String fileExtension = ''}) async =>
      cached.contains(mediaId);

  @override
  Future<MediaFetchResult> getMedia({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
    String fileExtension = '',
  }) async {
    calls[mediaId] = (calls[mediaId] ?? 0) + 1;
    await _mediaDir.create(recursive: true);
    await File(p.join(_mediaDir.path, '$mediaId.enc')).writeAsBytes([1]);
    cached.add(mediaId);
    return MediaFetchOk(Uint8List.fromList([1]));
  }
}

/// Spy that records [enqueuePending] invocations without doing real work.
class _SpyHydrator extends MediaHydrator {
  _SpyHydrator(MediaAttachmentsDao dao, DownloadManager dm)
    : super(attachmentsDao: dao, downloadManager: dm);

  int enqueuePendingCalls = 0;

  @override
  Future<void> enqueuePending() async {
    enqueuePendingCalls += 1;
  }
}

void main() {
  test('mediaHydratorProvider (real wiring) walks the DB and downloads missing '
      'blobs when enqueuePending runs on load', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tmp = await Directory.systemTemp.createTemp('hydra-startup-');
    addTearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });
    final fakeDownloads = _FakeDownloadManager(
      Directory(p.join(tmp.path, 'prism_media')),
    );

    // An already-paired device with a referenced blob and an empty cache —
    // exactly the fallback scenario: rows present, blob not yet pulled.
    await db
        .into(db.mediaAttachments)
        .insert(
          const MediaAttachmentsCompanion(
            id: Value('att-1'),
            mediaId: Value('media-on-load'),
            mediaType: Value('image'),
            encryptionKeyB64: Value('a2V5'),
            contentHash: Value('ch'),
            plaintextHash: Value('ph'),
          ),
        );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        downloadManagerProvider.overrideWithValue(fakeDownloads),
      ],
    );
    addTearDown(container.dispose);

    // Resolve the REAL hydrator from the REAL provider (proves the provider
    // assembles the right DAO + download manager), then run the load walk.
    final hydrator = container.read(mediaHydratorProvider);
    // The event fires only after the blob is written, so it's a deterministic
    // "download finished" signal — no polling.
    final landed = hydrator.events
        .map((e) => e.mediaId)
        .first
        .timeout(const Duration(seconds: 5));
    await hydrator.enqueuePending();
    expect(await landed, 'media-on-load');

    expect(
      fakeDownloads.calls.keys,
      contains('media-on-load'),
      reason: 'startup walk must download the referenced, uncached blob',
    );
    expect(
      File(p.join(tmp.path, 'prism_media', 'media-on-load.enc')).existsSync(),
      isTrue,
    );
  });

  testWidgets(
    'runMediaHydrationFromRef triggers enqueuePending on the resolved hydrator',
    (tester) async {
      final spyDb = AppDatabase(NativeDatabase.memory());
      addTearDown(spyDb.close);
      final spy = _SpyHydrator(
        spyDb.mediaAttachmentsDao,
        DownloadManager(handle: null, encryption: _NoopEncryption()),
      );
      addTearDown(spy.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mediaHydratorProvider.overrideWithValue(spy)],
          child: Consumer(
            builder: (context, ref, _) {
              // This is the exact call app.dart's startup hook makes.
              runMediaHydrationFromRef(ref);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(
        spy.enqueuePendingCalls,
        greaterThanOrEqualTo(1),
        reason: 'the startup glue must kick off a hydration walk',
      );
    },
  );

  test(
    'app.dart wires the media-hydration trigger into the DB-ready branch',
    () {
      final appDart = File('lib/app.dart').readAsStringSync();
      final readyStart = appDart.indexOf(
        '_repairPrimaryDatabaseKeySlotOnce();',
      );
      final appBuildStart = appDart.indexOf(
        'return DynamicColorBuilder(',
        readyStart,
      );
      expect(readyStart, isNonNegative);
      expect(appBuildStart, isNonNegative);

      final readyBranch = appDart.substring(readyStart, appBuildStart);
      expect(
        readyBranch,
        contains(
          'ref.listen(prismSyncHandleProvider, _maybeRunMediaHydration);',
        ),
        reason:
            'hydration must run after the sync layer resolves, like the '
            'orphan/bio reconcilers',
      );
      expect(
        readyBranch,
        contains(
          '_maybeRunMediaHydration(null, ref.read(prismSyncHandleProvider))',
        ),
        reason:
            'must peek the already-resolved handle (the listener will not '
            'fire for a cached value)',
      );
      // The trigger must delegate to the testable wrapper.
      expect(appDart, contains('runMediaHydrationFromRef(ref)'));
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Main-isolate fairness of the startup walk.
  //
  // `enqueuePending` runs on the main isolate at launch (`app.dart`'s DB-ready
  // branch). It awaits one full-table read, then walks every row synchronously,
  // doing two `enqueueIfMissing` calls (each reserving state and kicking off a
  // cache check) per row. For a large library that is an unbounded burst with no
  // frame or input turn, right when the first frame is being built. These tests
  // pin the yield cadence and prove the fanout still hydrates every row.
  // ─────────────────────────────────────────────────────────────────────────
  Future<AppDatabase> seedAttachments(int count) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (var i = 0; i < count; i++) {
      await db
          .into(db.mediaAttachments)
          .insert(
            MediaAttachmentsCompanion(
              id: Value('att-$i'),
              mediaId: Value('media-$i'),
              mediaType: const Value('image'),
              encryptionKeyB64: const Value('a2V5'),
              contentHash: Value('ch-$i'),
              plaintextHash: Value('ph-$i'),
            ),
          );
    }
    return db;
  }

  test(
    'a large startup walk yields once per cadence and still hydrates every row',
    () async {
      const rowCount = 120;
      final db = await seedAttachments(rowCount);
      final tmp = await Directory.systemTemp.createTemp('hydra-big-');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      });
      final fakeDownloads = _FakeDownloadManager(
        Directory(p.join(tmp.path, 'prism_media')),
      );

      var yields = 0;
      debugYieldOverride = () async => yields++;
      addTearDown(debugResetYieldOverride);

      final hydrator = MediaHydrator(
        attachmentsDao: db.mediaAttachmentsDao,
        downloadManager: fakeDownloads,
        rowsPerYield: 20,
        log: (_) {},
      );
      addTearDown(hydrator.dispose);

      final landed = hydrator.events
          .map((e) => e.mediaId)
          .take(rowCount)
          .toList();
      await hydrator.enqueuePending();

      expect(
        await landed.timeout(const Duration(seconds: 20)),
        hasLength(rowCount),
        reason: 'the fanout must still hydrate every referenced blob',
      );
      expect(fakeDownloads.calls.length, rowCount);
      expect(
        yields,
        6,
        reason:
            'one event-loop hop per rowsPerYield rows (120 / 20) — the bound '
            'that lets the first frame and early input through at startup',
      );
    },
  );

  test('a walk smaller than the cadence does not yield at all', () async {
    const rowCount = 10;
    final db = await seedAttachments(rowCount);
    final tmp = await Directory.systemTemp.createTemp('hydra-small-');
    addTearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });
    final fakeDownloads = _FakeDownloadManager(
      Directory(p.join(tmp.path, 'prism_media')),
    );

    var yields = 0;
    debugYieldOverride = () async => yields++;
    addTearDown(debugResetYieldOverride);

    final hydrator = MediaHydrator(
      attachmentsDao: db.mediaAttachmentsDao,
      downloadManager: fakeDownloads,
      rowsPerYield: 50,
      log: (_) {},
    );
    addTearDown(hydrator.dispose);

    final landed = hydrator.events
        .map((e) => e.mediaId)
        .take(rowCount)
        .toList();
    await hydrator.enqueuePending();

    expect(
      await landed.timeout(const Duration(seconds: 20)),
      hasLength(rowCount),
    );
    expect(yields, 0, reason: 'the walk yields in batches, not per row');
  });

  test('disposing mid-walk stops the fanout without throwing', () async {
    const rowCount = 200;
    final db = await seedAttachments(rowCount);
    final tmp = await Directory.systemTemp.createTemp('hydra-dispose-');
    addTearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });
    final fakeDownloads = _FakeDownloadManager(
      Directory(p.join(tmp.path, 'prism_media')),
    );

    MediaHydrator? hydratorRef;
    var yields = 0;
    debugYieldOverride = () async {
      yields++;
      // Dispose while the walk is suspended at a yield.
      if (yields == 1) hydratorRef?.dispose();
    };
    addTearDown(debugResetYieldOverride);

    final hydrator = MediaHydrator(
      attachmentsDao: db.mediaAttachmentsDao,
      downloadManager: fakeDownloads,
      rowsPerYield: 10,
      log: (_) {},
    );
    hydratorRef = hydrator;
    addTearDown(hydrator.dispose);

    await hydrator.enqueuePending();

    expect(
      yields,
      1,
      reason: 'the walk must bail out at the first yield after dispose',
    );
  });
}
