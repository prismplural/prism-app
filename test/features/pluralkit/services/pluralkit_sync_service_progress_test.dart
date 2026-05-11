/// Phase 2 — per-member progress tests.
///
/// Covers the new `onProgress` callback wired through `_importMembers` and the
/// three callers (`_runFullImportWithClient`, `importMembersOnly`,
/// `importFromFile`) that map the member-import phase to its own progress
/// band. See docs/plans/pk-megasystem-import.md Phase 2.
///
/// Why these tests matter: on a megasystem (1500+ members on mobile data),
/// the import loop is silent for 10-30 minutes without per-member progress.
/// Bug 2 in the plan calls this out — the UI freezes at the band start until
/// the loop ends. The cadence (every 10 members + last) keeps emit churn low
/// while still showing the user that work is happening.
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Minimal fake PluralKit client returning a fixed system + members list, no
/// switches, no groups. Used so the full-import path can run end-to-end with
/// only the member loop doing meaningful work.
class _ProgressFakeClient implements PluralKitClient {
  _ProgressFakeClient({required this.members});

  final List<PKMember> members;

  @override
  Future<PKSystem> getSystem() async =>
      const PKSystem(id: 'sys-1', name: 'Test System');

  @override
  Future<List<PKMember>> getMembers() async => members;

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  void dispose() {}

  // -- unused stubs ---------------------------------------------------------
  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) =>
      throw UnimplementedError();
  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) async {}
  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async {}
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async {}
}

/// Generate a deterministic list of fake PK members of size [count].
List<PKMember> _fakeMembers(int count) => List.generate(
      count,
      (i) => PKMember(
        // PK short id (5 chars) is required for the full-import path's
        // member-resolution map. Pad/format so IDs stay unique.
        id: 'm${i.toString().padLeft(4, '0')}',
        uuid: 'uuid-$i',
        name: 'Member $i',
      ),
    );

PkBannerCacheService _bannerCacheService() => PkBannerCacheService(
      fetcher: (_) async => Uint8List.fromList(const [1, 2, 3]),
      normalizer: (bytes) async => bytes,
    );

PluralKitSyncService _makeService({
  required AppDatabase db,
  required PluralKitClient client,
}) {
  return PluralKitSyncService(
    memberRepository: DriftMemberRepository(db.membersDao, null),
    frontingSessionRepository: DriftFrontingSessionRepository(
      db.frontingSessionsDao,
      null,
    ),
    syncDao: db.pluralKitSyncDao,
    tokenOverride: 'test-token',
    clientFactory: (_) => client,
    bannerCacheService: _bannerCacheService(),
  );
}

/// Captures every state emitted by the service. The PluralKit service emits
/// many states besides member progress ("Fetching system info...", "Importing
/// groups...", etc.), so callers filter by the "Importing member" status
/// prefix when checking per-member emissions.
class _StateRecorder {
  final List<PluralKitSyncState> states = [];

  void attach(PluralKitSyncService service) {
    service.onStateChanged = states.add;
  }

  /// Only the emissions corresponding to the per-member loop's progress.
  List<PluralKitSyncState> get memberEmissions => states
      .where((s) => s.syncStatus.startsWith('Importing member '))
      .toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  group('per-member progress cadence', () {
    test(
      'N=25 emits at i=0, i=10, i=20, i=24 — four total per-member emissions',
      () async {
        final client = _ProgressFakeClient(members: _fakeMembers(25));
        final service = _makeService(db: db, client: client);
        final recorder = _StateRecorder()..attach(service);

        await service.importMembersOnly();

        // The cadence is i % 10 == 0 (i=0, 10, 20) plus the last index
        // (i=24). The `||` does not double-fire because each i runs once.
        // Expected currents (current = i + 1): 1, 11, 21, 25.
        final currents = recorder.memberEmissions
            .map((s) => _parseCurrent(s.syncStatus))
            .toList();
        expect(
          currents,
          [1, 11, 21, 25],
          reason:
              'For 25 members, _importMembers must emit at i=0,10,20 (% 10 == 0) '
              'plus i=24 (last). Off-by-one or a missing last-iteration emit '
              'leaves the bar mid-band when the loop completes.',
        );

        // Every emission carries the right total.
        for (final state in recorder.memberEmissions) {
          expect(_parseTotal(state.syncStatus), 25);
        }
      },
    );

    test(
      'N=1 emits exactly once (i=0 is also the last iteration — no duplicate)',
      () async {
        final client = _ProgressFakeClient(members: _fakeMembers(1));
        final service = _makeService(db: db, client: client);
        final recorder = _StateRecorder()..attach(service);

        await service.importMembersOnly();

        // i=0 satisfies BOTH `i % 10 == 0` and `i == n - 1`, but each i runs
        // exactly once, so we get one emit, not two.
        expect(recorder.memberEmissions, hasLength(1));
        expect(_parseCurrent(recorder.memberEmissions.single.syncStatus), 1);
      },
    );

    test(
      'N=11 emits at i=0 and i=10 (last) — no double-fire when last is a '
      'multiple of 10',
      () async {
        // n=11 → i=0 (current=1, fires via i%10==0), i=10 (current=11, fires
        // via BOTH branches because i%10==0 AND i==n-1). Each i runs once.
        final client = _ProgressFakeClient(members: _fakeMembers(11));
        final service = _makeService(db: db, client: client);
        final recorder = _StateRecorder()..attach(service);

        await service.importMembersOnly();

        final currents = recorder.memberEmissions
            .map((s) => _parseCurrent(s.syncStatus))
            .toList();
        expect(currents, [1, 11]);
      },
    );

    test('N=0 emits nothing — the loop never runs', () async {
      final client = _ProgressFakeClient(members: const []);
      final service = _makeService(db: db, client: client);
      final recorder = _StateRecorder()..attach(service);

      await service.importMembersOnly();

      expect(recorder.memberEmissions, isEmpty);
    });
  });

  group('progress band math (50 of 1000)', () {
    // Per Phase 2 of the plan:
    //   _runFullImportWithClient  → band [0.05, 0.10]
    //   importMembersOnly         → band [0.50, 0.95]
    //   importFromFile            → band [0.05, 0.40]
    //
    // The math maps current=1 → band_start and current=total → band_end. We
    // verify band membership over the full set of emissions plus an
    // approximate value at current=50 of 1000.
    //
    // Note: cadence doesn't actually emit current=50 (it emits at 1, 11, 21,
    // ..., 991, 1000). The test "at member 50" verifies that *every*
    // emission, including those near member 50, lies inside the band.

    test('importMembersOnly progress stays in [0.50, 0.95]', () async {
      final client = _ProgressFakeClient(members: _fakeMembers(1000));
      final service = _makeService(db: db, client: client);
      final recorder = _StateRecorder()..attach(service);

      await service.importMembersOnly();

      expect(recorder.memberEmissions, isNotEmpty);
      for (final state in recorder.memberEmissions) {
        expect(
          state.syncProgress,
          inInclusiveRange(0.50, 0.95),
          reason:
              'importMembersOnly band is 0.50 → 0.95; got '
              '${state.syncProgress} for status "${state.syncStatus}"',
        );
      }
      // First emission at current=1 (i=0) should be exactly band_start.
      final first = recorder.memberEmissions.first;
      expect(_parseCurrent(first.syncStatus), 1);
      expect(first.syncProgress, closeTo(0.50, 1e-9));
      // Last emission at current=1000 (i=999) should be exactly band_end.
      final last = recorder.memberEmissions.last;
      expect(_parseCurrent(last.syncStatus), 1000);
      expect(last.syncProgress, closeTo(0.95, 1e-9));
    });

    test('importFromFile progress stays in [0.05, 0.40]', () async {
      final export = PkFileExport(
        system: const PKSystem(id: 'sys-1', name: 'Test System'),
        members: _fakeMembers(1000),
        groups: const [],
        switches: const [],
      );
      // importFromFile doesn't use a PK client — pass anything, it won't be
      // touched.
      final client = _ProgressFakeClient(members: const []);
      final service = _makeService(db: db, client: client);
      final recorder = _StateRecorder()..attach(service);

      await service.importFromFile(export);

      expect(recorder.memberEmissions, isNotEmpty);
      for (final state in recorder.memberEmissions) {
        expect(
          state.syncProgress,
          inInclusiveRange(0.05, 0.40),
          reason:
              'importFromFile band is 0.05 → 0.40; got '
              '${state.syncProgress} for status "${state.syncStatus}"',
        );
      }
      final first = recorder.memberEmissions.first;
      expect(_parseCurrent(first.syncStatus), 1);
      expect(first.syncProgress, closeTo(0.05, 1e-9));
      final last = recorder.memberEmissions.last;
      expect(_parseCurrent(last.syncStatus), 1000);
      expect(last.syncProgress, closeTo(0.40, 1e-9));
    });

    test(
      '_runFullImportWithClient (via performOneTimeFullImport) progress '
      'stays in [0.05, 0.10]',
      () async {
        final client = _ProgressFakeClient(members: _fakeMembers(1000));
        final service = _makeService(db: db, client: client);
        final recorder = _StateRecorder()..attach(service);

        await service.performOneTimeFullImport(token: 'test-token');

        expect(recorder.memberEmissions, isNotEmpty);
        for (final state in recorder.memberEmissions) {
          expect(
            state.syncProgress,
            inInclusiveRange(0.05, 0.10),
            reason:
                '_runFullImportWithClient member-import band is 0.05 → 0.10; '
                'got ${state.syncProgress} for status "${state.syncStatus}"',
          );
        }
        final first = recorder.memberEmissions.first;
        expect(_parseCurrent(first.syncStatus), 1);
        expect(first.syncProgress, closeTo(0.05, 1e-9));
        final last = recorder.memberEmissions.last;
        expect(_parseCurrent(last.syncStatus), 1000);
        expect(last.syncProgress, closeTo(0.10, 1e-9));
      },
    );
  });

  group('status text', () {
    test('importMembersOnly status includes the current member name', () async {
      final members = _fakeMembers(25);
      final client = _ProgressFakeClient(members: members);
      final service = _makeService(db: db, client: client);
      final recorder = _StateRecorder()..attach(service);

      await service.importMembersOnly();

      // The names visible to the user should match the members being worked
      // on at each cadence point (i=0, 10, 20, 24).
      expect(
        recorder.memberEmissions.map((s) => s.syncStatus).toList(),
        [
          'Importing member 1/25: Member 0',
          'Importing member 11/25: Member 10',
          'Importing member 21/25: Member 20',
          'Importing member 25/25: Member 24',
        ],
      );
    });

    test(
      'importFromFile status uses "from file:" template with member name',
      () async {
        final export = PkFileExport(
          system: const PKSystem(id: 'sys-1', name: 'Test System'),
          members: _fakeMembers(25),
          groups: const [],
          switches: const [],
        );
        final client = _ProgressFakeClient(members: const []);
        final service = _makeService(db: db, client: client);
        final recorder = _StateRecorder()..attach(service);

        await service.importFromFile(export);

        expect(
          recorder.memberEmissions.map((s) => s.syncStatus).toList(),
          [
            'Importing member 1/25 from file: Member 0',
            'Importing member 11/25 from file: Member 10',
            'Importing member 21/25 from file: Member 20',
            'Importing member 25/25 from file: Member 24',
          ],
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Parsing helpers — keep the regex tied to the actual template so a future
// edit to the status string fails noisily here rather than silently passing
// the band check with a parse error.
// ---------------------------------------------------------------------------

final _statusPattern = RegExp(
  r'^Importing member (\d+)/(\d+)(?: from file)?: ',
);

int _parseCurrent(String status) {
  final match = _statusPattern.firstMatch(status);
  if (match == null) {
    throw StateError('Could not parse current from status: "$status"');
  }
  return int.parse(match.group(1)!);
}

int _parseTotal(String status) {
  final match = _statusPattern.firstMatch(status);
  if (match == null) {
    throw StateError('Could not parse total from status: "$status"');
  }
  return int.parse(match.group(2)!);
}
