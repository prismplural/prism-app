/// Live PluralKit repair harness for corrupted local fronting history.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test account:
///
///   PK_TEST_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_corrupted_history_repair_integration_test.dart
///
/// Safety:
///   * If PK_TEST_TOKEN/PK_TOKEN is unset, the test is skipped.
///   * Every temporary PK member uses a unique prefix.
///   * Switch/member cleanup is best-effort, including a final prefix sweep.
@Tags(['integration'])
library;

import 'dart:io' show Platform;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
// Use package:test so Flutter's widget-test HTTP override cannot intercept
// live PluralKit requests.
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_session;
import 'package:prism_plurality/domain/models/member.dart' as domain_member;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

void main() {
  final token = Platform.environment['PK_TEST_TOKEN']?.trim().isNotEmpty == true
      ? Platform.environment['PK_TEST_TOKEN']!.trim()
      : Platform.environment['PK_TOKEN']?.trim();
  final hasToken = token != null && token.isNotEmpty;

  group(
    'live PK corrupted history repair',
    skip: hasToken
        ? false
        : 'Set PK_TEST_TOKEN or PK_TOKEN to run the live PluralKit test.',
    () {
      test(
        'full re-import tombstones phantom PK-linked local sessions',
        () async {
          final liveHttpClient = http.Client();
          final liveClient = PluralKitClient(
            token: token!,
            httpClient: liveHttpClient,
            bus: PkSyncEventBus(),
          );
          final createdSwitchIds = <String>[];
          final createdMemberIds = <String>[];
          final prefix = _uniquePrefix();

          try {
            final authoritativeMember = await liveClient.createMember({
              'name': '${prefix}authoritative',
            });
            final phantomMember = await liveClient.createMember({
              'name': '${prefix}phantom',
            });
            createdMemberIds.addAll([authoritativeMember.id, phantomMember.id]);

            final entryRequestedAt = DateTime.now().toUtc().subtract(
              const Duration(hours: 6),
            );
            final exitRequestedAt = entryRequestedAt.add(
              const Duration(seconds: 45),
            );
            final authoritativeSwitch = await liveClient.createSwitch([
              authoritativeMember.id,
            ], timestamp: entryRequestedAt);
            createdSwitchIds.add(authoritativeSwitch.id);
            final clearSwitch = await liveClient.createSwitch(
              const [],
              timestamp: exitRequestedAt,
            );
            createdSwitchIds.add(clearSwitch.id);

            final db = AppDatabase(NativeDatabase.memory());
            addTearDown(db.close);

            final memberRepo = DriftMemberRepository(
              db.membersDao,
              null,
              pkSyncDao: db.pluralKitSyncDao,
            );
            final sessionRepo = DriftFrontingSessionRepository(
              db.frontingSessionsDao,
              null,
              pkSyncDao: db.pluralKitSyncDao,
            );
            final service = await _makeConnectedService(
              db: db,
              memberRepo: memberRepo,
              sessionRepo: sessionRepo,
              token: token,
            );

            await service.performFullImport();

            final authoritativeLocal = await _localMemberForPk(
              memberRepo,
              authoritativeMember,
            );
            final phantomLocal = await _localMemberForPk(
              memberRepo,
              phantomMember,
            );

            final authoritativeRowId = derivePkSessionId(
              authoritativeSwitch.id,
              authoritativeMember.uuid,
            );
            final importedAuthoritative = await sessionRepo.getSessionById(
              authoritativeRowId,
            );
            expect(importedAuthoritative, isNotNull);
            expect(importedAuthoritative!.isDeleted, isFalse);
            expect(importedAuthoritative.memberId, authoritativeLocal.id);
            expect(importedAuthoritative.pluralkitUuid, authoritativeSwitch.id);

            final bogusSwitchId = const Uuid().v4();
            final bogusSessionId = derivePkSessionId(
              bogusSwitchId,
              phantomMember.uuid,
            );
            await sessionRepo.createSession(
              domain_session.FrontingSession(
                id: bogusSessionId,
                startTime: authoritativeSwitch.timestamp.add(
                  const Duration(seconds: 10),
                ),
                memberId: phantomLocal.id,
                pluralkitUuid: bogusSwitchId,
              ),
            );

            final visibleBeforeRepair = await sessionRepo.getActiveSessions();
            expect(
              visibleBeforeRepair.map((session) => session.id),
              contains(bogusSessionId),
              reason: 'The fixture must start with a visible phantom session.',
            );

            await service.performFullImport();

            final repairedBogus = await sessionRepo.getSessionById(
              bogusSessionId,
            );
            expect(
              repairedBogus?.isDeleted ?? true,
              isTrue,
              reason:
                  'Corrective full import should remove the fake PK-linked '
                  'session from the live timeline.',
            );

            final visibleAfterRepair = await sessionRepo.getAllSessions();
            expect(
              visibleAfterRepair.map((session) => session.id),
              isNot(contains(bogusSessionId)),
            );
            final activeAfterRepair = await sessionRepo.getActiveSessions();
            expect(
              activeAfterRepair.map((session) => session.id),
              isNot(contains(bogusSessionId)),
            );
            expect(
              activeAfterRepair.where(
                (session) => session.memberId == phantomLocal.id,
              ),
              isEmpty,
              reason:
                  'The locally-added phantom member must not remain fronting '
                  'after PK history is replayed from the authoritative API.',
            );

            final repairedAuthoritative = await sessionRepo.getSessionById(
              authoritativeRowId,
            );
            expect(repairedAuthoritative, isNotNull);
            expect(repairedAuthoritative!.isDeleted, isFalse);
            expect(repairedAuthoritative.memberId, authoritativeLocal.id);
            expect(repairedAuthoritative.pluralkitUuid, authoritativeSwitch.id);
            expect(
              repairedAuthoritative.startTime,
              _sameInstantWithinOneSecond(authoritativeSwitch.timestamp),
            );
            expect(
              repairedAuthoritative.endTime,
              _sameInstantWithinOneSecond(clearSwitch.timestamp),
            );
            expect(
              visibleAfterRepair.map((session) => session.id),
              contains(authoritativeRowId),
            );
          } finally {
            for (final switchId in createdSwitchIds.reversed) {
              try {
                await liveClient.deleteSwitch(switchId);
              } catch (_) {
                // Best-effort cleanup.
              }
            }
            for (final memberId in createdMemberIds.reversed) {
              try {
                await liveClient.deleteMember(memberId);
              } catch (_) {
                // Best-effort cleanup.
              }
            }
            try {
              final members = await liveClient.getMembers();
              for (final member in members) {
                if (member.name.startsWith(prefix)) {
                  try {
                    await liveClient.deleteMember(member.id);
                  } catch (_) {
                    // Best-effort cleanup.
                  }
                }
              }
            } catch (_) {
              // Best-effort cleanup.
            }
            liveClient.dispose();
            liveHttpClient.close();
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    },
  );
}

Future<PluralKitSyncService> _makeConnectedService({
  required AppDatabase db,
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
  required String token,
}) async {
  final now = DateTime.now().toUtc();
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      systemId: const Value('live-corrupted-history-repair-test'),
      directionConfirmed: const Value(true),
      mappingAcknowledged: const Value(true),
      linkedAt: Value(now.subtract(const Duration(minutes: 1))),
    ),
  );

  final service = PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    tokenOverride: token,
  );
  await service.loadState();
  return service;
}

Future<domain_member.Member> _localMemberForPk(
  DriftMemberRepository memberRepo,
  PKMember pkMember,
) async {
  final members = await memberRepo.getAllMembers();
  return members.singleWhere((member) => member.pluralkitUuid == pkMember.uuid);
}

Matcher _sameInstantWithinOneSecond(DateTime expected) {
  return predicate<DateTime?>((actual) {
    if (actual == null) return false;
    final delta = actual.toUtc().difference(expected.toUtc()).abs();
    return delta <= const Duration(seconds: 1);
  }, 'same instant as ${expected.toUtc().toIso8601String()} within 1s');
}

String _uniquePrefix() {
  final runId = const Uuid().v4().split('-').first;
  return 'prism-live-corrupt-repair-$runId-';
}
