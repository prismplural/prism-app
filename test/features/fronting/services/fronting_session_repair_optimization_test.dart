import 'dart:async';
import 'dart:collection';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

/// The startup repair used to resolve every duplicate open's "next session" by
/// rescanning the member's whole history, and to find its own row with
/// `indexWhere`, which is O(opens x S) and quadratic for a member with many
/// opens. These tests pin what the rewrite must preserve (exact repair
/// semantics and summaries) and what it must guarantee (O(1) per-open lookups).
void main() {
  late AppDatabase db;
  late DriftFrontingSessionRepository repository;
  late FrontingMutationService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
    service = FrontingMutationService(
      repository: repository,
      mutationRunner: MutationRunner(transactionRunner: db.transaction),
      frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
        db.frontSessionCommentsDao,
        null,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> open(String id, String memberId, DateTime start) {
    return repository.createSession(
      FrontingSession(id: id, startTime: start, memberId: memberId),
    );
  }

  /// Seeds one open per member so every member is individually clean. The
  /// repair still walks all of them, which is what the yield cadence is about.
  Future<void> seedCleanMembers(int memberCount) async {
    final base = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < memberCount; i++) {
      await open('m$i-open', 'member-$i', base.add(Duration(hours: i)));
    }
  }

  int byStartThenId(FrontingSession a, FrontingSession b) {
    final byStart = a.startTime.compareTo(b.startTime);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  }

  int bySpanThenId(
    (String, DateTime, DateTime?) a,
    (String, DateTime, DateTime?) b,
  ) {
    final byStart = a.$2.compareTo(b.$2);
    if (byStart != 0) return byStart;
    final aEnd = a.$3 ?? DateTime.utc(9999);
    final bEnd = b.$3 ?? DateTime.utc(9999);
    final byEnd = aEnd.compareTo(bEnd);
    return byEnd != 0 ? byEnd : a.$1.compareTo(b.$1);
  }

  /// The previous implementation's per-open exhaustive rescan, kept verbatim as
  /// the oracle for the collapse decision. Valid where the collapsed opens stay
  /// touching (distinct start times), so no merge obscures the end times.
  Map<String, DateTime?> referenceCollapsedEndTimes(
    List<FrontingSession> rows,
  ) {
    final sorted = [...rows]..sort(byStartThenId);
    final opens = [
      for (final s in sorted)
        if (s.endTime == null) s,
    ];
    final ends = <String, DateTime?>{for (final s in sorted) s.id: s.endTime};
    if (opens.length <= 1) return ends;

    final keep = opens.last; // most-recently started
    for (final open in opens) {
      if (open.id == keep.id) continue;
      DateTime? nextStart;
      for (final other in sorted) {
        if (other.id == open.id) continue;
        if (other.startTime.isAfter(open.startTime) &&
            (nextStart == null || other.startTime.isBefore(nextStart))) {
          nextStart = other.startTime;
        }
      }
      final end = nextStart ?? keep.startTime;
      ends[open.id] = end.isAfter(open.startTime)
          ? end
          : open.startTime.add(const Duration(seconds: 1));
    }
    return ends;
  }

  /// A complete independent reference for the ORIGINAL repair: the verbatim
  /// per-open rescan, the `indexWhere` self lookup, and the same forward merge
  /// sweep. Unlike [referenceCollapsedEndTimes] it survives merging, so it can
  /// check the shapes where duplicate opens share a timestamp and every open
  /// takes the *no-successor* branch.
  ({List<(String, DateTime, DateTime?)> rows, int closed, int absorbed})
  referenceRepair(List<FrontingSession> input) {
    final sorted = [...input]..sort(byStartThenId);
    final opens = [
      for (final s in sorted)
        if (s.endTime == null) s,
    ];
    var closed = 0;
    if (opens.length > 1) {
      final keep = opens.last;
      for (final open in opens) {
        if (open.id == keep.id) continue;
        DateTime? nextStart;
        for (final other in sorted) {
          if (other.id == open.id) continue;
          if (other.startTime.isAfter(open.startTime) &&
              (nextStart == null || other.startTime.isBefore(nextStart))) {
            nextStart = other.startTime;
          }
        }
        final end = nextStart ?? keep.startTime;
        final safeEnd = end.isAfter(open.startTime)
            ? end
            : open.startTime.add(const Duration(seconds: 1));
        final slot = sorted.indexWhere((s) => s.id == open.id);
        if (slot >= 0) sorted[slot] = sorted[slot].copyWith(endTime: safeEnd);
        closed++;
      }
    }

    final farFuture = DateTime.utc(9999);
    var absorbed = 0;
    final repaired = <(String, DateTime, DateTime?)>[];
    for (var i = 0; i < sorted.length; i++) {
      final seed = sorted[i];
      final group = <FrontingSession>[seed];
      var groupStart = seed.startTime;
      DateTime? groupEnd = seed.endTime;
      while (i + 1 < sorted.length) {
        final next = sorted[i + 1];
        final aEnd = groupEnd ?? farFuture;
        final bEnd = next.endTime ?? farFuture;
        // Strict overlap only: touching boundaries stay distinct.
        if (!groupStart.isBefore(bEnd) || !next.startTime.isBefore(aEnd)) break;
        i++;
        group.add(next);
        if (next.startTime.isBefore(groupStart)) groupStart = next.startTime;
        final end = next.endTime;
        if (groupEnd != null) {
          if (end == null) {
            groupEnd = null;
          } else if (end.isAfter(groupEnd)) {
            groupEnd = end;
          }
        }
      }
      absorbed += group.length - 1;
      // Survivor id: PluralKit-linked first, then earliest start, then id.
      final linked = [
        for (final s in group)
          if (s.pluralkitUuid != null && s.pluralkitUuid!.isNotEmpty) s,
      ];
      final pool = linked.isNotEmpty ? linked : group;
      final survivor = pool.reduce((a, b) => byStartThenId(a, b) <= 0 ? a : b);
      repaired.add((survivor.id, groupStart, groupEnd));
    }
    repaired.sort(bySpanThenId);
    return (rows: repaired, closed: closed, absorbed: absorbed);
  }

  Future<List<(String, DateTime, DateTime?)>> repairedRowsFor(
    String memberId,
  ) async {
    final rows = await repository.getSessionsForMember(memberId);
    final spans = [for (final s in rows) (s.id, s.startTime, s.endTime)];
    spans.sort(bySpanThenId);
    return spans;
  }

  group('cooperative yields', () {
    const interval = FrontingMutationService.frontingRepairMemberYieldInterval;

    test('yields before the first member past the interval', () async {
      // One member more than a full chunk: the interval elapses, so the next
      // member must be preceded by a turn of the event loop.
      await seedCleanMembers(interval + 1);

      var yields = 0;
      final result = await service.repairMemberSessionInvariants(
        betweenMembers: () async => yields++,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.madeChanges, isFalse);
      expect(
        yields,
        1,
        reason: 'a full interval of members must hand the loop a turn',
      );
    });

    test('does not yield when the interval never elapses', () async {
      // Exactly one chunk of work: nothing remains to be preempted, so the
      // repair must not pay for a pointless timer.
      await seedCleanMembers(interval);

      var yields = 0;
      await service.repairMemberSessionInvariants(
        betweenMembers: () async => yields++,
      );

      expect(yields, 0);
    });

    test('yields again on each following interval of members', () async {
      await seedCleanMembers(interval * 2 + 1);

      var yields = 0;
      await service.repairMemberSessionInvariants(
        betweenMembers: () async => yields++,
      );

      expect(yields, 2);
    });

    test('awaits the injected yield before processing more members', () async {
      await seedCleanMembers(interval + 1);

      final reachedYield = Completer<void>();
      final releaseYield = Completer<void>();
      final repair = service.repairMemberSessionInvariants(
        betweenMembers: () {
          if (!reachedYield.isCompleted) reachedYield.complete();
          return releaseYield.future;
        },
      );
      var settled = false;
      unawaited(repair.then((_) => settled = true));

      // Deterministic rendezvous: the 10s deadline is only a failure guard for
      // a repair that never yields, not a speed assertion.
      await reachedYield.future.timeout(const Duration(seconds: 10));
      await pumpEventQueue();
      expect(
        settled,
        isFalse,
        reason: 'the repair must suspend inside the injected yield',
      );

      releaseYield.complete();
      final result = await repair;
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.madeChanges, isFalse);
    });

    test('default path repairs many members without a seam', () async {
      await seedCleanMembers(interval * 3);

      final result = await service.repairMemberSessionInvariants();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.membersAffected, 0);
    });
  });

  group('collapse decisions match the old scan', () {
    // Distinct start times keep the overlap merge a no-op (each collapsed open
    // ends exactly where the next begins), so the end times observed after the
    // repair are the collapse decision itself, comparable row by row.
    final shapes = <String, List<(String, DateTime)>>{
      'opens at increasing starts': [
        ('a', DateTime(2026, 5, 20, 8)),
        ('b', DateTime(2026, 5, 21, 8)),
        ('c', DateTime(2026, 5, 22, 8)),
        ('d', DateTime(2026, 5, 23, 8)),
        ('e', DateTime(2026, 5, 24, 8)),
      ],
      'ids descending against start order': [
        ('c', DateTime(2026, 5, 20, 8)),
        ('b', DateTime(2026, 5, 21, 8)),
        ('a', DateTime(2026, 5, 22, 8)),
      ],
      'later open carries the smaller id': [
        ('z', DateTime(2026, 6, 1, 9)),
        ('a', DateTime(2026, 6, 4, 10)),
      ],
      'uneven gaps between opens': [
        ('a', DateTime(2026, 6, 1, 6)),
        ('b', DateTime(2026, 6, 1, 6, 30)),
        ('c', DateTime(2026, 7, 15, 23, 59)),
        ('d', DateTime(2026, 7, 16)),
      ],
    };

    shapes.forEach((name, rows) {
      test('repair end times match the old scan: $name', () async {
        final seeds = [
          for (final (id, start) in rows)
            FrontingSession(id: id, startTime: start, memberId: 'mel'),
        ];
        for (final seed in seeds) {
          await repository.createSession(seed);
        }
        final expected = referenceCollapsedEndTimes(seeds);
        expect(
          expected.values.whereType<DateTime>(),
          isNotEmpty,
          reason: 'each shape must actually collapse at least one open',
        );

        final result = await service.repairMemberSessionInvariants();
        expect(result.dataOrNull!.openDuplicatesClosed, seeds.length - 1);
        expect(
          result.dataOrNull!.overlapsMerged,
          0,
          reason:
              'distinct starts stay touching, so the collapse decision is '
              'directly observable',
        );

        final repaired = await repository.getSessionsForMember('mel');
        expect(repaired, hasLength(seeds.length));
        for (final row in repaired) {
          expect(
            row.endTime,
            expected[row.id],
            reason: 'end time for ${row.id} must match the old scan',
          );
        }
        final stillOpen = repaired.where((s) => s.endTime == null).toList();
        expect(stillOpen, hasLength(1));
        expect(stillOpen.single.id, seeds.last.id);
      });
    });
  });

  group('many duplicate opens and timestamp ties', () {
    // Shapes big enough that the old O(opens x S) rescan and the old missing-key
    // fallback scan both had real work to do, checked against the complete
    // reference repair (collapse + merge) rather than just the collapse step.
    final shapes = <String, List<FrontingSession>>{
      'many opens at distinct starts': [
        for (var i = 0; i < 40; i++)
          FrontingSession(
            id: 'd${i.toString().padLeft(3, '0')}',
            startTime: DateTime(2026, 3, 1).add(Duration(hours: i * 5)),
            memberId: 'mel',
          ),
      ],
      'many opens sharing one timestamp': [
        for (var i = 0; i < 40; i++)
          FrontingSession(
            id: 't${i.toString().padLeft(3, '0')}',
            startTime: DateTime(2026, 4, 2, 12),
            memberId: 'mel',
          ),
      ],
      'ties interleaved with distinct starts': [
        for (var group = 0; group < 3; group++)
          for (var i = 0; i < 15; i++)
            FrontingSession(
              id: 'g$group-${i.toString().padLeft(3, '0')}',
              startTime: DateTime(
                2026,
                5,
                5,
                8,
              ).add(Duration(hours: group * 3)),
              memberId: 'mel',
            ),
      ],
      'tie block ending the history': [
        for (var i = 0; i < 10; i++)
          FrontingSession(
            id: 'lead-$i',
            startTime: DateTime(2026, 6, 1, 7).add(Duration(hours: i)),
            memberId: 'mel',
          ),
        for (var i = 0; i < 30; i++)
          FrontingSession(
            id: 'tail-${i.toString().padLeft(3, '0')}',
            startTime: DateTime(2026, 6, 20, 22),
            memberId: 'mel',
          ),
      ],
    };

    shapes.forEach((name, seeds) {
      test('matches the full old-algorithm oracle: $name', () async {
        for (final seed in seeds) {
          await repository.createSession(seed);
        }
        final expected = referenceRepair(seeds);
        expect(
          expected.closed,
          greaterThan(0),
          reason: 'each shape must actually collapse duplicate opens',
        );

        final result = await service.repairMemberSessionInvariants();

        expect(result.isSuccess, isTrue);
        expect(
          result.dataOrNull!.openDuplicatesClosed,
          expected.closed,
          reason: 'collapse count must match the old algorithm',
        );
        expect(
          result.dataOrNull!.overlapsMerged,
          expected.absorbed,
          reason: 'merge count must match the old algorithm',
        );

        expect(
          await repairedRowsFor('mel'),
          expected.rows,
          reason: 'surviving rows must match the old algorithm exactly',
        );
      });
    });

    test(
      'the last-timestamp tie block is idempotent on a second run',
      () async {
        final seeds = [
          for (var i = 0; i < 10; i++)
            FrontingSession(
              id: 'lead-$i',
              startTime: DateTime(2026, 6, 1, 7).add(Duration(hours: i)),
              memberId: 'mel',
            ),
          for (var i = 0; i < 30; i++)
            FrontingSession(
              id: 'tail-${i.toString().padLeft(3, '0')}',
              startTime: DateTime(2026, 6, 20, 22),
              memberId: 'mel',
            ),
        ];
        for (final seed in seeds) {
          await repository.createSession(seed);
        }
        final afterFirst = referenceRepair(seeds).rows;

        final first = await service.repairMemberSessionInvariants();
        expect(first.dataOrNull!.madeChanges, isTrue);

        final second = await service.repairMemberSessionInvariants();
        expect(second.dataOrNull!.madeChanges, isFalse);
        expect(second.dataOrNull!.openDuplicatesClosed, 0);
        expect(second.dataOrNull!.overlapsMerged, 0);
        expect(await repairedRowsFor('mel'), afterFirst);
      },
    );
  });

  group('per-open lookups are O(1)', () {
    // The index is the unit that has to stay scan-free: the collapse pass reads
    // its successor and its own slot from it once per open, so an O(S) scan
    // hiding in either lookup is exactly the quadratic shape this change
    // removes. The fake list reports every element read, which turns "is it
    // O(1)?" into an exact count instead of a timing measurement.
    FrontingSession openRow(String id, DateTime start) =>
        FrontingSession(id: id, startTime: start, memberId: 'mel');

    List<FrontingSession> manyRowsAt(
      DateTime start,
      int count,
      String prefix,
    ) => [
      for (var i = 0; i < count; i++)
        openRow('$prefix${i.toString().padLeft(3, '0')}', start),
    ];

    test('no-successor ties resolve without reading the row list', () {
      final earlier = DateTime(2026, 4, 2, 11);
      final last = DateTime(2026, 4, 2, 12);
      final seeds = [
        ...manyRowsAt(earlier, 200, 'early-'),
        ...manyRowsAt(last, 200, 'tie-'),
      ];
      // All 200 tied ids land on the final timestamp, so every one of their
      // successor lookups misses. A representation that left "no successor" as a
      // missing key would rescan the seeded rows on each such miss.
      final tiedIds = [
        for (final row in seeds)
          if (row.startTime == last) row.id,
      ];
      final earlierId = seeds.first.id;

      final rows = _ReadCountingList<FrontingSession>(seeds);
      final lookup = NextStartLookup.of(rows);
      final readsAfterBuild = rows.readCount;
      expect(
        readsAfterBuild,
        greaterThan(0),
        reason: 'building the index must read the rows',
      );

      for (final id in tiedIds) {
        expect(lookup.after(id), isNull);
      }
      expect(lookup.after(earlierId), last);
      expect(
        rows.readCount,
        readsAfterBuild,
        reason: 'after() must be a map read, never a scan',
      );
    });

    test('successor hits resolve without reading the row list', () {
      final first = DateTime(2026, 4, 2, 11);
      final second = DateTime(2026, 4, 2, 12);
      final third = DateTime(2026, 4, 2, 13);
      final rows = _ReadCountingList<FrontingSession>([
        ...manyRowsAt(first, 50, 'a-'),
        ...manyRowsAt(second, 50, 'b-'),
        ...manyRowsAt(third, 50, 'c-'),
      ]);

      final lookup = NextStartLookup.of(rows);
      final readsAfterBuild = rows.readCount;

      for (var i = 0; i < 150; i++) {
        expect(lookup.after('a-000'), second);
        expect(lookup.after('b-000'), third);
      }
      expect(lookup.after('c-000'), isNull);

      expect(
        rows.readCount,
        readsAfterBuild,
        reason: 'after() must be a map read, never a scan',
      );
    });

    test('row-slot lookup resolves without reading the row list', () {
      final seeds = manyRowsAt(DateTime(2026, 4, 2, 11), 100, 's-');
      final ids = [for (final row in seeds) row.id];
      final rows = _ReadCountingList<FrontingSession>(seeds);

      final lookup = NextStartLookup.of(rows);
      final readsAfterBuild = rows.readCount;

      for (final id in ids) {
        expect(lookup.indexOf(id), isNotNull);
      }
      expect(lookup.indexOf('absent'), isNull);
      expect(
        rows.readCount,
        readsAfterBuild,
        reason: 'indexOf must be a map read, never an indexWhere scan',
      );
    });

    test('shared timestamps map to the same successor', () {
      final first = DateTime(2026, 4, 2, 11);
      final second = DateTime(2026, 4, 2, 12);
      final lookup = NextStartLookup.of([
        openRow('a', first),
        openRow('b', first),
        openRow('c', second),
      ]);

      expect(lookup.after('a'), second);
      expect(lookup.after('b'), second);
      expect(lookup.after('c'), isNull);
      expect(lookup.indexOf('b'), isNotNull);
      expect(lookup.indexOf('c'), greaterThan(lookup.indexOf('b')!));
    });
  });
}

/// A list that counts how many elements a read of it touches, so a test can
/// prove a lookup never scans instead of timing it.
class _ReadCountingList<T> extends ListBase<T> {
  _ReadCountingList(this._inner);

  final List<T> _inner;
  int readCount = 0;

  @override
  int get length => _inner.length;

  @override
  set length(int value) => _inner.length = value;

  @override
  T operator [](int index) {
    readCount++;
    return _inner[index];
  }

  @override
  void operator []=(int index, T value) => _inner[index] = value;
}
