/// Integration test: live PluralKit current fronter is surfaced for review
/// when Prism has no local mapping yet.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test token:
///
///   PK_TEST_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_unmapped_current_fronter_integration_test.dart
///
/// Safety:
///   * If PK_TEST_TOKEN/PK_TOKEN is unset, the test is skipped.
///   * The test creates one temporary PK member and switch with a unique prefix.
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

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

void main() {
  final token = Platform.environment['PK_TEST_TOKEN']?.trim().isNotEmpty == true
      ? Platform.environment['PK_TEST_TOKEN']!.trim()
      : Platform.environment['PK_TOKEN']?.trim();
  final hasToken = token != null && token.isNotEmpty;

  group(
    'live PK unmapped current fronter',
    skip: hasToken
        ? false
        : 'Set PK_TEST_TOKEN or PK_TOKEN to run the live PluralKit test.',
    () {
      test(
        'fronts-only pull reports unmapped notice before import, then creates '
        'the correct session after resolving it',
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
            final pkMember = await liveClient.createMember({
              'name': '${prefix}current',
            });
            createdMemberIds.add(pkMember.id);

            final liveSwitch = await liveClient.createSwitch([pkMember.id]);
            createdSwitchIds.add(liveSwitch.id);
            final current = await _waitForCurrentSwitch(
              liveClient,
              liveSwitch.id,
            );

            final db = AppDatabase(NativeDatabase.memory());
            addTearDown(db.close);

            final memberRepo = DriftMemberRepository(db.membersDao, null);
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

            final firstSummary = await service.syncLiveFrontersOnly(
              direction: PkSyncDirection.pullOnly,
              isManual: true,
            );

            expect(firstSummary, isNotNull);
            expect(firstSummary!.switchesPulled, 0);
            expect(firstSummary.switchesPushed, 0);
            expect(firstSummary.observedLiveFronters, isTrue);
            expect(firstSummary.observedLiveFrontersDismissalKey, isNotEmpty);
            expect(firstSummary.staleLinkMessages, isEmpty);

            final notice = firstSummary.liveUnmappedFronters;
            expect(notice, isNotNull);
            expect(notice!.switchId, current.id);
            expect(notice.sortedPkIds, [pkMember.id]);
            expect(notice.refs, hasLength(1));
            expect(notice.refs.single.pkId, pkMember.id);
            expect(notice.refs.single.pkUuid, pkMember.uuid);
            expect(notice.refs.single.name, pkMember.name);
            expect(await sessionRepo.getAllSessions(), isEmpty);

            final imported = await service.importCurrentFronter(
              notice.refs.single,
            );
            expect(imported.pluralkitId, pkMember.id);
            expect(imported.pluralkitUuid, pkMember.uuid);

            // The post-resolution re-pull models the mapping controller's
            // automatic refresh, not a second manual tap — a manual pull
            // inside 60s now throws PkManualSyncCooldownException (2026-06
            // PK audit M1, wave 4).
            final secondSummary = await service.syncLiveFrontersOnly(
              direction: PkSyncDirection.pullOnly,
              isManual: false,
            );

            expect(secondSummary, isNotNull);
            expect(secondSummary!.switchesPulled, 1);
            expect(secondSummary.liveUnmappedFronters, isNull);

            final sessions = await sessionRepo.getAllSessions();
            expect(sessions, hasLength(1));
            expect(sessions.single.memberId, imported.id);
            expect(sessions.single.pluralkitUuid, current.id);
            expect(sessions.single.endTime, isNull);
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
        timeout: const Timeout(Duration(minutes: 2)),
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
      systemId: const Value('live-unmapped-fronter-test'),
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

String _uniquePrefix() {
  final runId = const Uuid().v4().split('-').first;
  return 'prism-live-unmapped-current-$runId-';
}
