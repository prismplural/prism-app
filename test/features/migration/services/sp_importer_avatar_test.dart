import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/core/database/app_database.dart' show AppDatabase;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
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
          db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null),
      settingsRepo: settingsRepo,
      downloadAvatars: downloadAvatars,
    );
  }

  test('system avatar URL with 2xx image response is stored on settings repo',
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
  });

  test('non-image response is recorded as a warning and avatar is not stored',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response('<html/>', 200, headers: {
        'content-type': 'text/html',
      });
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
    expect(
      result.warnings.any((w) => w.contains('System avatar')),
      isTrue,
    );
  });

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
}
