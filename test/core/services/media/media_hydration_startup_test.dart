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
  test(
    'mediaHydratorProvider (real wiring) walks the DB and downloads missing '
    'blobs when enqueuePending runs on load',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final tmp = await Directory.systemTemp.createTemp('hydra-startup-');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      });
      final fakeDownloads =
          _FakeDownloadManager(Directory(p.join(tmp.path, 'prism_media')));

      // An already-paired device with a referenced blob and an empty cache —
      // exactly the fallback scenario: rows present, blob not yet pulled.
      await db.into(db.mediaAttachments).insert(
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
      final landed = hydrator.events.map((e) => e.mediaId).first.timeout(
            const Duration(seconds: 5),
          );
      await hydrator.enqueuePending();
      expect(await landed, 'media-on-load');

      expect(fakeDownloads.calls.keys, contains('media-on-load'),
          reason: 'startup walk must download the referenced, uncached blob');
      expect(
        File(p.join(tmp.path, 'prism_media', 'media-on-load.enc')).existsSync(),
        isTrue,
      );
    },
  );

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

      expect(spy.enqueuePendingCalls, greaterThanOrEqualTo(1),
          reason: 'the startup glue must kick off a hydration walk');
    },
  );

  test('app.dart wires the media-hydration trigger into the DB-ready branch',
      () {
    final appDart = File('lib/app.dart').readAsStringSync();
    final readyStart = appDart.indexOf('_repairPrimaryDatabaseKeySlotOnce();');
    final appBuildStart =
        appDart.indexOf('return DynamicColorBuilder(', readyStart);
    expect(readyStart, isNonNegative);
    expect(appBuildStart, isNonNegative);

    final readyBranch = appDart.substring(readyStart, appBuildStart);
    expect(
      readyBranch,
      contains('ref.listen(prismSyncHandleProvider, _maybeRunMediaHydration);'),
      reason: 'hydration must run after the sync layer resolves, like the '
          'orphan/bio reconcilers',
    );
    expect(
      readyBranch,
      contains('_maybeRunMediaHydration(null, ref.read(prismSyncHandleProvider))'),
      reason: 'must peek the already-resolved handle (the listener will not '
          'fire for a cached value)',
    );
    // The trigger must delegate to the testable wrapper.
    expect(appDart, contains('runMediaHydrationFromRef(ref)'));
  });
}
