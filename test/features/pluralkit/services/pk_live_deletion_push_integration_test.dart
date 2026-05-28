/// Live PluralKit integration coverage for Prism's pending deletion push path.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test account:
///
///   PK_TEST_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_deletion_push_integration_test.dart
///
/// The test creates one temporary PK member, one member-fronting switch, and a
/// later empty switch. The empty switch makes PK's current fronter set match
/// Prism's local empty active set, so the regular switch-push phase is a no-op
/// and the assertions focus on pending deletion push.
@Tags(['integration'])
library;

import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
// Use the pure Dart test package so Flutter's widget-test HTTP override does
// not intercept live PluralKit requests.
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_session;
import 'package:prism_plurality/domain/models/member.dart' as domain_member;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

String? get _tokenOrNull {
  final testToken = Platform.environment['PK_TEST_TOKEN'];
  if (testToken != null && testToken.trim().isNotEmpty) {
    return testToken.trim();
  }
  final token = Platform.environment['PK_TOKEN'];
  if (token != null && token.trim().isNotEmpty) return token.trim();
  return null;
}

String get _token => _tokenOrNull!;

bool get _skipAll => _tokenOrNull == null;

String get _skipReason =>
    'Set PK_TEST_TOKEN or PK_TOKEN to run live PluralKit deletion tests.';

final String _kPrefix = _buildPrefix();

String _buildPrefix() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'prism-delete-push-it-$ts-$rand-';
}

class _CreatedResources {
  final Set<String> memberIds = {};
  final Set<String> switchIds = {};
}

void main() {
  group('PluralKit deletion push - live API', () {
    test(
      'tombstoned linked switch and member are deleted on PK and unlinked',
      () async {
        final client = PluralKitClient(
          token: _token,
          httpClient: http.Client(),
          bus: PkSyncEventBus(),
        );
        final db = AppDatabase(NativeDatabase.memory());
        final created = _CreatedResources();

        try {
          final system = await client.getSystem();
          final runId = _kPrefix.substring(0, _kPrefix.length - 1);
          final localMemberId = 'local-member-$runId';
          final localSessionId = 'local-session-$runId';
          final pkMember = await client.createMember({
            'name': '${_kPrefix}target',
          });
          created.memberIds.add(pkMember.id);

          final baseTime = DateTime.now().toUtc().subtract(
            const Duration(seconds: 10),
          );
          final targetSwitch = await client.createSwitch([
            pkMember.id,
          ], timestamp: baseTime);
          created.switchIds.add(targetSwitch.id);

          final emptySwitch = await client.createSwitch(
            const <String>[],
            timestamp: baseTime.add(const Duration(seconds: 5)),
          );
          created.switchIds.add(emptySwitch.id);
          await _waitForCurrentSwitch(client, emptySwitch.id);

          await _seedConnectedPushState(db, system.id);

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
          final service = _makeService(
            db: db,
            memberRepo: memberRepo,
            sessionRepo: sessionRepo,
          );
          await service.loadState();

          await memberRepo.createMember(
            _localMember(id: localMemberId, pkMember: pkMember),
          );
          await sessionRepo.createSession(
            domain_session.FrontingSession(
              id: localSessionId,
              startTime: targetSwitch.timestamp,
              memberId: localMemberId,
              pluralkitUuid: targetSwitch.id,
            ),
          );

          await sessionRepo.deleteSession(localSessionId);
          await memberRepo.deleteMember(localMemberId);

          expect(
            await sessionRepo.getDeletedLinkedSessions(),
            hasLength(1),
            reason: 'Setup must queue exactly one linked session tombstone.',
          );
          expect(
            await memberRepo.getDeletedLinkedMembers(),
            hasLength(1),
            reason: 'Setup must queue exactly one linked member tombstone.',
          );

          final summary = await service.syncRecentData(
            direction: PkSyncDirection.pushOnly,
          );

          expect(summary, isNotNull);
          expect(summary!.switchesDeletedOnPk, 1);
          expect(summary.membersDeletedOnPk, 1);

          final recentSwitches = await client.getSwitches(limit: 100);
          expect(
            recentSwitches.any((sw) => sw.id == targetSwitch.id),
            isFalse,
            reason: 'The target switch must disappear from live PK history.',
          );
          await expectLater(
            client.getMember(pkMember.id),
            throwsA(
              isA<PluralKitApiError>().having(
                (e) => e.statusCode,
                'statusCode',
                404,
              ),
            ),
          );

          final localSession = await sessionRepo.getSessionById(localSessionId);
          expect(localSession, isNotNull);
          expect(localSession!.isDeleted, isTrue);
          expect(localSession.pluralkitUuid, isNull);

          final localMember = await memberRepo.getMemberById(localMemberId);
          expect(localMember, isNotNull);
          expect(localMember!.isDeleted, isTrue);
          expect(localMember.pluralkitId, isNull);
          expect(localMember.pluralkitUuid, isNull);
        } finally {
          await _cleanup(client, created);
          await db.close();
          client.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: _skipAll ? _skipReason : false,
    );
  }, skip: _skipAll ? _skipReason : false);
}

PluralKitSyncService _makeService({
  required AppDatabase db,
  required DriftMemberRepository memberRepo,
  required DriftFrontingSessionRepository sessionRepo,
}) {
  return PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    tokenOverride: _token,
    clientFactory: (token) => PluralKitClient(
      token: token,
      httpClient: http.Client(),
      bus: PkSyncEventBus(),
    ),
  );
}

Future<void> _seedConnectedPushState(AppDatabase db, String systemId) async {
  final now = DateTime.now().toUtc();
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      systemId: Value(systemId),
      directionConfirmed: const Value(true),
      mappingAcknowledged: const Value(true),
      linkedAt: Value(now.subtract(const Duration(minutes: 1))),
      lastSyncDate: Value(now.subtract(const Duration(minutes: 1))),
      fieldSyncConfig: Value(
        serializeFieldSyncConfigWithGlobalDirection(
          null,
          PkSyncDirection.pushOnly,
        ),
      ),
    ),
  );
}

domain_member.Member _localMember({
  required String id,
  required PKMember pkMember,
}) {
  return domain_member.Member(
    id: id,
    name: pkMember.name,
    emoji: '?',
    createdAt: DateTime.now().toUtc(),
    pluralkitId: pkMember.id,
    pluralkitUuid: pkMember.uuid,
  );
}

Future<PKSwitch> _waitForCurrentSwitch(
  PluralKitClient client,
  String switchId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (true) {
    final current = await client.getCurrentFronters();
    if (current?.id == switchId) return current!;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for current PK switch $switchId');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> _cleanup(PluralKitClient client, _CreatedResources created) async {
  for (final id in created.switchIds.toList().reversed) {
    try {
      await client.deleteSwitch(id);
    } catch (_) {
      // Best-effort cleanup.
    }
  }
  for (final id in created.memberIds.toList().reversed) {
    try {
      await client.deleteMember(id);
    } catch (_) {
      // Best-effort cleanup.
    }
  }
  try {
    final allMembers = await client.getMembers();
    for (final member in allMembers) {
      if (!member.name.startsWith(_kPrefix)) continue;
      try {
        await client.deleteMember(member.id);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  } catch (_) {
    // Best-effort cleanup.
  }
}
