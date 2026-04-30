import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:uuid/uuid.dart';

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
  // ---------------------------------------------------------------------------
  // Phase 4A: Per-member shape tests
  // ---------------------------------------------------------------------------

  group('SP importer — 1:1 row mapping (per §2.6)', () {
    test('normal member row maps 1:1 to one Prism session', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1, 10),
            endTime: DateTime(2024, 1, 1, 12),
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      // Exactly one session — no expansion, no collapse.
      expect(result.sessions, hasLength(1));
      final s = result.sessions.first;
      final aliceId = result.members.firstWhere((m) => m.name == 'Alice').id;
      expect(s.memberId, aliceId);
      expect(s.startTime, DateTime(2024, 1, 1, 10));
      expect(s.endTime, DateTime(2024, 1, 1, 12));
    });

    test('multiple rows each produce exactly one Prism session', () {
      final data = _data(
        members: const [_alice, _bob],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1, 9),
            endTime: DateTime(2024, 1, 1, 11),
            live: false,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'sp-b',
            startTime: DateTime(2024, 1, 1, 10),
            endTime: DateTime(2024, 1, 1, 12),
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      // Two rows → two sessions (co-fronting is emergent from overlap).
      expect(result.sessions, hasLength(2));
    });
  });

  group('SP importer — live flag → end_time mapping (per §2.6)', () {
    test('live: true produces end_time = null (active session)', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            // SP always has endTime as int even for live sessions — mapper
            // must ignore it when live: true.
            endTime: DateTime(2024, 1, 1, 23, 59),
            live: true,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.endTime, isNull);
      expect(result.sessions.first.isActive, isTrue);
    });

    test('live: false produces end_time = endTime', () {
      final end = DateTime(2024, 1, 1, 8);
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            endTime: end,
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.endTime, end);
    });

    test('live not set (default false) uses endTime', () {
      final end = DateTime(2024, 6, 1, 18);
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 6, 1, 12),
            endTime: end,
            // live defaults to false
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions.first.endTime, end);
    });
  });

  group('SP importer — customStatus folded into notes (per §2.6)', () {
    test('customStatus only → "[customStatus]" in notes', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            customStatus: 'Co-fronting',
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions.first.notes, '[Co-fronting]');
    });

    test('customStatus + comment → "[customStatus] comment"', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            customStatus: 'Blurry',
            comment: 'felt weird today',
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions.first.notes, '[Blurry] felt weird today');
    });

    test('comment only, no customStatus → comment preserved as-is', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            comment: 'just a note',
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions.first.notes, 'just a note');
    });

    test('no customStatus and no comment → notes is null', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions.first.notes, isNull);
    });
  });

  group('SP importer — member: "unknown" → Unknown sentinel (per §2.6)', () {
    test('unknown sentinel resolves to a real member with name "Unknown"', () {
      final data = _data(
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'unknown',
            startTime: DateTime(2024, 1, 1),
            comment: 'who was here?',
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      // Session must have a non-null memberId pointing to the sentinel.
      expect(result.sessions.first.memberId, isNotNull);
      // The sentinel member must appear in the members list.
      final sentinel = result.members.firstWhere(
        (m) => m.id == result.sessions.first.memberId,
        orElse: () => throw StateError('Unknown sentinel not in members list'),
      );
      expect(sentinel.name, 'Unknown');
      // Notes preserved.
      expect(result.sessions.first.notes, 'who was here?');
    });

    test('sentinel id is deterministic (same input → same id)', () {
      final hist = [
        SpFrontHistory(
          id: 'f1',
          memberId: 'unknown',
          startTime: DateTime(2024, 1, 1),
          live: false,
        ),
      ];
      final r1 = SpMapper().mapAll(_data(frontHistory: hist));
      final r2 = SpMapper().mapAll(_data(frontHistory: hist));
      expect(r1.sessions.first.memberId, r2.sessions.first.memberId);
      // And it equals the derivation formula (v5 in spFrontingNamespace).
      const uuid = Uuid();
      final expectedId = uuid.v5(
        spFrontingNamespace,
        'unknown-member-sentinel',
      );
      expect(r1.sessions.first.memberId, expectedId);
    });

    test('single sentinel created even across multiple unknown rows', () {
      final data = _data(
        frontHistory: [
          SpFrontHistory(
            id: 'f1',
            memberId: 'unknown',
            startTime: DateTime(2024, 1, 1),
            live: false,
          ),
          SpFrontHistory(
            id: 'f2',
            memberId: 'unknown',
            startTime: DateTime(2024, 1, 2),
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      // Two sessions but only one Unknown sentinel member.
      final sentinels = result.members.where((m) => m.name == 'Unknown');
      expect(sentinels, hasLength(1));
      // Both sessions point to the same sentinel.
      expect(
        result.sessions.every((s) => s.memberId == sentinels.first.id),
        isTrue,
      );
    });
  });

  group('SP importer — deterministic IDs (per §2.6)', () {
    test('new row gets deterministic v5 id derived from SP _id', () {
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'mongo-abc123',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            live: false,
          ),
        ],
      );
      final mapper = SpMapper();
      final result = mapper.mapAll(data);
      const uuid = Uuid();
      final expected = uuid.v5(spFrontingNamespace, 'mongo-abc123');
      expect(result.sessions.first.id, expected);
    });

    test('existing row keeps its original ID via sp_id_map lookup', () {
      const existingLocalId = 'legacy-v4-random-uuid';
      final data = _data(
        members: const [_alice],
        frontHistory: [
          SpFrontHistory(
            id: 'mongo-abc123',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
            live: false,
          ),
        ],
      );
      // Seed the session map as if a prior import created the row.
      final mapper = SpMapper(
        existingMappings: const {
          'session': {'mongo-abc123': existingLocalId},
        },
      );
      final result = mapper.mapAll(data);
      // Must reuse the legacy id, NOT generate a fresh v5.
      expect(result.sessions.first.id, existingLocalId);
    });

    test(
      're-import idempotency: same input twice → same row count, same IDs',
      () {
        final hist = [
          SpFrontHistory(
            id: 'sp1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1, 9),
            endTime: DateTime(2024, 1, 1, 11),
            live: false,
          ),
          SpFrontHistory(
            id: 'sp2',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 2, 9),
            endTime: DateTime(2024, 1, 2, 11),
            live: false,
          ),
        ];

        final data = _data(members: const [_alice], frontHistory: hist);

        // First import.
        final mapper1 = SpMapper();
        final r1 = mapper1.mapAll(data);
        // Capture the session ids and the session map produced.
        final sessionMap = Map<String, String>.from(mapper1.sessionIdMap);

        // Second import using the session map from the first run.
        final mapper2 = SpMapper(existingMappings: {'session': sessionMap});
        final r2 = mapper2.mapAll(data);

        expect(r2.sessions, hasLength(r1.sessions.length));
        // IDs are identical — no new rows would be created on upsert.
        final ids1 = r1.sessions.map((s) => s.id).toSet();
        final ids2 = r2.sessions.map((s) => s.id).toSet();
        expect(ids2, ids1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Existing CF disposition tests (still valid — custom fronts are still
  // processed per-row through the disposition tree).
  // ---------------------------------------------------------------------------

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
      expect(result.warnings.any((w) => w.contains('dropped')), isTrue);
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
      expect(result.warnings.any((w) => w.contains('clamped to 24h')), isTrue);
    });

    test(
      'same-start defensive dedup within 60s collapses to one (test 13)',
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
      },
    );
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
          (w) => w.contains('previously-imported custom fronts'),
        ),
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
    test(
      'isCustomFront id missing from customFronts list is handled as note',
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
        expect(result.members.where((m) => m.name != 'Unknown'), isEmpty);
        // Session emitted as sessionless note.
        expect(result.sessions, hasLength(1));
        final s = result.sessions.first;
        expect(s.memberId, isNull);
        expect(s.notes, contains('deleted custom front'));
        expect(
          result.warnings.any(
            (w) =>
                w.contains('deleted in SP') || w.contains('handled as notes'),
          ),
          isTrue,
        );
      },
    );
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
      final memCfId = result.members.firstWhere((m) => m.name == 'MemCF').id;
      expect(fcReminders.any((r) => r.targetMemberId == memCfId), isTrue);
      // mergeAsNote timer has no target.
      expect(fcReminders.any((r) => r.targetMemberId == null), isTrue);

      // Warning surfaces for CF timer changes.
      expect(
        result.warnings.any(
          (w) =>
              w.contains('targeted custom fronts') ||
              w.contains('target dropped or timer removed'),
        ),
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
      // Dropped-comment warning surfaced.
      expect(
        result.warnings.any(
          (w) => w.contains('comments dropped') || w.contains('c1'),
        ),
        isTrue,
      );
    });

    test('converted-sleep session keeps its comments with targetTime set', () {
      final commentTime = DateTime(2024, 1, 1, 4);
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
            time: commentTime,
          ),
        ],
      );
      final mapper = SpMapper(
        customFrontDispositions: const {'cf1': CfDisposition.convertToSleep},
      );
      final result = mapper.mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.frontComments, hasLength(1));
      // Comments now anchor to targetTime, not a sessionId FK.
      expect(result.frontComments.first.targetTime, commentTime);
      expect(result.frontComments.first.body, 'had a dream');
    });
  });

  group('Mapper — active-session collision (test 12, mapper-level)', () {
    test('open-ended cfSleep emits sleep session clamped to 24h', () {
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

  group('Mapper — legacy sessionless emit preserved', () {
    test('unknown sentinel emits session with sentinel memberId + comment', () {
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
      // Unknown now maps to the sentinel member (not null).
      expect(result.sessions.first.memberId, isNotNull);
      expect(result.frontComments, hasLength(1));
      // Comment anchors to targetTime.
      expect(result.frontComments.first.targetTime, DateTime(2024, 1, 1, 1));
    });

    test(
      'missing real-member id still emits sessionless session (not dropped)',
      () {
        // Unresolved real-member id → warn + emit session with null primary.
        final data = _data(
          members: const [_alice],
          frontHistory: [
            SpFrontHistory(
              id: 'f1',
              memberId: 'sp-ghost',
              startTime: DateTime(2024, 1, 1),
            ),
          ],
        );
        final mapper = SpMapper();
        final result = mapper.mapAll(data);
        expect(result.sessions, hasLength(1));
        expect(result.sessions.first.memberId, isNull);
        expect(result.warnings.any((w) => w.contains('sp-ghost')), isTrue);
      },
    );
  });

  group('Mapper — stale CF mapping + synthetic CF', () {
    test('CF deleted from export but flagged isCustomFront: scrubs stale '
        'member mapping and synthesizes as note', () {
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
      expect(result.sessions.any((s) => s.memberId == 'stale-uuid'), isFalse);
      // Stale mapping scrubbed + queued for DAO delete.
      expect(mapper.memberIdMap.containsKey('cf-ghost'), isFalse);
      expect(mapper.pendingStaleMappingDeletes, contains('cf-ghost'));
      // Synthetic CF fallback kicked in.
      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.notes, contains('deleted custom front'));
    });
  });

  group('Mapper — E5 overlap warning', () {
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
        result.warnings.any(
          (w) =>
              w.contains('sleep sessions overlap') &&
              w.contains('resolve in the Fronting tab'),
        ),
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
            // Open-ended regular session (null endTime / live = false for now).
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
      },
    );

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
