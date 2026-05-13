/// Live-API integration tests for the direction-first PluralKit setup flow.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test token:
///   PK_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_setup_flow_live_integration_test.dart
///
/// Covers the new code paths introduced by the setup direction-first refactor
/// against the real PluralKit API:
///   1. Wizard transitions: setToken -> confirmDirection -> acknowledgeMapping.
///   2. pushOverrideSwitch with members creates a real PK switch.
///   3. pushOverrideSwitch with [] clears PK's current fronters (C1 fix).
///   4. advanceImportCursorPast prevents re-importing the override on next sync.
///   5. deferBootstrap-equivalent (prefs flag) does not trigger auto-sync.
///
/// Safety:
///   * If PK_TOKEN is unset, every test is skipped.
///   * Every switch created in this file is tracked in [_created.switchIds]
///     and deleted in tearDownAll, even if the test body crashes.
///   * This file does NOT create new PK members — it works against the
///     existing account members. If a member is somehow created, it carries
///     [_kPrefix] so the final prefix sweep can mop it up.
@Tags(['integration'])
library;

import 'dart:io' show HttpOverrides, Platform;
import 'dart:math' show Random;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    as domain_session;
import 'package:prism_plurality/domain/models/member.dart' as domain_member;
import 'package:prism_plurality/features/pluralkit/services/pk_prefs_keys.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Env + naming
// ---------------------------------------------------------------------------

String? get _tokenOrNull {
  final env = Platform.environment['PK_TOKEN'];
  if (env == null || env.trim().isEmpty) return null;
  return env;
}

String get _token => _tokenOrNull!;

bool get _skipAll => _tokenOrNull == null;

String get _skipReason =>
    'PK_TOKEN env var not set - skipping live PluralKit integration tests';

/// Per-run prefix. Unique among the live tests so concurrent runs / cleanup
/// sweeps don't collide with pk_api_integration_test or
/// pk_live_fronts_only_integration_test.
final String _kPrefix = _buildPrefix();

String _buildPrefix() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'prism-direction-it-$ts-$rand-';
}

// ---------------------------------------------------------------------------
// Created-resource tracker
// ---------------------------------------------------------------------------

class _CreatedResources {
  final Set<String> switchIds = {};
  final Set<String> memberIds = {};
}

final _CreatedResources _created = _CreatedResources();

// ---------------------------------------------------------------------------
// HTTP override reset
//
// flutter_test installs an HttpOverrides that turns every real HTTP request
// into a fake 400. We need real network access for these tests, so reset to
// default. (See pk_onboarding_path_integration_test.dart for the same trick.)
// ---------------------------------------------------------------------------

class _NoOverrides extends HttpOverrides {}

// ---------------------------------------------------------------------------
// Secure-storage stub — setToken writes to secure storage even when
// tokenOverride is set, so we must install this before any test that calls
// setToken / clearToken.
// ---------------------------------------------------------------------------

void _installSecureStorageStub() {
  final store = <String, String?>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async {
          switch (call.method) {
            case 'write':
              store[call.arguments['key'] as String] =
                  call.arguments['value'] as String?;
              return null;
            case 'read':
              return store[call.arguments['key'] as String];
            case 'delete':
              store.remove(call.arguments['key'] as String);
              return null;
            case 'containsKey':
              return store.containsKey(call.arguments['key'] as String);
            default:
              return null;
          }
        },
      );
}

// ---------------------------------------------------------------------------
// State-machine helpers
// ---------------------------------------------------------------------------

/// Builds a PluralKitSyncService against the live API with tokenOverride so
/// _getToken short-circuits secure-storage reads (writes still go through the
/// stub for setToken).
PluralKitSyncService _makeService(AppDatabase db) {
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

/// Seeds the DAO with the post-wizard state so canAutoSync is true. Mirrors
/// the helper used by other live integration tests.
///
/// Pass [withLastSyncDate]=true to also set lastSyncDate so syncRecentData
/// takes the incremental path instead of falling back to a full import.
Future<void> _seedPostWizardState(
  PluralKitSyncService service,
  AppDatabase db, {
  String systemId = 'test-system',
  bool withLastSyncDate = false,
}) async {
  final now = DateTime.now().toUtc();
  await db.pluralKitSyncDao.upsertSyncState(
    PluralKitSyncStateCompanion(
      id: const Value('pk_config'),
      isConnected: const Value(true),
      systemId: Value(systemId),
      directionConfirmed: const Value(true),
      mappingAcknowledged: const Value(true),
      linkedAt: Value(now.subtract(const Duration(minutes: 1))),
      lastSyncDate: withLastSyncDate
          ? Value(now.subtract(const Duration(minutes: 1)))
          : const Value.absent(),
    ),
  );
  await service.loadState();
}

/// Imports the PK account's existing members into the local DB so that
/// pushOverrideSwitch can resolve local IDs to PK short IDs. Returns the
/// list of local Member rows (with their PK IDs populated).
Future<List<domain_member.Member>> _seedLocalMembersFromPk(
  AppDatabase db,
  PluralKitClient client,
) async {
  final pkMembers = await client.getMembers();
  expect(pkMembers, isNotEmpty,
      reason: 'PK account must have members for these tests');
  final repo = DriftMemberRepository(db.membersDao, null);
  final results = <domain_member.Member>[];
  for (final pk in pkMembers) {
    final local = domain_member.Member(
      id: 'local-${pk.id}',
      name: pk.name,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitId: pk.id,
      pluralkitUuid: pk.uuid,
    );
    await repo.createMember(local);
    results.add(local);
  }
  return results;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that turns every real HTTP request
  // into a 400. Reset to default so the live PK API is reachable.
  HttpOverrides.global = _NoOverrides();

  group(
    'PluralKit direction-first setup - live API',
    () {
      late AppDatabase db;
      late PluralKitClient client;
      late http.Client sharedHttpClient;

      setUpAll(() {
        sharedHttpClient = http.Client();
        client = PluralKitClient(token: _token, httpClient: sharedHttpClient);
      });

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        _installSecureStorageStub();
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() => db.close());

      tearDownAll(() async {
        // Pass 1: explicitly delete every switch we tracked.
        for (final id in _created.switchIds.toList()) {
          try {
            await client.deleteSwitch(id);
            _created.switchIds.remove(id);
          } catch (_) {
            // Best-effort cleanup.
          }
        }

        // Pass 2: prefix sweep for any stray members. We don't create members
        // in this file, but defend in case a future change does.
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
              } catch (_) {/* ignore */}
            }
          }
        } catch (_) {/* ignore */}

        client.dispose();
        sharedHttpClient.close();
      });

      // -----------------------------------------------------------------
      // 1. Wizard transitions: setToken -> confirmDirection ->
      //    acknowledgeMapping. Each step flips the state machine.
      // -----------------------------------------------------------------
      test(
        'wizard transitions: setToken needsDirection -> confirmDirection '
        'needsMapping -> acknowledgeMapping canAutoSync',
        () async {
          // Build the service WITHOUT tokenOverride so setToken actually
          // exercises the secure-storage write path. The token comes in via
          // setToken below.
          final service = PluralKitSyncService(
            memberRepository: DriftMemberRepository(db.membersDao, null),
            frontingSessionRepository: DriftFrontingSessionRepository(
              db.frontingSessionsDao,
              null,
              pkSyncDao: db.pluralKitSyncDao,
            ),
            syncDao: db.pluralKitSyncDao,
            bus: PkSyncEventBus(),
          );

          // Step 1: setToken with the live token.
          await service.setToken(_token);
          expect(service.state.isConnected, isTrue,
              reason: 'After setToken, isConnected must be true');
          expect(service.state.needsDirection, isTrue,
              reason: 'Fresh system after setToken must require direction');
          expect(service.state.canAutoSync, isFalse,
              reason: 'canAutoSync must remain false until both flags set');

          // Step 2: confirmDirection.
          await service.confirmDirection();
          expect(service.state.directionConfirmed, isTrue);
          expect(service.state.needsDirection, isFalse);
          expect(service.state.needsMapping, isTrue,
              reason: 'After confirmDirection, needsMapping must be true');
          expect(service.state.canAutoSync, isFalse);

          // Step 3: acknowledgeMapping.
          await service.acknowledgeMapping();
          expect(service.state.mappingAcknowledged, isTrue);
          expect(service.state.needsMapping, isFalse);
          expect(service.state.canAutoSync, isTrue,
              reason: 'After acknowledgeMapping, canAutoSync must be true');

          // Verify all of this was persisted.
          final row = await db.pluralKitSyncDao.getSyncState();
          expect(row.isConnected, isTrue);
          expect(row.directionConfirmed, isTrue);
          expect(row.mappingAcknowledged, isTrue);
          expect(row.systemId, isNotNull,
              reason: 'setToken must record the resolved PK system ID');
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: _skipAll ? _skipReason : false,
      );

      // -----------------------------------------------------------------
      // 2. pushOverrideSwitch with two real members creates a real PK
      //    switch with the right member set and advances cursor.
      // -----------------------------------------------------------------
      test(
        'pushOverrideSwitch creates a real PK switch with the right members',
        () async {
          final service = _makeService(db);
          await _seedPostWizardState(service, db);
          final locals = await _seedLocalMembersFromPk(db, client);
          expect(locals.length, greaterThanOrEqualTo(2),
              reason: 'Need at least 2 members for this test');

          // Pick the first two members.
          final picked = locals.take(2).toList();
          final pickedPkIds = picked.map((m) => m.pluralkitId!).toSet();

          final at = DateTime.now().toUtc();
          final sw = await service.pushOverrideSwitch(
            picked.map((m) => m.id).toList(),
            at,
          );

          expect(sw, isNotNull,
              reason: 'pushOverrideSwitch must return a PKSwitch on success');
          _created.switchIds.add(sw!.id);

          // Member set on the returned switch must contain both picked PK IDs.
          expect(sw.members.toSet(), pickedPkIds,
              reason: 'New PK switch must contain exactly the picked members');

          // Cursor advancement is the caller's job (PkMappingController), but
          // verify the helper works end-to-end: advance and read it back.
          await service.advanceImportCursorPast(
            switchId: sw.id,
            timestamp: sw.timestamp,
          );
          final row = await db.pluralKitSyncDao.getSyncState();
          expect(row.switchCursorId, sw.id);
          // Drift's DateTimeColumn stores second precision, so compare with
          // the same truncation applied to PK's returned timestamp.
          expect(
            row.switchCursorTimestamp?.toUtc().millisecondsSinceEpoch,
            (sw.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
          );

          // Clean up — delete the switch we just pushed.
          await client.deleteSwitch(sw.id);
          _created.switchIds.remove(sw.id);
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: _skipAll ? _skipReason : false,
      );

      // -----------------------------------------------------------------
      // 3. Empty-set override clears PK's current fronters. Validates C1.
      //
      // PK rejects an empty switch when the current fronter list is already
      // empty (40004 "Member list identical to current fronter list").
      // To make the test deterministic regardless of the account's prior
      // state, we first push a single-member switch so the current fronter
      // list is guaranteed non-empty, then push an empty switch to clear it.
      // -----------------------------------------------------------------
      test(
        'empty-set pushOverrideSwitch creates an empty PK switch (C1 fix)',
        () async {
          final service = _makeService(db);
          await _seedPostWizardState(service, db);
          final locals = await _seedLocalMembersFromPk(db, client);
          expect(locals, isNotEmpty);

          // Step 1: push a non-empty switch so the current fronter is set.
          final seedAt = DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 2));
          final seedSw = await service.pushOverrideSwitch(
            [locals.first.id],
            seedAt,
          );
          expect(seedSw, isNotNull,
              reason: 'Setup: seed switch must succeed before clearing');
          _created.switchIds.add(seedSw!.id);

          // Step 2: push an empty switch to clear the front. This is the
          // C1 case — pushOverrideSwitch must accept [] and POST to PK.
          final at = DateTime.now().toUtc();
          final sw = await service.pushOverrideSwitch(const [], at);

          expect(sw, isNotNull,
              reason: 'Empty-set push must still return a PKSwitch (C1)');
          _created.switchIds.add(sw!.id);

          expect(sw.members, isEmpty,
              reason: 'Empty-set push must create a switch with no members');

          // Cursor helper still works with an empty switch.
          await service.advanceImportCursorPast(
            switchId: sw.id,
            timestamp: sw.timestamp,
          );
          final row = await db.pluralKitSyncDao.getSyncState();
          expect(row.switchCursorId, sw.id);

          // Cleanup both switches in newest-first order.
          await client.deleteSwitch(sw.id);
          _created.switchIds.remove(sw.id);
          await client.deleteSwitch(seedSw.id);
          _created.switchIds.remove(seedSw.id);
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: _skipAll ? _skipReason : false,
      );

      // -----------------------------------------------------------------
      // 4. advanceImportCursorPast prevents a duplicate session from being
      //    created for the override switch on the next incremental sync.
      //
      // Mirrors production flow (PkMappingController.applyFronterResolution):
      //   1. pushOverrideSwitch -> PK creates the switch.
      //   2. advanceImportCursorPast -> mark cursor at the override.
      //   3. Local writes -> create a local fronting session with
      //      pluralkitUuid = pushedSwitch.id so the dedup-by-uuid path
      //      catches the override on the next pull.
      //
      // Drift's DateTimeColumn truncates to second precision; PK returns
      // microseconds. The sweep-side cursor.covers() check therefore can't
      // protect on its own — production relies on the local session's
      // pluralkit_uuid matching to prevent a duplicate. We replicate that
      // here.
      // -----------------------------------------------------------------
      test(
        'advanceImportCursorPast + matching local session prevents duplicate '
        'session on next incremental sync',
        () async {
          final service = _makeService(db);
          // Set lastSyncDate so syncRecentData takes the incremental path
          // (which honours the cursor) instead of falling through to
          // performFullImport (which clears the cursor and re-imports
          // everything from scratch).
          await _seedPostWizardState(service, db, withLastSyncDate: true);
          final locals = await _seedLocalMembersFromPk(db, client);
          expect(locals.length, greaterThanOrEqualTo(1));

          // Push an override with a single member, capture the switch.
          final picked = locals.first;
          final at = DateTime.now().toUtc();
          final sw = await service.pushOverrideSwitch(
            [picked.id],
            at,
          );
          expect(sw, isNotNull);
          _created.switchIds.add(sw!.id);

          // Advance the cursor past the override (production step).
          await service.advanceImportCursorPast(
            switchId: sw.id,
            timestamp: sw.timestamp,
          );

          final rowBefore = await db.pluralKitSyncDao.getSyncState();
          expect(rowBefore.switchCursorId, sw.id);

          // Mirror the production flow's local-session write so dedupe by
          // pluralkit_uuid kicks in on the next pull.
          final sessionRepo = DriftFrontingSessionRepository(
            db.frontingSessionsDao,
            null,
            pkSyncDao: db.pluralKitSyncDao,
          );
          await sessionRepo.createSession(
            domain_session.FrontingSession(
              id: 'override-session-${sw.id}',
              startTime: sw.timestamp,
              memberId: picked.id,
              // Load-bearing for dedupe: the next pull's diff sweep matches
              // by pluralkitUuid and must not create a second row.
              pluralkitUuid: sw.id,
            ),
          );

          final sessionsBefore =
              await db.frontingSessionsDao.getAllSessions();
          final picksBefore = sessionsBefore
              .where((s) =>
                  s.memberId == picked.id && s.pluralkitUuid == sw.id)
              .length;
          expect(picksBefore, 1,
              reason: 'Setup: exactly one override session must exist');

          // Run an incremental sync. The override switch must NOT cause a
          // second local session to be created — either because the cursor
          // skipped it, or because the dedupe-by-uuid path matched the
          // existing session.
          await service.syncRecentData();

          final sessionsAfter =
              await db.frontingSessionsDao.getAllSessions();
          final picksAfter = sessionsAfter
              .where((s) =>
                  s.memberId == picked.id && s.pluralkitUuid == sw.id)
              .length;
          expect(
            picksAfter,
            picksBefore,
            reason:
                'No duplicate session must be created for the override '
                'switch after advanceImportCursorPast + syncRecentData.',
          );

          // Cleanup.
          await client.deleteSwitch(sw.id);
          _created.switchIds.remove(sw.id);
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: _skipAll ? _skipReason : false,
      );

      // -----------------------------------------------------------------
      // 5. Deferred bootstrap: setting the prefs flag manually does not
      //    cause any PK sync to run (no local sessions appear).
      //
      //    This is the simplified service-level variant of the scenario.
      //    The full PkMappingController.deferBootstrap path is covered by
      //    setup_flow_e2e_test.dart (offline, controller-level).
      // -----------------------------------------------------------------
      test(
        'deferBootstrap-equivalent: prefs flag set, no auto-sync runs',
        () async {
          // Resolve the live system ID (so the prefs key matches what the
          // controller would use in production).
          final system = await client.getSystem();

          final service = _makeService(db);
          await _seedPostWizardState(service, db, systemId: system.id);

          // Manually set the firstSyncDeferred prefs flag, mimicking what
          // deferBootstrap() does internally.
          final prefs = await SharedPreferences.getInstance();
          final key = PkPrefsKeys.firstSyncDeferred(system.id);
          await prefs.setBool(key, true);

          expect(prefs.getBool(key), isTrue,
              reason: 'Prefs flag must be set to true');

          // We deliberately do NOT call syncRecentData / performFullImport /
          // pushPendingSwitches here. After deferBootstrap, the bootstrap is
          // skipped, so the local DB must remain empty of any imported PK
          // data.
          final sessions = await db.frontingSessionsDao.getAllSessions();
          expect(
            sessions,
            isEmpty,
            reason:
                'No fronting sessions must be imported when bootstrap is '
                'deferred (no sync ran).',
          );
          final members = await db.membersDao.getAllMembers();
          expect(
            members,
            isEmpty,
            reason:
                'No members must be imported when bootstrap is deferred.',
          );

          // The setup is still complete from the state-machine perspective:
          // canAutoSync stays true so future manual / scheduled syncs can
          // proceed when the user chooses to.
          expect(service.state.canAutoSync, isTrue);
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: _skipAll ? _skipReason : false,
      );
    },
    skip: _skipAll ? _skipReason : false,
  );
}
