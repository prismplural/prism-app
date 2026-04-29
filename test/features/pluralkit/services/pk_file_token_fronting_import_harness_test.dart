import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

import '../../../helpers/pluralkit_fake_client.dart';

const _fixturePath = 'test/fixtures/pk_combined_import_sanitized_export.json';

const _alphaUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _betaUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _deletedUuid = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

const _swAlpha = '00000000-0000-4000-8000-000000000001';
const _swAlphaBeta = '00000000-0000-4000-8000-000000000002';
const _swAlphaAgain = '00000000-0000-4000-8000-000000000003';
const _swStaleOutside = '00000000-0000-4000-8000-000000000004';
const _swDeletedMember = '00000000-0000-4000-8000-000000000005';
const _swSwitchOut = '00000000-0000-4000-8000-000000000006';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PK file + token fronting import harness', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'exact file/API matches import canonically and retain file provenance',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final export = await _readSanitizedExport();
        final client = FakePluralKitClient(
          system: export.system,
          members: export.members,
          groups: export.groups,
          switchesNewestFirst: [
            _switch(
              id: _swStaleOutside,
              timestamp: DateTime.utc(2026, 4, 2, 9),
              members: ['bbbbb'],
            ),
            _switch(
              id: _swAlphaAgain,
              timestamp: DateTime.utc(2026, 4, 1, 14),
              members: ['aaaaa'],
            ),
            _switch(
              id: _swAlphaBeta,
              timestamp: DateTime.utc(2026, 4, 1, 12),
              members: ['aaaaa', 'bbbbb'],
            ),
            _switch(
              id: _swAlpha,
              timestamp: DateTime.utc(2026, 4, 1, 10, 0, 0, 123, 456),
              members: ['aaaaa'],
            ),
          ],
        );

        final result = await _runHarness(
          db: db,
          export: export,
          client: client,
        );

        expect(result.importResult.membersImported, 2);
        expect(result.importResult.groupsImported, 1);
        expect(result.importResult.exactImportedCount, 3);
        expect(result.importResult.apiOnlyOutsideRangeCount, 1);
        expect(result.importResult.canonicalizationSafe, isTrue);
        expect(result.importResult.frontingImported, isTrue);
        expect(
          result.importResult.apiSwitchesFetched,
          result.importResult.exactImportedCount +
              result.importResult.apiOnlyOutsideRangeCount,
        );

        final members = await db.membersDao.getAllMembers();
        expect(members.map((m) => m.pluralkitId).toSet(), {'aaaaa', 'bbbbb'});

        final groups = await db.memberGroupsDao.getAllActiveGroups();
        expect(
          groups.single.pluralkitUuid,
          '99999999-9999-4999-8999-999999999999',
        );

        final sessions = await _sessions(db);
        expect(sessions, hasLength(3));

        final alpha = sessions.singleWhere(
          (s) => s.id == derivePkSessionId(_swAlpha, _alphaUuid),
        );
        expect(alpha.memberId, isNotNull);
        expect(alpha.pluralkitUuid, _swAlpha);
        expect(alpha.pkImportSource, pkImportSourceFileApi);
        expect(
          alpha.pkFileSwitchId,
          'pkfile:v1:2026-04-01T10:00:00.123456Z|aaaaa',
        );
        expect(
          _sameInstant(
            alpha.startTime,
            DateTime.utc(2026, 4, 1, 10, 0, 0, 123, 456),
          ),
          isTrue,
        );
        expect(
          _sameInstant(alpha.endTime!, DateTime.utc(2026, 4, 2, 9)),
          isTrue,
        );

        final beta = sessions.singleWhere(
          (s) => s.id == derivePkSessionId(_swAlphaBeta, _betaUuid),
        );
        expect(beta.pluralkitUuid, _swAlphaBeta);
        expect(beta.pkImportSource, pkImportSourceFileApi);
        expect(
          beta.pkFileSwitchId,
          'pkfile:v1:2026-04-01T12:00:00.000Z|aaaaa,bbbbb',
        );
        expect(
          _sameInstant(beta.endTime!, DateTime.utc(2026, 4, 1, 14)),
          isTrue,
        );

        final staleOutside = sessions.singleWhere(
          (s) => s.id == derivePkSessionId(_swStaleOutside, _betaUuid),
        );
        expect(staleOutside.pluralkitUuid, _swStaleOutside);
        expect(staleOutside.pkImportSource, isNull);
        expect(staleOutside.pkFileSwitchId, isNull);
      },
    );

    test('ambiguous duplicate switch blocks canonical persistence', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final export = _exportWithSwitches([
        _fileSwitch(DateTime.utc(2026, 4, 1, 10), ['aaaaa']),
      ]);
      final client = _clientFor(
        export,
        switches: [
          _switch(
            id: _swAlpha,
            timestamp: DateTime.utc(2026, 4, 1, 10),
            members: ['aaaaa'],
          ),
          _switch(
            id: _swAlphaBeta,
            timestamp: DateTime.utc(2026, 4, 1, 10),
            members: ['aaaaa'],
          ),
        ],
      );

      final result = await _runHarness(db: db, export: export, client: client);

      expect(result.importResult.ambiguousCount, 1);
      expect(result.importResult.frontingImported, isFalse);
      expect(result.importResult.canonicalizationSafe, isFalse);
      expect(await _sessions(db), isEmpty);
    });

    test('file-only switch blocks canonical persistence', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final export = _exportWithSwitches([
        _fileSwitch(DateTime.utc(2026, 4, 1, 10), ['aaaaa']),
        _fileSwitch(DateTime.utc(2026, 4, 1, 12), ['bbbbb']),
      ]);
      final client = _clientFor(
        export,
        switches: [
          _switch(
            id: _swAlpha,
            timestamp: DateTime.utc(2026, 4, 1, 10),
            members: ['aaaaa'],
          ),
        ],
      );

      final result = await _runHarness(db: db, export: export, client: client);

      expect(result.importResult.fileOnlyCount, 1);
      expect(result.importResult.frontingImported, isFalse);
      expect(result.importResult.canonicalizationSafe, isFalse);
      expect(await _sessions(db), isEmpty);
    });

    test(
      'API-only switch inside file range blocks canonical persistence',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final export = _exportWithSwitches([
          _fileSwitch(DateTime.utc(2026, 4, 1, 10), ['aaaaa']),
          _fileSwitch(DateTime.utc(2026, 4, 1, 14), ['aaaaa']),
        ]);
        final client = _clientFor(
          export,
          switches: [
            _switch(
              id: _swAlpha,
              timestamp: DateTime.utc(2026, 4, 1, 10),
              members: ['aaaaa'],
            ),
            _switch(
              id: _swAlphaBeta,
              timestamp: DateTime.utc(2026, 4, 1, 12),
              members: ['aaaaa', 'bbbbb'],
            ),
            _switch(
              id: _swAlphaAgain,
              timestamp: DateTime.utc(2026, 4, 1, 14),
              members: ['aaaaa'],
            ),
          ],
        );

        final result = await _runHarness(
          db: db,
          export: export,
          client: client,
        );

        expect(result.importResult.apiOnlyInRangeCount, 1);
        expect(result.importResult.frontingImported, isFalse);
        expect(result.importResult.canonicalizationSafe, isFalse);
        expect(await _sessions(db), isEmpty);
      },
    );

    test(
      'missing/deleted member refs are counted but known members import',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final export = _exportWithSwitches([
          _fileSwitch(DateTime.utc(2026, 4, 1, 10), ['aaaaa', 'zzzzz']),
          _fileSwitch(DateTime.utc(2026, 4, 1, 12), []),
        ]);
        final client = _clientFor(
          export,
          switches: [
            _switch(
              id: _swSwitchOut,
              timestamp: DateTime.utc(2026, 4, 1, 12),
              members: [],
            ),
            _switch(
              id: _swDeletedMember,
              timestamp: DateTime.utc(2026, 4, 1, 10),
              members: ['aaaaa', 'zzzzz'],
            ),
          ],
        );

        final result = await _runHarness(
          db: db,
          export: export,
          client: client,
        );

        expect(result.importResult.exactImportedCount, 2);
        expect(result.importResult.frontingImported, isTrue);
        expect(result.importResult.unmappedMemberReferences, 1);

        final sessions = await _sessions(db);
        expect(sessions, hasLength(1));
        expect(
          sessions.single.id,
          derivePkSessionId(_swDeletedMember, _alphaUuid),
        );
        expect(
          sessions.single.id,
          isNot(derivePkSessionId(_swDeletedMember, _deletedUuid)),
        );
        expect(sessions.single.pkImportSource, pkImportSourceFileApi);
        expect(
          sessions.single.pkFileSwitchId,
          'pkfile:v1:2026-04-01T10:00:00.000Z|aaaaa,zzzzz',
        );
        expect(
          _sameInstant(sessions.single.endTime!, DateTime.utc(2026, 4, 1, 12)),
          isTrue,
        );
      },
    );
  });
}

Future<PkFileExport> _readSanitizedExport() async {
  final raw = await File(_fixturePath).readAsString();
  return parsePkExportFile(raw);
}

PkFileExport _exportWithSwitches(List<PkFileSwitch> switches) {
  return PkFileExport(
    system: const PKSystem(id: 'pkfix', name: 'Sanitized Fixture System'),
    members: const [
      PKMember(id: 'aaaaa', uuid: _alphaUuid, name: 'Alpha'),
      PKMember(id: 'bbbbb', uuid: _betaUuid, name: 'Beta'),
    ],
    groups: const [],
    switches: switches,
  );
}

FakePluralKitClient _clientFor(
  PkFileExport export, {
  required List<PKSwitch> switches,
}) {
  return FakePluralKitClient(
    system: export.system,
    members: export.members,
    groups: export.groups,
    switchesNewestFirst: switches,
  );
}

PkFileSwitch _fileSwitch(DateTime timestamp, List<String> members) {
  return PkFileSwitch(timestamp: timestamp, memberIds: members);
}

PKSwitch _switch({
  required String id,
  required DateTime timestamp,
  required List<String> members,
}) {
  return PKSwitch(id: id, timestamp: timestamp, members: members);
}

Future<_HarnessResult> _runHarness({
  required AppDatabase db,
  required PkFileExport export,
  required FakePluralKitClient client,
}) async {
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
  final service = PluralKitSyncService(
    memberRepository: memberRepo,
    frontingSessionRepository: sessionRepo,
    syncDao: db.pluralKitSyncDao,
    tokenOverride: 'test-token',
    clientFactory: (_) => client,
    groupsImporter: PkGroupsImporter(db: db, memberRepository: memberRepo),
  );

  final importResult = await service.importFromFileWithToken(
    export,
    token: 'test-token',
  );

  return _HarnessResult(importResult: importResult);
}

Future<List<FrontingSession>> _sessions(AppDatabase db) {
  return DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    null,
  ).getAllSessions();
}

bool _sameInstant(DateTime actual, DateTime expected) {
  return actual.millisecondsSinceEpoch ~/ 1000 ==
      expected.millisecondsSinceEpoch ~/ 1000;
}

class _HarnessResult {
  final PkFileTokenFrontingImportResult importResult;

  const _HarnessResult({required this.importResult});
}
