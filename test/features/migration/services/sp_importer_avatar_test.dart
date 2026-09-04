import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  final testPublicAddress = InternetAddress('93.184.216.34');
  Future<List<InternetAddress>> testPublicLookup(String _) async => [
    testPublicAddress,
  ];
  setUpAll(() => setRemoteImageHostLookupForTesting(testPublicLookup));
  tearDownAll(() => setRemoteImageHostLookupForTesting(null));

  AppDatabase makeDb() => AppDatabase(NativeDatabase.memory());

  SpExportData exportWithSystemAvatar(String? url) => SpExportData(
    members: const [],
    customFronts: const [],
    frontHistory: const [],
    groups: const [],
    channels: const [],
    messages: const [],
    polls: const [],
    systemAvatarUrl: url,
  );

  Future<ImportResult> runImport({
    required AppDatabase db,
    required http.Client client,
    required FakeSystemSettingsRepository settingsRepo,
    required SpExportData data,
    bool downloadAvatars = true,
  }) {
    final importer = SpImporter(httpClient: client);
    return importer.executeImport(
      db: db,
      data: data,
      memberRepo: DriftMemberRepository(db.membersDao, null),
      sessionRepo: DriftFrontingSessionRepository(db.frontingSessionsDao, null),
      conversationRepo: DriftConversationRepository(db.conversationsDao, null),
      messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
      pollRepo: DriftPollRepository(
        db.pollsDao,
        db.pollOptionsDao,
        db.pollVotesDao,
        null,
      ),
      settingsRepo: settingsRepo,
      downloadAvatars: downloadAvatars,
    );
  }

  test(
    'system avatar URL with 2xx image response is stored on settings repo',
    () async {
      final avatarBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/system.png');
        return http.Response.bytes(
          avatarBytes,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final settingsRepo = FakeSystemSettingsRepository();
      final db = makeDb();
      addTearDown(db.close);

      final result = await runImport(
        db: db,
        client: mockClient,
        settingsRepo: settingsRepo,
        data: exportWithSystemAvatar('https://example.com/system.png'),
      );

      expect(result.systemAvatarDownloaded, isTrue);
      expect(settingsRepo.settings.systemAvatarData, isNotNull);
      expect(settingsRepo.settings.systemAvatarData, equals(avatarBytes));
    },
  );

  test(
    'non-image response is recorded as a warning and avatar is not stored',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '<html/>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final settingsRepo = FakeSystemSettingsRepository();
      final db = makeDb();
      addTearDown(db.close);

      final result = await runImport(
        db: db,
        client: mockClient,
        settingsRepo: settingsRepo,
        data: exportWithSystemAvatar('https://example.com/bad.html'),
      );

      expect(result.systemAvatarDownloaded, isFalse);
      expect(settingsRepo.settings.systemAvatarData, isNull);
      expect(result.warnings.any((w) => w.contains('System avatar')), isTrue);
    },
  );

  test('downloadAvatars=false skips the system avatar fetch', () async {
    var requested = false;
    final mockClient = MockClient((request) async {
      requested = true;
      return http.Response.bytes(
        Uint8List.fromList([1, 2, 3]),
        200,
        headers: {'content-type': 'image/png'},
      );
    });

    final settingsRepo = FakeSystemSettingsRepository();
    final db = makeDb();
    addTearDown(db.close);

    final result = await runImport(
      db: db,
      client: mockClient,
      settingsRepo: settingsRepo,
      data: exportWithSystemAvatar('https://example.com/system.png'),
      downloadAvatars: false,
    );

    expect(requested, isFalse);
    expect(result.systemAvatarDownloaded, isFalse);
    expect(settingsRepo.settings.systemAvatarData, isNull);
  });

  test('no systemAvatarUrl → no fetch, no warning', () async {
    var requested = false;
    final mockClient = MockClient((request) async {
      requested = true;
      return http.Response('', 200);
    });

    final settingsRepo = FakeSystemSettingsRepository();
    final db = makeDb();
    addTearDown(db.close);

    final result = await runImport(
      db: db,
      client: mockClient,
      settingsRepo: settingsRepo,
      data: exportWithSystemAvatar(null),
    );

    expect(requested, isFalse);
    expect(result.systemAvatarDownloaded, isFalse);
    expect(result.warnings, isEmpty);
  });

  // Regression test for the Phase 2 stale-snapshot bug. Pre-fix,
  // `_downloadAvatars` bulk-read members at the START of the avatar phase
  // and emitted `syncRecordUpdate` per success using `_memberFields()` from
  // that stale snapshot. A user renaming a member during the avatar
  // download window would have their edit clobbered on peers via field-LWW
  // (local DB stayed correct because the DAO batch only writes the
  // `avatarImageData` column). Post-fix, the read is deferred until after
  // all downloads complete so the emission payload carries the
  // post-mutation member name.
  test(
    'mid-download rename is reflected in emitted syncRecordUpdate payload',
    () async {
      // Real PNG so DriftMemberRepository's avatar normalizer doesn't bail
      // on garbage bytes. Generated rather than hard-coded so the `image`
      // package's decoder is guaranteed to accept it.
      final fakeBytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4)),
      );
      const avatarUrl = 'https://example.com/slow.png';

      // HTTP client that holds the avatar response until the test
      // explicitly completes `releaseFetch`. Lets the test rename the
      // member between the start of the fetch and its completion — i.e.
      // exactly the window in which the bug manifests.
      final fetchStarted = Completer<void>();
      final releaseFetch = Completer<http.Response>();
      final mockClient = MockClient((request) async {
        if (request.url.toString() != avatarUrl) {
          return http.Response('not found', 404);
        }
        if (!fetchStarted.isCompleted) fetchStarted.complete();
        return releaseFetch.future;
      });

      final db = makeDb();
      addTearDown(db.close);

      final settingsRepo = FakeSystemSettingsRepository();
      final memberRepo = DriftMemberRepository(db.membersDao, null);
      final importer = SpImporter(httpClient: mockClient);

      const data = SpExportData(
        members: [
          SpMember(id: 'sp-mid', name: 'Original', avatarUrl: avatarUrl),
        ],
        customFronts: [],
        frontHistory: [],
        groups: [],
        channels: [],
        messages: [],
        polls: [],
      );

      // Install the capture sink so we can inspect what syncRecordUpdate
      // would emit to peers. SyncRecordMixin enforces single-installer; we
      // remove it on tearDown via the helper below.
      final updateEmissions = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting((op) {
        if (op.opType == SyncRecordOpType.update && op.table == 'members') {
          updateEmissions.add(op);
        }
      });
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Kick off the import. We do NOT await it yet — it'll block inside
      // _downloadAvatars waiting on `releaseFetch`.
      final importFuture = importer.executeImport(
        db: db,
        data: data,
        memberRepo: memberRepo,
        sessionRepo: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        conversationRepo: DriftConversationRepository(
          db.conversationsDao,
          null,
        ),
        messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
        pollRepo: DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        ),
        settingsRepo: settingsRepo,
        downloadAvatars: true,
      );

      // Wait until the avatar fetch is in flight. At this point the member
      // row has been inserted (the create emission has already fired) but
      // _downloadAvatars is parked on `releaseFetch.future`.
      await fetchStarted.future;

      // Simulate a user renaming the member while the avatar phase is
      // in flight. Pre-fix, _downloadAvatars holds a snapshot from before
      // this update and would emit "Original" on the post-download
      // syncRecordUpdate.
      final imported = (await memberRepo.getAllMembers()).single;
      await memberRepo.updateMember(
        imported.copyWith(name: 'Renamed Mid Flight'),
      );

      // Release the avatar fetch and let the import finish.
      releaseFetch.complete(
        http.Response.bytes(
          fakeBytes,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      final result = await importFuture;
      expect(result.avatarsDownloaded, 1);

      final finalRow = (await memberRepo.getAllMembers()).single;
      expect(finalRow.name, 'Renamed Mid Flight');
      expect(finalRow.avatarImageData, isNotNull);

      // Avatar replay should not ship a stale full-member snapshot.
      final avatarEmission = updateEmissions.singleWhere(
        (op) =>
            op.entityId == finalRow.id &&
            op.fields['avatar_image_data'] != null,
        orElse: () => throw StateError(
          'expected exactly one avatar-phase update emission for the member',
        ),
      );
      expect(
        avatarEmission.fields.containsKey('name'),
        isFalse,
        reason:
            'avatar-phase syncRecordUpdate emitted a name field; peers could '
            'resurrect a stale value via field-LWW',
      );
    },
  );
}
