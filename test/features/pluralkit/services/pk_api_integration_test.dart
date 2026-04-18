/// Integration test: full PluralKit sync pipeline using a real API token.
///
/// Excluded from CI. Run manually with a PluralKit token in PK_TOKEN:
///   PK_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_api_integration_test.dart
///
/// The test hits the live PluralKit API — use a dedicated test account,
/// not your real system.
///
/// Safety:
///   * If PK_TOKEN is unset, every test is skipped (never silently passes,
///     never mutates a real account).
///   * Every member created by a test is tagged with `_kPrefix` so that
///     the final `tearDownAll` sweep can find and delete leftovers even if
///     individual cleanups were missed (e.g. a crash mid-test).
///   * Each test also records IDs of things it creates in [_created] — the
///     teardown walks that list first, then does a prefix sweep as a
///     belt-and-suspenders pass.
@Tags(['integration'])
library;

import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/services/pk_member_matcher.dart';
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
    'PK_TOKEN env var not set — skipping live PluralKit integration tests';

/// Per-run prefix used for every test-created PK member. Cleanup sweeps any
/// member whose `name` starts with this so abandoned runs don't accumulate.
final String _kPrefix = _buildPrefix();

String _buildPrefix() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'prism-it-$ts-$rand-';
}

// ---------------------------------------------------------------------------
// Created-resource tracker
// ---------------------------------------------------------------------------

class _CreatedResources {
  final Set<String> memberIds = {};
  final Set<String> switchIds = {};
}

final _CreatedResources _created = _CreatedResources();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group(
    'PluralKit sync — full pipeline integration',
    () {
      late AppDatabase db;
      late PluralKitClient client;

      setUpAll(() {
        client = PluralKitClient(token: _token, httpClient: http.Client());
      });

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() => db.close());

      tearDownAll(() async {
        // Pass 1: walk the IDs we recorded this run.
        for (final id in _created.switchIds.toList()) {
          try {
            await client.deleteSwitch(id);
          } catch (_) {
            // Best-effort cleanup.
          }
        }
        for (final id in _created.memberIds.toList()) {
          try {
            await client.deleteMember(id);
          } catch (_) {
            // Best-effort cleanup.
          }
        }

        // Pass 2: prefix sweep. Catches anything a crashed test missed.
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
      });

      // ---------------------------------------------------------------------
      // Existing coverage (real import pipeline — does NOT mutate the account;
      // it only reads from PK).
      // ---------------------------------------------------------------------

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
          final sessionsAfterFirst =
              await db.frontingSessionsDao.getAllSessions();

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

      // ---------------------------------------------------------------------
      // New Phase 5 scaffolding — these exercise the write path. Each test
      // must record every created PK ID in [_created] so teardown cleans up.
      // ---------------------------------------------------------------------

      test(
        'push new member + PATCH + null-clear + GET round-trips through PK',
        () async {
          // 1. Create a member.
          final created = await client.createMember({
            'name': '${_kPrefix}push-a',
            'display_name': 'Push A',
            'pronouns': 'they/them',
          });
          _created.memberIds.add(created.id);

          // 2. PATCH display_name to a new value.
          final patched = await client.updateMember(created.id, {
            'display_name': 'Push A (updated)',
          });
          expect(patched.displayName, 'Push A (updated)');

          // 3. Null-clear display_name (explicit null, not omit).
          await client.updateMember(created.id, {
            'display_name': null,
          });

          // 4. GET verifies clearing took.
          final fetched =
              (await client.getMembers()).firstWhere((m) => m.id == created.id);
          expect(fetched.displayName, isNull,
              reason: 'Null PATCH must clear display_name on PK');
          expect(fetched.pronouns, 'they/them',
              reason: 'Unrelated fields must survive a null-clear PATCH');
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'push switch + PATCH timestamp + DELETE removes cleanly',
        () async {
          // Need a member to switch to.
          final m = await client.createMember({'name': '${_kPrefix}switch-a'});
          _created.memberIds.add(m.id);

          final t0 = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final sw = await client.createSwitch(
            [m.id],
            timestamp: t0,
          );
          _created.switchIds.add(sw.id);

          // PATCH the timestamp forward 10 minutes.
          final t1 = t0.add(const Duration(minutes: 10));
          final patched = await client.updateSwitch(
            sw.id,
            timestamp: t1,
          );
          // Assert the PATCH round-tripped to t1 (not merely "after t0").
          // Allow a 1-second tolerance for PK's timestamp rounding.
          final delta =
              patched.timestamp.toUtc().difference(t1.toUtc()).abs();
          expect(
            delta <= const Duration(seconds: 1),
            isTrue,
            reason:
                'Patched switch timestamp ${patched.timestamp.toUtc()} must '
                'equal requested t1 ${t1.toUtc()} within 1s tolerance '
                '(delta: $delta)',
          );

          // DELETE the switch. Cleanup should then be a no-op for this ID.
          await client.deleteSwitch(sw.id);
          _created.switchIds.remove(sw.id);
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'matcher suggests exact name matches on a real PK read-back',
        () async {
          // Seed two PK members with distinct names. The local side runs in
          // memory (matcher is pure) — we verify PkMemberMatcher pairs each
          // PK member with its same-named local against a live PK listing.
          final a = await client.createMember({'name': '${_kPrefix}overlap-a'});
          _created.memberIds.add(a.id);
          final b = await client.createMember({'name': '${_kPrefix}overlap-b'});
          _created.memberIds.add(b.id);

          // Fetch the PK member list so the matcher operates on real data
          // (including any other members on the account, which it must NOT
          // accidentally pair to our locals).
          final allPk = await client.getMembers();
          final ours = allPk
              .where((m) => m.name == a.name || m.name == b.name)
              .toList();
          expect(ours.length, 2,
              reason: 'Both seeded PK members must be visible');

          // Two local members matching by name — plus one unrelated local
          // that must not be paired to anything.
          final locals = <domain.Member>[
            domain.Member(
                id: 'local-a',
                name: a.name,
                createdAt: DateTime(2026)),
            domain.Member(
                id: 'local-b',
                name: b.name,
                createdAt: DateTime(2026)),
            domain.Member(
                id: 'local-noise',
                name: '${_kPrefix}zzz-noise',
                createdAt: DateTime(2026)),
          ];

          final suggestions =
              const PkMemberMatcher().suggest(locals, ours);

          // Exactly one suggestion per PK member.
          expect(suggestions.length, 2);

          final byPkUuid = {for (final s in suggestions) s.pkMember.uuid: s};

          final sa = byPkUuid[a.uuid]!;
          expect(sa.confidence, PkMatchConfidence.exact);
          expect(sa.suggestedLocal?.id, 'local-a');

          final sb = byPkUuid[b.uuid]!;
          expect(sb.confidence, PkMatchConfidence.exact);
          expect(sb.suggestedLocal?.id, 'local-b');

          // local-noise must not appear as a suggestion target.
          final suggestedLocalIds =
              suggestions.map((s) => s.suggestedLocal?.id).toSet();
          expect(suggestedLocalIds, isNot(contains('local-noise')));
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'member deletion removes it from the getMembers() listing',
        () async {
          // PluralKitClient has no per-id GET, so we can't assert a live 404
          // directly from this suite. Instead, verify the weaker but still
          // meaningful contract: a DELETEd member disappears from the
          // listing that the sync pipeline consumes. (The stale-link /
          // 404-translation path itself is covered by unit tests against a
          // faked HTTP client.)
          final m = await client.createMember({'name': '${_kPrefix}stale'});
          _created.memberIds.add(m.id);

          await client.deleteMember(m.id);
          _created.memberIds.remove(m.id);

          final still = await client.getMembers();
          expect(still.any((x) => x.id == m.id), isFalse,
              reason:
                  'After delete, member must disappear from the live listing');
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: _skipAll ? _skipReason : false,
      );
    },
    skip: _skipAll ? _skipReason : false,
  );
}
