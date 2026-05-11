/// Integration tests: live-fronts-only PluralKit sync against the real API.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test token:
///   PK_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_fronts_only_integration_test.dart
///
/// Safety:
///   * If PK_TOKEN is unset, every test is skipped.
///   * Every PK member this file creates uses [_kPrefix].
///   * Switches and members are tracked by ID and deleted in tearDownAll.
///   * A final prefix sweep removes any matching member left by a crashed run.
@Tags(['integration'])
library;

import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_session;
import 'package:prism_plurality/domain/models/member.dart' as domain_member;
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

String? get _tokenOrNull {
  final env = Platform.environment['PK_TOKEN'];
  if (env == null || env.trim().isEmpty) return null;
  return env;
}

String get _token => _tokenOrNull!;

bool get _skipAll => _tokenOrNull == null;

String get _skipReason =>
    'PK_TOKEN env var not set - skipping live PluralKit integration tests';

final String _kPrefix = _buildPrefix();

String _buildPrefix() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'prism-live-fronts-e2e-$ts-$rand-';
}

class _CreatedResources {
  final Set<String> memberIds = {};
  final Set<String> switchIds = {};
}

final _created = _CreatedResources();

void main() {
  group(
    'PluralKit live-fronts-only sync - live API',
    () {
      late AppDatabase db;
      late PluralKitClient client;
      late http.Client sharedHttpClient;

      setUpAll(() {
        sharedHttpClient = http.Client();
        client = PluralKitClient(token: _token, httpClient: sharedHttpClient);
      });

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() => db.close());

      tearDownAll(() async {
        for (final id in _created.switchIds.toList()) {
          try {
            await client.deleteSwitch(id);
            _created.switchIds.remove(id);
          } catch (_) {
            // Best-effort cleanup.
          }
        }
        for (final id in _created.memberIds.toList()) {
          try {
            await client.deleteMember(id);
            _created.memberIds.remove(id);
          } catch (_) {
            // Best-effort cleanup.
          }
        }

        try {
          final allMembers = await client.getMembers();
          for (final m in allMembers) {
            if (m.name.startsWith(_kPrefix)) {
              try {
                await client.deleteMember(m.id);
              } catch (_) {
                // Best-effort cleanup.
              }
            }
          }
        } catch (_) {
          // Best-effort cleanup.
        }

        client.dispose();
        sharedHttpClient.close();
      });

      test(
        'pull-only imports only the current switch and leaves full-sync cursor '
        'untouched',
        () async {
          final oldMember = await _createPkMember(client, 'pull-old');
          final currentMember = await _createPkMember(client, 'pull-current');
          final oldSwitch = await client.createSwitch([oldMember.id]);
          _created.switchIds.add(oldSwitch.id);
          final currentSwitch = await client.createSwitch([currentMember.id]);
          _created.switchIds.add(currentSwitch.id);
          await _waitForCurrentSwitch(client, currentSwitch.id);

          final service = await _makeConnectedService(db);
          final memberRepo = DriftMemberRepository(db.membersDao, null);
          await _seedLocalMember(memberRepo, oldMember, 'local-old');
          await _seedLocalMember(memberRepo, currentMember, 'local-current');

          final cursorTimestamp = DateTime.utc(2026, 1, 1, 12);
          await db.pluralKitSyncDao.upsertSyncState(
            PluralKitSyncStateCompanion(
              id: const Value('pk_config'),
              switchCursorTimestamp: Value(cursorTimestamp),
              switchCursorId: const Value('unchanged-cursor'),
            ),
          );
          await service.loadState();

          final summary = await service.syncLiveFrontersOnly(
            direction: PkSyncDirection.pullOnly,
            isManual: true,
          );

          expect(summary, isNotNull);
          expect(summary!.switchesPulled, 1);
          expect(summary.switchesPushed, 0);

          final sessions = await db.frontingSessionsDao.getAllSessions();
          expect(sessions.map((s) => s.pluralkitUuid), [currentSwitch.id]);
          expect(sessions.single.memberId, 'local-current');

          final row = await db.pluralKitSyncDao.getSyncState();
          expect(row.switchCursorTimestamp?.toUtc(), cursorTimestamp);
          expect(row.switchCursorId, 'unchanged-cursor');
          expect(row.lastSyncDate, isNull);
          expect(row.lastManualSyncDate, isNotNull);
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'push-only creates a PK switch from the local active front',
        () async {
          final pushedMember = await _createPkMember(client, 'push-current');
          final service = await _makeConnectedService(db);
          final memberRepo = DriftMemberRepository(db.membersDao, null);
          final sessionRepo = DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
          );
          await _seedLocalMember(memberRepo, pushedMember, 'local-pushed');
          await sessionRepo.createSession(
            domain_session.FrontingSession(
              id: 'local-active-session',
              startTime: DateTime.now().toUtc(),
              memberId: 'local-pushed',
            ),
          );

          await service.loadState();
          final summary = await service.syncLiveFrontersOnly(
            direction: PkSyncDirection.pushOnly,
            isManual: true,
          );

          expect(summary, isNotNull);
          expect(summary!.switchesPulled, 0);
          expect(summary.switchesPushed, 1);

          final current = await _waitForCurrentMemberSet(client, {
            pushedMember.id,
          });
          _created.switchIds.add(current.id);
          expect(current.members, contains(pushedMember.id));

          final sessions = await db.frontingSessionsDao.getAllSessions();
          expect(sessions.single.pluralkitUuid, current.id);

          final row = await db.pluralKitSyncDao.getSyncState();
          expect(row.lastSyncDate, isNull);
          expect(row.lastManualSyncDate, isNotNull);
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: _skipAll ? _skipReason : false,
      );
    },
    skip: _skipAll ? _skipReason : false,
  );
}

Future<PluralKitSyncService> _makeConnectedService(AppDatabase db) async {
  final now = DateTime.now().toUtc();
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      mappingAcknowledged: const Value(true),
      linkedAt: Value(now.subtract(const Duration(minutes: 1))),
    ),
  );

  return PluralKitSyncService(
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
      pkSyncDao: db.pluralKitSyncDao,
    ),
    syncDao: db.pluralKitSyncDao,
    bus: PkSyncEventBus(),
    tokenOverride: _token,
  );
}

Future<void> _seedLocalMember(
  DriftMemberRepository repo,
  dynamic pkMember,
  String localId,
) {
  return repo.createMember(
    domain_member.Member(
      id: localId,
      name: pkMember.name,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitId: pkMember.id,
      pluralkitUuid: pkMember.uuid,
    ),
  );
}

Future<dynamic> _createPkMember(PluralKitClient client, String suffix) async {
  final member = await client.createMember({'name': '$_kPrefix$suffix'});
  _created.memberIds.add(member.id);
  return member;
}

Future<dynamic> _waitForCurrentSwitch(
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

Future<dynamic> _waitForCurrentMemberSet(
  PluralKitClient client,
  Set<String> memberIds,
) async {
  final expected = memberIds.toList()..sort();
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (true) {
    final current = await client.getCurrentFronters();
    final actual = [...?current?.members]..sort();
    if (actual.length == expected.length) {
      var same = true;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != expected[i]) {
          same = false;
          break;
        }
      }
      if (same && current != null) return current;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for current PK member set $expected');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
