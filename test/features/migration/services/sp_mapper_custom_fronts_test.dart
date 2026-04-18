import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

SpExportData _data({
  List<SpMember> members = const [],
  List<SpCustomFront> customFronts = const [],
  List<SpFrontHistory> frontHistory = const [],
  List<SpComment> comments = const [],
  List<SpAutomatedTimer> automatedTimers = const [],
}) {
  return SpExportData(
    members: members,
    customFronts: customFronts,
    frontHistory: frontHistory,
    groups: const [],
    channels: const [],
    messages: const [],
    polls: const [],
    comments: comments,
    automatedTimers: automatedTimers,
  );
}

const _alice = SpMember(id: 'sp-a', name: 'Alice');
const _bob = SpMember(id: 'sp-b', name: 'Bob');

void main() {
  group('Mapper — disposition in isolation (test 2)', () {
    test('importAsMember: CF emitted as a tagged member, session normal', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Blurry')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.importAsMember},
      );
      final result = mapper.mapAll(data);
      expect(result.members.any((m) => m.name == 'Blurry'), isTrue);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.sessionType, domain.SessionType.normal);
      expect(result.sessions.first.memberId, isNotNull);
    });

    test('mergeAsNote: no member row; CF name appears in session note', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Blurry')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.mergeAsNote},
      );
      final result = mapper.mapAll(data);
      expect(result.members.any((m) => m.name == 'Blurry'), isFalse);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.memberId, isNull);
      expect(result.sessions.first.notes, contains('Blurry'));
    });

    test('convertToSleep: sleep-type session emitted, no member row', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            endTime: DateTime(2024, 1, 1, 8),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.members.any((m) => m.name == 'Asleep'), isFalse);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.sessionType, domain.SessionType.sleep);
      expect(result.sessions.first.memberId, isNull);
      expect(result.sessions.first.coFronterIds, isEmpty);
      expect(result.sessions.first.quality, domain.SleepQuality.unknown);
    });

    test('skip: lone-primary entry dropped with warning, no member', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Away')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.skip},
      );
      final result = mapper.mapAll(data);
      expect(result.members.any((m) => m.name == 'Away'), isFalse);
      expect(result.sessions, isEmpty);
      expect(
        result.warnings.any((w) => w.contains('dropped')),
        isTrue,
      );
    });
  });

  group('Mapper — mixed CF dispositions (test 3)', () {
    test('primary cfNote + co-fronter realMember → promotes, note tags', () {
      final data = _data(
        members: const [_alice],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Blurry')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            coFronters: const ['sp-a'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.mergeAsNote},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      // Alice promoted to primary.
      final alicePrismId =
          result.members.firstWhere((m) => m.name == 'Alice').id;
      expect(s.memberId, alicePrismId);
      // Alice is no longer in co-fronters.
      expect(s.coFronterIds, isEmpty);
      expect(s.notes, contains('Blurry'));
      expect(s.sessionType, domain.SessionType.normal);
    });

    test(
        'primary cfSleep + co-fronter realMember (E2) → sleep session, '
        'no co-fronters, warning', () {
      final data = _data(
        members: const [_alice],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            endTime: DateTime(2024, 1, 1, 5),
            coFronters: const ['sp-a'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      expect(s.sessionType, domain.SessionType.sleep);
      expect(s.memberId, isNull);
      expect(s.coFronterIds, isEmpty);
      expect(
        result.warnings.any((w) => w.contains('co-fronters that were discarded')),
        isTrue,
      );
    });

    test(
        'primary realMember + co-fronter cfSleep (E4) → member session, '
        'note has "[<name> during]", no sleep session', () {
      final data = _data(
        members: const [_alice],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            endTime: DateTime(2024, 1, 1, 5),
            coFronters: const ['cf1'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      expect(s.sessionType, domain.SessionType.normal);
      final alicePrismId =
          result.members.firstWhere((m) => m.name == 'Alice').id;
      expect(s.memberId, alicePrismId);
      expect(s.notes, contains('Asleep during'));
      expect(
        result.warnings
            .any((w) => w.contains('sleep custom front as co-fronter')),
        isTrue,
      );
    });

    test('primary cfSkip + co-fronters realMember → first promoted, rest kept',
        () {
      final data = _data(
        members: const [_alice, _bob],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Away')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            coFronters: const ['sp-b', 'sp-a'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.skip},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      final aliceId = result.members.firstWhere((m) => m.name == 'Alice').id;
      final bobId = result.members.firstWhere((m) => m.name == 'Bob').id;
      // Stable SP-id sort within realMember tier: sp-a < sp-b → Alice wins.
      expect(s.memberId, aliceId);
      expect(s.coFronterIds, [bobId]);
    });

    test('primary cfSkip + no co-fronters → dropped, warning counted', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Away')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.skip},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, isEmpty);
      expect(
        result.warnings.any((w) =>
            w.contains('1 front-history entries dropped') ||
            w.contains('skipped custom front')),
        isTrue,
      );
    });
  });

  group('Mapper — sleep behavior (tests 4, 11, 13)', () {
    test('overlapping sleep sessions both emitted (E5)', () {
      final data = _data(
        customFronts: const [
          SpCustomFront(id: 'cf1', name: 'Asleep'),
          SpCustomFront(id: 'cf2', name: 'Napping'),
        ],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1, 0),
            endTime: DateTime(2024, 1, 1, 8),
            isCustomFront: true,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'cf2',
            startTime: DateTime(2024, 1, 1, 4),
            endTime: DateTime(2024, 1, 1, 10),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {
          'cf1': CfDisposition.convertToSleep,
          'cf2': CfDisposition.convertToSleep,
        },
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(2));
      expect(
        result.sessions.every((s) => s.sessionType == domain.SessionType.sleep),
        isTrue,
      );
    });

    test('open-ended sleep clamped to 24h with warning (test 11)', () {
      final start = DateTime(2024, 1, 1);
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: start,
            endTime: null,
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(
        result.sessions.first.endTime,
        start.add(const Duration(hours: 24)),
      );
      expect(
        result.warnings.any((w) => w.contains('clamped to 24h')),
        isTrue,
      );
    });

    test('same-start defensive dedup within 60s collapses to one (test 13)',
        () {
      final start = DateTime(2024, 1, 1);
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            isCustomFront: true,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'cf1',
            startTime: start.add(const Duration(seconds: 30)),
            endTime: start.add(const Duration(hours: 2)),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(
        result.warnings.any((w) => w.contains('duplicate-start')),
        isTrue,
      );
    });
  });

  group('Mapper — note combining (test 5)', () {
    test('customStatus + comment + CF note tags combine cleanly', () {
      final data = _data(
        members: const [_alice],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Blurry')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            coFronters: const ['cf1'],
            comment: 'a comment',
            customStatus: 'status-x',
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.mergeAsNote},
      );
      final result = mapper.mapAll(data);
      final notes = result.sessions.first.notes!;
      expect(notes, contains('[Blurry]'));
      expect(notes, contains('[status-x]'));
      expect(notes, contains('a comment'));
      // Ensure no doubled brackets like [[ or ]].
      expect(notes.contains('[['), isFalse);
      expect(notes.contains(']]'), isFalse);
    });
  });

  group('Mapper — stale mapping scrub (test 6)', () {
    test('CF with prior-import member mapping is scrubbed when disposition '
        'is no longer importAsMember', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Blurry')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        existingMappings: const {
          'member': {'cf1': 'stale-prism-uuid'},
        },
        customFrontDispositions: const {'cf1': CfDisposition.mergeAsNote},
      );
      final result = mapper.mapAll(data);

      // No member row for the CF.
      expect(result.members.any((m) => m.name == 'Blurry'), isFalse);
      // The session should NOT resolve to the stale UUID as primary.
      expect(
        result.sessions.any((s) => s.memberId == 'stale-prism-uuid'),
        isFalse,
      );
      // Mapping scrubbed.
      expect(mapper.memberIdMap.containsKey('cf1'), isFalse);
      // Importer will be asked to delete the stale mapping.
      expect(mapper.pendingStaleMappingDeletes, contains('cf1'));
      // Warning surfaced.
      expect(
        result.warnings.any(
            (w) => w.contains('previously-imported custom fronts')),
        isTrue,
      );
    });

    test('importAsMember re-run reuses existing mapping (no scrub)', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Blurry')],
      );
      final mapper = SpMapper(
        existingMappings: const {
          'member': {'cf1': 'keep-this-uuid'},
        },
        customFrontDispositions: const {'cf1': CfDisposition.importAsMember},
      );
      mapper.mapAll(data);
      expect(mapper.memberIdMap['cf1'], 'keep-this-uuid');
      expect(mapper.pendingStaleMappingDeletes, isEmpty);
    });
  });

  group('Mapper — synthetic CF fallback (test 7)', () {
    test('isCustomFront id missing from customFronts list is handled as note',
        () {
      final data = _data(
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-ghost',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      // No member for the synthesized CF.
      expect(result.members, isEmpty);
      // Session emitted as sessionless note (promotion path — cfNote primary,
      // no cofronters → hasContent via note text).
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      expect(s.memberId, isNull);
      expect(s.notes, contains('deleted custom front'));
      expect(
        result.warnings.any((w) =>
            w.contains('deleted in SP') ||
            w.contains('handled as notes')),
        isTrue,
      );
    });
  });

  group('Mapper — timer dispositions (test 8)', () {
    test('each CF-target disposition produces expected reminder behavior', () {
      final data = _data(
        members: const [_alice],
        customFronts: const [
          SpCustomFront(id: 'cf-mem', name: 'MemCF'),
          SpCustomFront(id: 'cf-note', name: 'NoteCF'),
          SpCustomFront(id: 'cf-sleep', name: 'SleepCF'),
          SpCustomFront(id: 'cf-skip', name: 'SkipCF'),
        ],
        automatedTimers: const [
          SpAutomatedTimer(
            id: 't-mem',
            name: 'T1',
            type: 1,
            targetId: 'cf-mem',
          ),
          SpAutomatedTimer(
            id: 't-note',
            name: 'T2',
            type: 1,
            targetId: 'cf-note',
          ),
          SpAutomatedTimer(
            id: 't-sleep',
            name: 'T3',
            type: 1,
            targetId: 'cf-sleep',
          ),
          SpAutomatedTimer(
            id: 't-skip',
            name: 'T4',
            type: 1,
            targetId: 'cf-skip',
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {
          'cf-mem': CfDisposition.importAsMember,
          'cf-note': CfDisposition.mergeAsNote,
          'cf-sleep': CfDisposition.convertToSleep,
          'cf-skip': CfDisposition.skip,
        },
      );
      final result = mapper.mapAll(data);

      // Only 2 reminders survive: importAsMember (with target), mergeAsNote
      // (target dropped → "any front change"). Sleep/skip timers are removed.
      final fcReminders = result.reminders
          .where((r) => r.trigger == domain.ReminderTrigger.onFrontChange)
          .toList();
      expect(fcReminders, hasLength(2));

      // importAsMember timer keeps its target.
      final memCfId =
          result.members.firstWhere((m) => m.name == 'MemCF').id;
      expect(
        fcReminders.any((r) => r.targetMemberId == memCfId),
        isTrue,
      );
      // mergeAsNote timer has no target.
      expect(
        fcReminders.any((r) => r.targetMemberId == null),
        isTrue,
      );

      // Warning surfaces for CF timer changes.
      expect(
        result.warnings.any((w) =>
            w.contains('targeted custom fronts') ||
            w.contains('target dropped or timer removed')),
        isTrue,
      );
    });
  });

  group('Mapper — comment handling (tests 9, 10)', () {
    test('dropped-session comment is skipped with warning', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Away')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'f1',
            collection: 'frontHistory',
            text: 'orphan',
            time: DateTime(2024, 1, 1, 12),
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.skip},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, isEmpty);
      expect(result.frontComments, isEmpty);
      // Dropped-comment warning surfaced (either the aggregated one or the
      // per-comment warning is fine).
      expect(
        result.warnings.any((w) =>
            w.contains('comments dropped') || w.contains('c1')),
        isTrue,
      );
    });

    test('converted-sleep session keeps its comments', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1),
            endTime: DateTime(2024, 1, 1, 8),
            isCustomFront: true,
          ),
        ],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'f1',
            collection: 'frontHistory',
            text: 'had a dream',
            time: DateTime(2024, 1, 1, 4),
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.frontComments, hasLength(1));
      expect(
        result.frontComments.first.sessionId,
        result.sessions.first.id,
      );
    });
  });

  group('Mapper — active-session collision (test 12, mapper-level)', () {
    test('open-ended cfSleep emits sleep session without side-effects '
        '(no startSleep call, no active-session mutation at mapper layer)', () {
      // The mapper cannot see the live DB; the plan's active-session
      // collision concern is that the importer does not take a startSleep
      // path. At the mapper level we verify the emitted session is purely a
      // historical one: it has an endTime (clamped to 24h) and is a plain
      // SessionType.sleep record.
      final start = DateTime(2024, 1, 1);
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: start,
            endTime: null,
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      // Clamped, not open-ended.
      expect(s.endTime, isNotNull);
      expect(s.isActive, isFalse);
      expect(s.sessionType, domain.SessionType.sleep);
    });
  });

  group('Mapper — promotion determinism (test 14)', () {
    test('promotion picks realMember over cfMember, stable by SP id', () {
      // Primary is cfNote; co-fronters mix a realMember (sp-b) and a
      // cfMember (cf-z). realMember wins regardless of input order. Among
      // real members, lowest SP id wins.
      final data = _data(
        members: const [_alice, _bob],
        customFronts: const [
          SpCustomFront(id: 'cf-note', name: 'NoteCF'),
          SpCustomFront(id: 'cf-z', name: 'CfMember'),
        ],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-note',
            startTime: DateTime(2024, 1, 1),
            coFronters: const ['cf-z', 'sp-b', 'sp-a'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {
          'cf-note': CfDisposition.mergeAsNote,
          'cf-z': CfDisposition.importAsMember,
        },
      );
      // Run twice — promotion must be stable across runs.
      final r1 = mapper.mapAll(data);
      final mapper2 = SpMapper(
        customFrontDispositions: const {
          'cf-note': CfDisposition.mergeAsNote,
          'cf-z': CfDisposition.importAsMember,
        },
      );
      final r2 = mapper2.mapAll(data);

      final alice1 = r1.members.firstWhere((m) => m.name == 'Alice').id;
      final alice2 = r2.members.firstWhere((m) => m.name == 'Alice').id;
      expect(r1.sessions.first.memberId, alice1);
      expect(r2.sessions.first.memberId, alice2);
    });
  });

  group('Mapper — skip semantics (test 15)', () {
    test('primary cfSkip + all-cfNote co-fronters → entry dropped entirely', () {
      final data = _data(
        customFronts: const [
          SpCustomFront(id: 'cf-skip', name: 'SkipCF'),
          SpCustomFront(id: 'cf-note', name: 'NoteCF'),
        ],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-skip',
            startTime: DateTime(2024, 1, 1),
            coFronters: const ['cf-note'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {
          'cf-skip': CfDisposition.skip,
          'cf-note': CfDisposition.mergeAsNote,
        },
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, isEmpty);
    });
  });

  group('Mapper — unknown sentinel unchanged (test 16)', () {
    test('memberId == "unknown" still produces sessionless session', () {
      final data = _data(
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'unknown',
            startTime: DateTime(2024, 1, 1),
            comment: 'note here',
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.memberId, isNull);
      expect(result.sessions.first.notes, contains('note here'));
      expect(result.sessions.first.sessionType, domain.SessionType.normal);
    });
  });

  // ---- codex-review fixes -------------------------------------------------

  group('Mapper — legacy sessionless emit preserved (codex P1 #1)', () {
    test('unknown sentinel with separate comment emits session + comment', () {
      final data = _data(
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'unknown',
            startTime: DateTime(2024, 1, 1),
          ),
        ],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'f1',
            collection: 'frontHistory',
            text: 'attached',
            time: DateTime(2024, 1, 1, 1),
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.frontComments, hasLength(1));
      expect(
        result.frontComments.first.sessionId,
        result.sessions.first.id,
      );
    });

    test('missing real-member id still emits sessionless session (not dropped)',
        () {
      // Legacy pre-change behavior: unresolved real-member id warns and
      // emits a session with a null primary. Do NOT promote a co-fronter
      // (codex P1 #1: promotion is only for cfSkip/cfNote).
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-ghost',
            startTime: DateTime(2024, 1, 1),
            coFronters: const ['sp-a'],
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      // Primary stays null; Alice is not promoted.
      expect(result.sessions.first.memberId, isNull);
      final aliceId =
          result.members.firstWhere((m) => m.name == 'Alice').id;
      expect(result.sessions.first.coFronterIds, [aliceId]);
      expect(
        result.warnings.any((w) => w.contains('sp-ghost')),
        isTrue,
      );
    });
  });

  group('Mapper — stale CF mapping + synthetic CF (codex P1 #2)', () {
    test('CF deleted from export but flagged isCustomFront: scrubs stale '
        'member mapping and synthesizes as note', () {
      // Prior import recorded cf-ghost as a real member in _memberIdMap.
      // It's no longer in customFronts (deleted). Front-history references
      // it with isCustomFront: true. Expected: scrub mapping, synthesize
      // as mergeAsNote, emit sessionless session with note.
      final data = _data(
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-ghost',
            startTime: DateTime(2024, 1, 1),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        existingMappings: const {
          'member': {'cf-ghost': 'stale-uuid'},
        },
      );
      final result = mapper.mapAll(data);
      // No resolution to stale uuid.
      expect(
        result.sessions.any((s) => s.memberId == 'stale-uuid'),
        isFalse,
      );
      // Stale mapping scrubbed + queued for DAO delete.
      expect(mapper.memberIdMap.containsKey('cf-ghost'), isFalse);
      expect(mapper.pendingStaleMappingDeletes, contains('cf-ghost'));
      // Synthetic CF fallback kicked in.
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.notes, contains('deleted custom front'));
    });
  });

  group('Mapper — cfSleep co-fronter names on sleep path (codex P1 #3)', () {
    test('primary cfSleep + cfNote + cfSleep co-fronters → names appended', () {
      final data = _data(
        customFronts: const [
          SpCustomFront(id: 'cf-sleep-main', name: 'Asleep'),
          SpCustomFront(id: 'cf-nap', name: 'Napping'),
          SpCustomFront(id: 'cf-note', name: 'Blurry'),
        ],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-sleep-main',
            startTime: DateTime(2024, 1, 1),
            endTime: DateTime(2024, 1, 1, 8),
            coFronters: const ['cf-nap', 'cf-note'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {
          'cf-sleep-main': CfDisposition.convertToSleep,
          'cf-nap': CfDisposition.convertToSleep,
          'cf-note': CfDisposition.mergeAsNote,
        },
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      expect(s.sessionType, domain.SessionType.sleep);
      expect(s.notes, contains('Blurry'));
      expect(s.notes, contains('Napping during'));
    });

    test('cfNote co-fronter on cfSleep primary gets "during" suffix', () {
      final data = _data(
        customFronts: const [
          SpCustomFront(id: 'cf-sleep-main', name: 'Asleep'),
          SpCustomFront(id: 'cf-note', name: 'Blurry'),
        ],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf-sleep-main',
            startTime: DateTime(2024, 1, 1),
            endTime: DateTime(2024, 1, 1, 8),
            coFronters: const ['cf-note'],
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {
          'cf-sleep-main': CfDisposition.convertToSleep,
          'cf-note': CfDisposition.mergeAsNote,
        },
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      expect(s.sessionType, domain.SessionType.sleep);
      expect(s.notes, contains('Blurry during'));
    });
  });

  group('Mapper — E5 overlap warning (codex P2 #5)', () {
    test('overlapping sleep + normal session produces overlap warning', () {
      final data = _data(
        members: const [_alice],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1, 0),
            endTime: DateTime(2024, 1, 1, 8),
            isCustomFront: true,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1, 4),
            endTime: DateTime(2024, 1, 1, 10),
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(2));
      expect(
        result.warnings.any((w) =>
            w.contains('sleep sessions overlap') &&
            w.contains('resolve in the Fronting tab')),
        isTrue,
      );
    });

    test(
        'open-ended regular session alongside sleep does not throw and counts overlap',
        () {
      final data = _data(
        members: const [_alice],
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          // Open-ended regular session (null endTime) — previously overflowed
          // DateTime.fromMillisecondsSinceEpoch(1 << 62).
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1, 0),
          ),
          // Sleep session starting later, inside the open-ended regular span.
          SpFrontHistory(
            id: 'f2',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1, 4),
            endTime: DateTime(2024, 1, 1, 10),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      // Must not throw.
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(2));
      expect(
        result.warnings.any((w) => w.contains('sleep sessions overlap')),
        isTrue,
      );
    });

    test('non-overlapping sleep sessions produce no overlap warning', () {
      final data = _data(
        customFronts: const [SpCustomFront(id: 'cf1', name: 'Asleep')],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 1, 0),
            endTime: DateTime(2024, 1, 1, 8),
            isCustomFront: true,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'cf1',
            startTime: DateTime(2024, 1, 2, 0),
            endTime: DateTime(2024, 1, 2, 8),
            isCustomFront: true,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(
        result.warnings.any((w) => w.contains('sleep sessions overlap')),
        isFalse,
      );
    });
  });
}
