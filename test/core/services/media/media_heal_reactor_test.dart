import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/ephemeral_signal.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_heal_providers.dart';
import 'package:prism_plurality/core/services/media/media_heal_requester.dart';
import 'package:prism_plurality/core/services/media/media_heal_responder.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/chat/providers/media_available_provider.dart';

// ── Spies over the three heal sinks the reactor drives ─────────────────────────
//
// Each extends the real class (so it satisfies the provider's type) and records
// the one method the reactor calls, no-op'ing the rest. The reactor is a thin
// wiring seam; these prove each source event routes to the correct sink.

class _SpyResponder extends MediaHealResponder {
  _SpyResponder()
      : super(
          holdsBlob: (_) async => false,
          batchExists: (_) async => const [],
          reUpload: (_) async => ReUploadResult.failed,
          sendMediaUploaded: (_) async {},
        );
  final List<String> requests = [];
  @override
  Future<void> onMediaRequest(String mediaId) async => requests.add(mediaId);
}

class _SpyHydrator extends MediaHydrator {
  _SpyHydrator(MediaAttachmentsDao dao, DownloadManager dm)
      : super(attachmentsDao: dao, downloadManager: dm);
  final List<String> retried = [];
  @override
  Future<void> retry(String mediaId) async => retried.add(mediaId);
}

class _SpyRequester extends MediaHealRequester {
  _SpyRequester(MissingMediaDao dao)
      : super(
          dao: dao,
          batchExists: (_) async => const [],
          sendMediaRequest: (_) async {},
        );
  int cadenceRuns = 0;
  List<String> healed = [];
  @override
  Future<List<String>> runCadence() async {
    cadenceRuns++;
    return healed;
  }
}

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  late AppDatabase db;
  late _SpyResponder responder;
  late _SpyHydrator hydrator;
  late _SpyRequester requester;
  late StreamController<EphemeralMessage> ephemeral;
  late StreamController<MediaAvailableEvent> available;
  late StreamController<SyncEvent> syncEvents;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    responder = _SpyResponder();
    hydrator = _SpyHydrator(
      db.mediaAttachmentsDao,
      DownloadManager(handle: null, encryption: MediaEncryptionService()),
    );
    requester = _SpyRequester(db.missingMediaDao);
    ephemeral = StreamController<EphemeralMessage>.broadcast();
    available = StreamController<MediaAvailableEvent>.broadcast();
    syncEvents = StreamController<SyncEvent>.broadcast();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        ephemeralMessageStreamProvider.overrideWith((ref) => ephemeral.stream),
        mediaAvailableProvider.overrideWith((ref) => available.stream),
        syncEventStreamProvider.overrideWith((ref) => syncEvents.stream),
        mediaHealResponderProvider.overrideWithValue(responder),
        mediaHydratorProvider.overrideWithValue(hydrator),
        mediaHealRequesterProvider.overrideWithValue(requester),
      ],
    );
    // Activate the reactor exactly as `app.dart` does — a live `listen` keeps it
    // (and its three internal `ref.listen`s) subscribed. Settle so the underlying
    // broadcast subscriptions are live before we emit.
    container.listen(mediaHealReactorProvider, (_, _) {}, fireImmediately: true);
    await settle();
  });

  tearDown(() async {
    container.dispose();
    await ephemeral.close();
    await available.close();
    await syncEvents.close();
    await db.close();
  });

  EphemeralMessage msg(String kind, String mediaId) => EphemeralMessage(
        senderDeviceId: 'peer',
        kind: kind,
        mediaId: mediaId,
        epochId: 1,
      );

  test('a peer media_request drives the responder, not the hydrator', () async {
    ephemeral.add(msg(mediaRequestKind, 'blob-req'));
    await settle();

    expect(responder.requests, ['blob-req']);
    expect(hydrator.retried, isEmpty, reason: 'a request is the responder’s job');
  });

  test('a peer media_uploaded drives the hydrator re-download, not the responder',
      () async {
    ephemeral.add(msg(mediaUploadedKind, 'blob-up'));
    await settle();

    expect(hydrator.retried, ['blob-up'], reason: 'heal-completion re-download');
    expect(responder.requests, isEmpty);
  });

  test('an unknown ephemeral kind is ignored by both sinks', () async {
    ephemeral.add(msg('some_other_kind', 'blob-x'));
    await settle();

    expect(responder.requests, isEmpty);
    expect(hydrator.retried, isEmpty);
  });

  test('a media-available event removes the blob from the missing-media set',
      () async {
    await db.missingMediaDao.markMissing(
      mediaId: 'now-here',
      priority: MissingMediaDao.priorityChat,
      nowMs: 1000,
    );
    expect(await db.missingMediaDao.getById('now-here'), isNotNull);

    available.add(const MediaAvailableEvent('now-here'));
    await settle();

    expect(
      await db.missingMediaDao.getById('now-here'),
      isNull,
      reason: 'a blob that landed in cache is no longer missing',
    );
  });

  test('a completed sync runs the cadence and re-downloads what it healed',
      () async {
    requester.healed = ['h1', 'h2'];
    syncEvents.add(SyncEvent('SyncCompleted', {'type': 'SyncCompleted'}));
    await settle();

    expect(requester.cadenceRuns, 1);
    expect(hydrator.retried, containsAll(<String>['h1', 'h2']),
        reason: 'each healed blob is re-pulled to emit MediaAvailable');
  });

  test('a non-completion sync event does not run the cadence', () async {
    syncEvents.add(SyncEvent('SyncStarted', {'type': 'SyncStarted'}));
    await settle();

    expect(requester.cadenceRuns, 0);
    expect(hydrator.retried, isEmpty);
  });
}
