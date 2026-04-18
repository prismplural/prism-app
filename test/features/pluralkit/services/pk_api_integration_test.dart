/// Integration test: full PluralKit sync pipeline using a real API token.
///
/// Excluded from CI. Run manually:
///   flutter test --tags integration test/features/pluralkit/services/pk_api_integration_test.dart
///
/// Set PK_TOKEN env var to override the default test account token.
@Tags(['integration'])
library;

import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Token — set PK_TOKEN env var to override; falls back to dedicated test
// account token (not personal credentials — a read-only integration test
// account at pluralkit.me/profile).
// ---------------------------------------------------------------------------

const _testAccountToken =
    'REDACTED_PK_TEST_TOKEN';

String get _token =>
    Platform.environment['PK_TOKEN'] ?? _testAccountToken;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PluralKit sync — full pipeline integration', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'performFullImport writes members and sessions to DB',
      () async {
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo =
            DriftFrontingSessionRepository(db.frontingSessionsDao, null);

        // tokenOverride bypasses FlutterSecureStorage so no test binding needed.
        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: sessionRepo,
          syncDao: db.pluralKitSyncDao,
          tokenOverride: _token,
        );

        // Full import — pulls members and all switch history from live API.
        await service.performFullImport();

        expect(service.state.isSyncing, isFalse);
        expect(service.state.syncError, isNull,
            reason: 'Full import should complete without error');

        // Members were written to DB.
        final membersInDb = await db.membersDao.getAllMembers();
        expect(membersInDb, isNotEmpty,
            reason: 'At least one member should be imported from PK');

        // Every member must carry its PK IDs for future delta syncs.
        for (final m in membersInDb) {
          expect(m.pluralkitId, isNotNull,
              reason: 'Member ${m.name} missing pluralkitId');
          expect(m.pluralkitUuid, isNotNull,
              reason: 'Member ${m.name} missing pluralkitUuid');
        }

        // Switches were written as fronting sessions.
        final sessionsInDb = await db.frontingSessionsDao.getAllSessions();
        expect(sessionsInDb, isNotEmpty,
            reason: 'At least one switch should become a fronting session');

        // Every session with a member must reference a known member.
        final memberIds = membersInDb.map((m) => m.id).toSet();
        for (final s in sessionsInDb) {
          if (s.memberId != null) {
            expect(memberIds, contains(s.memberId),
                reason:
                    'Session ${s.id} references unknown member ${s.memberId}');
          }
        }

        // Sync state was updated.
        final syncState = await db.pluralKitSyncDao.getSyncState();
        expect(syncState.lastSyncDate, isNotNull,
            reason: 'lastSyncDate should be set after full import');

        // -- Diagnostic output -------------------------------------------------
        // ignore: avoid_print
        print('\n=== PluralKit API Integration Test Summary ===');
        // ignore: avoid_print
        print('Members in DB: ${membersInDb.length}');
        // ignore: avoid_print
        print('Sessions in DB: ${sessionsInDb.length}');
        // ignore: avoid_print
        print('Last sync: ${syncState.lastSyncDate}');
        // ignore: avoid_print
        print('Sync status: ${service.state.syncStatus}');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      're-import is idempotent — same member count, no duplicate sessions',
      () async {
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo =
            DriftFrontingSessionRepository(db.frontingSessionsDao, null);

        final service = PluralKitSyncService(
          memberRepository: memberRepo,
          frontingSessionRepository: sessionRepo,
          syncDao: db.pluralKitSyncDao,
          tokenOverride: _token,
        );

        await service.performFullImport();

        final membersAfterFirst = await db.membersDao.getAllMembers();
        final sessionsAfterFirst = await db.frontingSessionsDao.getAllSessions();

        // Second import — should update existing members and skip duplicate switches.
        await service.performFullImport();

        final membersAfterSecond = await db.membersDao.getAllMembers();
        final sessionsAfterSecond =
            await db.frontingSessionsDao.getAllSessions();

        expect(membersAfterSecond.length, membersAfterFirst.length,
            reason: 'Second import should not create duplicate members');
        expect(sessionsAfterSecond.length, sessionsAfterFirst.length,
            reason: 'Second import should not create duplicate sessions');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
