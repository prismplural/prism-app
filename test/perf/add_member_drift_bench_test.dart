// Drift-layer benchmark for "adding a member is slow on large systems".
//
// Isolated: a fresh FILE-backed AppDatabase (real transaction commits, unlike
// :memory:) seeded with a trimmed Reported-Large fixture (1000 members, 40
// custom fields, 300 dense groups; social tables zeroed for fast seeding). No
// FFI, no app, no personal data.
//
// Measures the costs the FFI bench can't see:
//   #1  custom-field commit N+1: 40 serial dao.upsertValue (each = getField +
//       own transaction + dedup SELECTs) vs one batchUpsertValues(40).
//   ord nextDisplayOrderIncludingDeleted (MAX scan) + the member-list ORDER BY
//       query, WITHOUT then WITH an index on display_order.
//
// Run: flutter test test/perf/add_member_drift_bench_test.dart

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';

// Trimmed Reported-Large: keep the member/group/custom-field density that
// stresses the add path; zero the social tables so seeding is seconds, not
// minutes.
const _benchPreset = StressPreset(
  label: 'Bench Reported-Large (trimmed)',
  members: 1000,
  sessions: 0,
  conversations: 0,
  messages: 0,
  habits: 0,
  completions: 0,
  notes: 0,
  polls: 0,
  groups: 300,
  customFields: 40,
  years: 1,
  estimatedSizeMb: 0,
  estimatedSeconds: 0,
  realisticProfiles: true,
  groupMembershipsPerMember: 12,
  customFieldValueCoverage: 0.9,
  memberAvatarEvery: 2,
  memberHeaderEvery: 5,
  groupAvatarEvery: 3,
  groupNestingDepth: 8,
);

({int medianUs, int p90Us, int maxUs}) _stats(List<int> us) {
  final sorted = [...us]..sort();
  int at(double q) => sorted[(q * (sorted.length - 1)).round()];
  return (medianUs: at(0.5), p90Us: at(0.9), maxUs: sorted.last);
}

String _ms(int us) => (us / 1000).toStringAsFixed(2);

void main() {
  test('add-member Drift-layer cost breakdown', () async {
    final dir = Directory.systemTemp.createTempSync('prism_bench');
    final dbFile = File('${dir.path}/bench.sqlite');
    final db = AppDatabase(NativeDatabase(dbFile));
    try {
      // ── Seed ────────────────────────────────────────────────────────
      final seedSw = Stopwatch()..start();
      await StressDataGenerator(db).generate(_benchPreset).drain<void>();
      seedSw.stop();

      final memberCount = await db
          .customSelect('SELECT COUNT(*) c FROM members')
          .getSingle()
          .then((r) => r.read<int>('c'));
      final entryCount = await db
          .customSelect('SELECT COUNT(*) c FROM member_group_entries')
          .getSingle()
          .then((r) => r.read<int>('c'));
      final cfvCount = await db
          .customSelect('SELECT COUNT(*) c FROM custom_field_values')
          .getSingle()
          .then((r) => r.read<int>('c'));

      // ── #1: per-field custom-field commit, serial vs batch ───────────
      // A brand-new member gets a value for each of the 40 stress fields —
      // exactly what saving a member with all custom fields filled does.
      // Distinct member per run so the (custom_field_id, member_id) unique
      // index doesn't collide between the serial and batch passes.
      List<CustomFieldValuesCompanion> companions(String tag) => [
            for (var f = 0; f < _benchPreset.customFields; f++)
              CustomFieldValuesCompanion.insert(
                id: 'bench-cfv-$tag-$f',
                customFieldId: 'stress-field-$f',
                memberId: 'bench-new-member-$tag',
                value: 'Benchmark value for field $f',
              ),
          ];

      final serialSw = Stopwatch()..start();
      final perFieldTimes = <int>[];
      for (final c in companions('serial')) {
        final sw = Stopwatch()..start();
        await db.customFieldsDao.upsertValue(c);
        sw.stop();
        perFieldTimes.add(sw.elapsedMicroseconds);
      }
      serialSw.stop();
      final perField = _stats(perFieldTimes);

      final batchSw = Stopwatch()..start();
      await db.customFieldsDao.batchUpsertValues(companions('batch'));
      batchSw.stop();

      // Safe batching: the SAME per-field upsertValue calls (which dedup on the
      // (field,member) unique key, unlike batchUpsertValues' id-keyed upsert),
      // wrapped in one outer transaction so 40 fsyncs collapse to 1 savepoint.
      final txnSw = Stopwatch()..start();
      await db.transaction(() async {
        for (final c in companions('txn')) {
          await db.customFieldsDao.upsertValue(c);
        }
      });
      txnSw.stop();

      // ── ordering: MAX(display_order) scan, no index then index ───────
      Future<({int medianUs, int p90Us, int maxUs})> timeNextOrder() async {
        final t = <int>[];
        for (var i = 0; i < 30; i++) {
          final sw = Stopwatch()..start();
          await db.membersDao.nextDisplayOrderIncludingDeleted();
          sw.stop();
          t.add(sw.elapsedMicroseconds);
        }
        return _stats(t);
      }

      Future<({int medianUs, int p90Us, int maxUs})> timeListOrderBy() async {
        final t = <int>[];
        for (var i = 0; i < 30; i++) {
          final sw = Stopwatch()..start();
          await db
              .customSelect(
                'SELECT id FROM members WHERE is_deleted = 0 '
                'ORDER BY display_order ASC',
                readsFrom: {db.members},
              )
              .get();
          sw.stop();
          t.add(sw.elapsedMicroseconds);
        }
        return _stats(t);
      }

      final nextOrderNoIdx = await timeNextOrder();
      final listNoIdx = await timeListOrderBy();
      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_members_display_order '
        'ON members (display_order)',
      );
      final nextOrderIdx = await timeNextOrder();
      final listIdx = await timeListOrderBy();

      // ── #3 (DB portion): the full member-list query that re-fires on
      //     every insert, plus the group-entries read the grouped list folds.
      // Fix B before/after: memberNameMapProvider used to watch the HEAVY
      // getAllMembers (full rows incl. avatar blobs); now it watches the light
      // list (watchActiveMembersForList, blobs nulled). Same row set.
      final heavyTimes = <int>[];
      final lightTimes = <int>[];
      for (var i = 0; i < 20; i++) {
        var sw = Stopwatch()..start();
        await db.membersDao.getAllMembers();
        sw.stop();
        heavyTimes.add(sw.elapsedMicroseconds);
        sw = Stopwatch()..start();
        await db.membersDao.watchActiveMembersForList().first;
        sw.stop();
        lightTimes.add(sw.elapsedMicroseconds);
      }
      final heavyStats = _stats(heavyTimes);
      final lightStats = _stats(lightTimes);

      final memberListTimes = <int>[];
      final entriesTimes = <int>[];
      for (var i = 0; i < 20; i++) {
        var sw = Stopwatch()..start();
        await db.membersDao.getAllMembers();
        sw.stop();
        memberListTimes.add(sw.elapsedMicroseconds);
        sw = Stopwatch()..start();
        await db
            .customSelect('SELECT id, group_id, member_id FROM member_group_entries')
            .get();
        sw.stop();
        entriesTimes.add(sw.elapsedMicroseconds);
      }
      final memberListStats = _stats(memberListTimes);
      final entriesStats = _stats(entriesTimes);

      // ── Report ───────────────────────────────────────────────────────
      final b = StringBuffer()
        ..writeln('\n============== ADD-MEMBER DRIFT BENCH ==============')
        ..writeln(
          'seed: ${seedSw.elapsedMilliseconds}ms  '
          'members=$memberCount entries=$entryCount cfValues=$cfvCount\n',
        )
        ..writeln('#1  CUSTOM-FIELD COMMIT (40 fields on a new member):')
        ..writeln(
          '    serial upsertValue : total=${serialSw.elapsedMilliseconds}ms  '
          'per-op median=${_ms(perField.medianUs)}ms p90=${_ms(perField.p90Us)}ms',
        )
        ..writeln(
          '    batchUpsertValues  : total=${batchSw.elapsedMilliseconds}ms  '
          '(one txn, id-keyed — UNSAFE for edits w/ differing value-row id)',
        )
        ..writeln(
          '    serial in 1 txn    : total=${txnSw.elapsedMilliseconds}ms  '
          '(SAFE: same dedup upsert, fsyncs collapsed)',
        )
        ..writeln(
          '    => 1-txn speedup x'
          '${(serialSw.elapsedMilliseconds / (txnSw.elapsedMilliseconds == 0 ? 1 : txnSw.elapsedMilliseconds)).toStringAsFixed(1)}',
        )
        ..writeln('')
        ..writeln('ORD nextDisplayOrder MAX scan (per call):')
        ..writeln(
          '    no index : median=${_ms(nextOrderNoIdx.medianUs)}ms p90=${_ms(nextOrderNoIdx.p90Us)}ms',
        )
        ..writeln(
          '    w/ index : median=${_ms(nextOrderIdx.medianUs)}ms p90=${_ms(nextOrderIdx.p90Us)}ms',
        )
        ..writeln('    member-list ORDER BY display_order (per emission):')
        ..writeln(
          '    no index : median=${_ms(listNoIdx.medianUs)}ms p90=${_ms(listNoIdx.p90Us)}ms',
        )
        ..writeln(
          '    w/ index : median=${_ms(listIdx.medianUs)}ms p90=${_ms(listIdx.p90Us)}ms',
        )
        ..writeln('')
        ..writeln('FIX B (memberNameMapProvider re-fire, per insert):')
        ..writeln(
          '    heavy getAllMembers (blobs): median=${_ms(heavyStats.medianUs)}ms p90=${_ms(heavyStats.p90Us)}ms',
        )
        ..writeln(
          '    light list (blobs nulled)  : median=${_ms(lightStats.medianUs)}ms p90=${_ms(lightStats.p90Us)}ms',
        )
        ..writeln(
          '    => saved per insert ~${_ms(heavyStats.medianUs - lightStats.medianUs)}ms '
          '(x${(heavyStats.medianUs / (lightStats.medianUs == 0 ? 1 : lightStats.medianUs)).toStringAsFixed(1)} cheaper)',
        )
        ..writeln('')
        ..writeln('#3  RE-FIRED-ON-INSERT QUERIES (DB portion):')
        ..writeln(
          '    getAllMembers (1000 rows, full incl. avatar blobs): median=${_ms(memberListStats.medianUs)}ms p90=${_ms(memberListStats.p90Us)}ms',
        )
        ..writeln(
          '    all group entries read         : median=${_ms(entriesStats.medianUs)}ms p90=${_ms(entriesStats.p90Us)}ms',
        )
        ..writeln('====================================================\n');
      // ignore: avoid_print
      print(b.toString());
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
