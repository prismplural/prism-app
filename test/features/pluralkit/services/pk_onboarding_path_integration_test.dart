/// Integration test mirroring the EXACT onboarding _handleImport path:
///   setToken -> testConnection -> importMembersOnly
///
/// The existing pk_api_integration_test only exercises performFullImport
/// with tokenOverride — it skips setToken / testConnection entirely. This
/// reproduces the user-reported "silent fail in onboarding" against the
/// real PluralKit API.
///
/// Run: PK_TOKEN=… flutter test --tags integration \
///   test/features/pluralkit/services/pk_onboarding_path_integration_test.dart
@Tags(['integration'])
library;

import 'dart:io' show HttpClient, HttpOverrides, Platform, SecurityContext;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

String? get _tokenOrNull {
  final env = Platform.environment['PK_TOKEN'];
  if (env == null || env.trim().isEmpty) return null;
  return env;
}

bool get _skipAll => _tokenOrNull == null;

class _NoOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding installs HttpOverrides that turn every HTTP request
  // into a fake 400. Reset to default so we can hit the live PK API.
  HttpOverrides.global = _NoOverrides();

  // Stub flutter_secure_storage's MethodChannel with an in-memory map so
  // setToken's write/read path works without a real platform binding.
  final _memStore = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      switch (call.method) {
        case 'write':
          final args = (call.arguments as Map).cast<String, dynamic>();
          _memStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          final args = (call.arguments as Map).cast<String, dynamic>();
          return _memStore[args['key'] as String];
        case 'delete':
          final args = (call.arguments as Map).cast<String, dynamic>();
          _memStore.remove(args['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(_memStore);
        case 'deleteAll':
          _memStore.clear();
          return null;
      }
      return null;
    },
  );

  group('PluralKit onboarding _handleImport path', () {
    late AppDatabase db;

    setUp(() {
      _memStore.clear();
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'setToken -> testConnection -> importMembersOnly imports members',
      () async {
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo =
            DriftFrontingSessionRepository(db.frontingSessionsDao, null);

        // tokenOverride bypasses FlutterSecureStorage so we don't need a
        // platform binding. setToken still runs its full body (getSystem +
        // upsertSyncState + state emit).
        // Match production: do NOT use tokenOverride. We want setToken to
        // actually write to secure storage and _buildClient to read it back,
        // exactly as the onboarding flow does.
        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: sessionRepo,
          syncDao: db.pluralKitSyncDao,
          secureStorage: const FlutterSecureStorage(),
          // TestWidgetsFlutterBinding intercepts HttpClient → all requests
          // return 400. Inject a real http.Client via IOClient so we can
          // talk to the live PK API.
          clientFactory: (token) => PluralKitClient(
            token: token,
            httpClient: http_io.IOClient(),
          ),
        );

        // Mirror import_data_step.dart:_handleImport step-for-step.
        await service.setToken(_tokenOrNull!);
        // ignore: avoid_print
        print('after setToken: isConnected=${service.state.isConnected} '
            'needsMapping=${service.state.needsMapping} '
            'syncError=${service.state.syncError}');

        final connected = await service.testConnection();
        // ignore: avoid_print
        print('testConnection: $connected');
        expect(connected, isTrue, reason: 'token should connect');

        final (systemName, importedMembers) = await service.importMembersOnly();
        // ignore: avoid_print
        print('importMembersOnly: systemName=$systemName '
            'importedMembers=${importedMembers.length} '
            'syncError=${service.state.syncError}');

        expect(importedMembers, isNotEmpty,
            reason: 'PK system has 7 members — import should not return 0');

        final membersInDb = await db.membersDao.getAllMembers();
        // ignore: avoid_print
        print('members in DB: ${membersInDb.length}');
        expect(membersInDb, isNotEmpty,
            reason: 'members should be persisted to the local DB');
        expect(membersInDb.length, equals(importedMembers.length),
            reason: 'every PK member should land in the DB');
      },
      skip: _skipAll ? 'PK_TOKEN not set' : null,
    );
  });
}
