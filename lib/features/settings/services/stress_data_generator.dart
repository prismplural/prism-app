import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';

/// Configures the scale of generated stress test data.
class StressPreset {
  const StressPreset({
    required this.label,
    required this.members,
    required this.sessions,
    required this.conversations,
    required this.messages,
    required this.habits,
    required this.completions,
    required this.notes,
    required this.polls,
    required this.groups,
    required this.customFields,
    required this.years,
    required this.estimatedSizeMb,
    required this.estimatedSeconds,
  });

  final String label;
  final int members, sessions, conversations, messages, habits, completions;
  final int notes, polls, groups, customFields, years;
  final int estimatedSizeMb, estimatedSeconds;

  static const medium = StressPreset(
    label: 'Medium',
    members: 50,
    sessions: 5000,
    conversations: 20,
    messages: 5000,
    habits: 30,
    completions: 500,
    notes: 100,
    polls: 10,
    groups: 5,
    customFields: 5,
    years: 2,
    estimatedSizeMb: 30,
    estimatedSeconds: 15,
  );

  static const large = StressPreset(
    label: 'Large',
    members: 200,
    sessions: 50000,
    conversations: 100,
    messages: 50000,
    habits: 100,
    completions: 5000,
    notes: 500,
    polls: 50,
    groups: 15,
    customFields: 10,
    years: 5,
    estimatedSizeMb: 200,
    estimatedSeconds: 60,
  );

  static const extreme = StressPreset(
    label: 'Extreme',
    members: 500,
    sessions: 100000,
    conversations: 200,
    messages: 100000,
    habits: 200,
    completions: 10000,
    notes: 1000,
    polls: 100,
    groups: 30,
    customFields: 15,
    years: 7,
    estimatedSizeMb: 500,
    estimatedSeconds: 180,
  );

  // 5000-member system, 7 years of history. Plural systems this large
  // really exist and this preset is meant to stress every query path.
  static const huge = StressPreset(
    label: 'Huge',
    members: 5000,
    sessions: 500000,
    conversations: 500,
    messages: 500000,
    habits: 500,
    completions: 50000,
    notes: 3000,
    polls: 300,
    groups: 75,
    customFields: 25,
    years: 7,
    estimatedSizeMb: 2500,
    estimatedSeconds: 900,
  );

  // 10000-member system, 7 years. Upper bound for dogfooding — expect
  // multi-GB database and many minutes of generation time.
  static const massive = StressPreset(
    label: 'Massive',
    members: 10000,
    sessions: 1000000,
    conversations: 1000,
    messages: 1000000,
    habits: 1000,
    completions: 100000,
    notes: 6000,
    polls: 500,
    groups: 150,
    customFields: 30,
    years: 7,
    estimatedSizeMb: 5000,
    estimatedSeconds: 1800,
  );
}

/// Progress update emitted during generation.
class StressProgress {
  const StressProgress(this.phase, this.current, this.total);
  final String phase;
  final int current;
  final int total;
  double get fraction => total > 0 ? current / total : 0;
}

/// Internal bookkeeping for a multi-member front "episode" produced by the
/// generator.  The fronting table no longer carries co-fronter lists, so
/// downstream passes (e.g. comment attachment) need a way to recover which
/// per-member rows belong to the same wall-clock event.
class _StressEpisode {
  const _StressEpisode({
    required this.start,
    required this.end,
    required this.firstRowId,
  });
  final DateTime start;
  final DateTime end;
  final String firstRowId;
}

/// Generates large volumes of test data directly into the Drift database,
/// bypassing the repository layer (no sync/CRDT recording).
///
/// All generated IDs are prefixed with `stress-` for easy identification
/// and cleanup.
class StressDataGenerator {
  StressDataGenerator(this._db);
  final AppDatabase _db;

  static const _chunkSize = 2000;

  static const _colorPalette = [
    'FF6B6B',
    'FFA07A',
    'FFD93D',
    '6BCB77',
    '4D96FF',
    '9B59B6',
    'E91E63',
    '00BCD4',
    'FF9800',
    '8BC34A',
    '3F51B5',
    '795548',
    '607D8B',
    'F44336',
    '009688',
  ];

  static const _emojis = [
    '\u{1F60A}',
    '\u{1F31F}',
    '\u{1F308}',
    '\u{2728}',
    '\u{1F33B}',
    '\u{1F338}',
    '\u{1F984}',
    '\u{1F431}',
    '\u{1F436}',
    '\u{1F985}',
    '\u{1F989}',
    '\u{1F98B}',
    '\u{1F33A}',
    '\u{2B50}',
    '\u{1F525}',
    '\u{1F30A}',
    '\u{2744}\u{FE0F}',
    '\u{1F343}',
    '\u{1FA90}',
    '\u{1F48E}',
  ];

  static const _habitNames = [
    'Exercise',
    'Journaling',
    'Meditation',
    'Reading',
    'Hydration',
    'Stretching',
    'Walk outside',
    'Gratitude list',
    'Art practice',
    'Music practice',
    'Cooking',
    'Cleaning',
    'Study session',
    'Yoga',
    'Deep breathing',
    'Therapy homework',
    'Social time',
    'Self-care',
    'Vitamins',
    'Screen break',
  ];

  static const _noteWords = [
    'Today',
    'feeling',
    'noticed',
    'worked',
    'talked',
    'thought',
    'remembered',
    'tried',
    'started',
    'finished',
    'felt',
    'happy',
    'calm',
    'anxious',
    'tired',
    'energetic',
    'creative',
    'focused',
    'distracted',
    'peaceful',
    'about',
    'the',
    'and',
    'with',
    'a',
    'some',
    'really',
    'quite',
    'very',
    'somewhat',
  ];

  static const _messageWords = [
    'hey',
    'hi',
    'hello',
    'how',
    'are',
    'you',
    'doing',
    'good',
    'great',
    'thanks',
    'yeah',
    'sure',
    'okay',
    'sounds',
    'nice',
    'cool',
    'awesome',
    'interesting',
    'agree',
    'think',
    'maybe',
    'probably',
    'definitely',
    'absolutely',
    'right',
    'exactly',
    'lol',
    'haha',
    'true',
    'same',
    'I',
    'we',
    'they',
    'it',
    'was',
    'is',
    'that',
    'this',
    'not',
    'but',
    'and',
    'the',
  ];

  /// Generate stress data, yielding progress updates.
  ///
  /// The whole generation runs inside a single Drift transaction so table
  /// stream notifications are deferred until commit — otherwise every 2000-row
  /// batch would trigger every UI stream to re-query the growing tables,
  /// pegging the CPU and melting the device. One notification fires at the
  /// end for all affected tables.
  Stream<StressProgress> generate(StressPreset preset) {
    final controller = StreamController<StressProgress>();
    scheduleMicrotask(() async {
      try {
        await _db.transaction(() => _generate(preset, controller));
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    });
    return controller.stream;
  }

  Future<void> _generate(
    StressPreset preset,
    StreamController<StressProgress> sink,
  ) async {
    final rng = Random(42); // Deterministic for reproducibility

    // Build Zipf-like member weights for session distribution.
    // Harmonic series: weight(rank) = 1/rank^0.8, so top 10% gets ~60%.
    final memberIds = List.generate(preset.members, (i) => 'stress-member-$i');
    final memberCumulative = _buildCumulative(
      preset.members,
      (i) => 1.0 / pow(i + 1, 0.8),
    );

    // --- Members ---
    sink.add(StressProgress('Members', 0, preset.members));
    for (var chunk = 0; chunk < preset.members; chunk += _chunkSize) {
      final end = min(chunk + _chunkSize, preset.members);
      await _db.batch((batch) {
        for (var i = chunk; i < end; i++) {
          final color = _colorPalette[i % _colorPalette.length];
          batch.insert(
            _db.members,
            MembersCompanion.insert(
              id: memberIds[i],
              name: 'Stress Member $i',
              pronouns: Value(
                i % 3 == 0 ? 'they/them' : (i % 3 == 1 ? 'she/her' : 'he/him'),
              ),
              emoji: Value(_emojis[i % _emojis.length]),
              createdAt: DateTime(2020, 1, 1).add(Duration(days: i)),
              customColorEnabled: const Value(true),
              customColorHex: Value(color),
              displayOrder: Value(i),
            ),
          );
        }
      });
      sink.add(StressProgress('Members', end, preset.members));
    }

    // --- Member Groups ---
    final groupIds = List.generate(preset.groups, (i) => 'stress-group-$i');
    sink.add(StressProgress('Groups', 0, preset.groups));
    if (preset.groups > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < preset.groups; i++) {
          batch.insert(
            _db.memberGroups,
            MemberGroupsCompanion.insert(
              id: groupIds[i],
              name: 'Group $i',
              description: Value('Stress test group $i'),
              colorHex: Value(_colorPalette[i % _colorPalette.length]),
              emoji: Value(_emojis[i % _emojis.length]),
              displayOrder: Value(i),
              createdAt: DateTime(2020, 1, 1).add(Duration(days: i)),
            ),
          );
        }
      });

      // Assign members to groups (each member in 1-2 groups).
      final entryCompanions = <MemberGroupEntriesCompanion>[];
      for (var m = 0; m < preset.members; m++) {
        final groupIndex = m % preset.groups;
        entryCompanions.add(
          MemberGroupEntriesCompanion.insert(
            id: 'stress-mge-$m-$groupIndex',
            groupId: groupIds[groupIndex],
            memberId: memberIds[m],
          ),
        );
        if (m % 3 == 0 && preset.groups > 1) {
          final secondGroup = (groupIndex + 1) % preset.groups;
          entryCompanions.add(
            MemberGroupEntriesCompanion.insert(
              id: 'stress-mge-$m-$secondGroup',
              groupId: groupIds[secondGroup],
              memberId: memberIds[m],
            ),
          );
        }
      }
      for (var chunk = 0; chunk < entryCompanions.length; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, entryCompanions.length);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            batch.insert(_db.memberGroupEntries, entryCompanions[i]);
          }
        });
      }
    }
    sink.add(StressProgress('Groups', preset.groups, preset.groups));

    // --- Custom Fields ---
    final fieldIds = List.generate(
      preset.customFields,
      (i) => 'stress-field-$i',
    );
    sink.add(StressProgress('Custom Fields', 0, preset.customFields));
    if (preset.customFields > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < preset.customFields; i++) {
          batch.insert(
            _db.customFields,
            CustomFieldsCompanion.insert(
              id: fieldIds[i],
              name: 'Custom Field $i',
              fieldType: i % 3, // 0=text, 1=number, 2=date
              displayOrder: Value(i),
              createdAt: DateTime(2020, 1, 1),
            ),
          );
        }
      });

      // Create values for a subset of members.
      final valueCompanions = <CustomFieldValuesCompanion>[];
      for (var f = 0; f < preset.customFields; f++) {
        final membersWithValue = min(preset.members, 20);
        for (var m = 0; m < membersWithValue; m++) {
          valueCompanions.add(
            CustomFieldValuesCompanion.insert(
              id: 'stress-cfv-$f-$m',
              customFieldId: fieldIds[f],
              memberId: memberIds[m],
              value: 'Value $f for member $m',
            ),
          );
        }
      }
      for (var chunk = 0; chunk < valueCompanions.length; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, valueCompanions.length);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            batch.insert(_db.customFieldValues, valueCompanions[i]);
          }
        });
      }
    }
    sink.add(
      StressProgress('Custom Fields', preset.customFields, preset.customFields),
    );

    // --- Fronting Sessions ---
    //
    // Per-member shape (Phase 5 refactor — see
    // docs/plans/fronting-per-member-sessions.md §2.1):
    // every row represents ONE member's continuous presence.  Co-fronting
    // is emergent from overlapping rows, never `co_fronter_ids`.
    //
    // Each "front episode" the generator produces fans out into N rows
    // (one per fronting member), exercising scenarios the new analytics
    // and timeline code must handle:
    //   - solo (1 member)
    //   - duo / trio (2-3 members, fully overlapping)
    //   - staggered start (member joins mid-front, shifted start_time)
    //   - staggered end (member leaves mid-front, shifted end_time)
    //   - active (end_time IS NULL on at least one member)
    // Adjacent episodes are placed back-to-back so we sometimes get gaps
    // between epochs and sometimes touching/near-overlapping epochs across
    // the rng-picked time span.
    final now = DateTime.now();
    final timeSpan = Duration(days: preset.years * 365);
    final earliest = now.subtract(timeSpan);

    sink.add(StressProgress('Fronting Sessions', 0, preset.sessions));
    var sessionRowsWritten = 0;
    var episodeIdx = 0;
    // Track per-episode metadata so we can layer new-shape comments on top.
    // (Bounded — kept just for the comment-attachment pass below.)
    final episodes = <_StressEpisode>[];
    while (sessionRowsWritten < preset.sessions) {
      // Build one batch worth of episodes.
      final batchTargetEnd = min(
        sessionRowsWritten + _chunkSize,
        preset.sessions,
      );
      await _db.batch((batch) {
        while (sessionRowsWritten < batchTargetEnd) {
          // Pick a "primary" presence and 0..2 co-fronters by Zipf weight.
          // ~50% solo, ~35% duo, ~15% trio — typical heavy-co-front shape.
          final coRoll = rng.nextDouble();
          final memberCount = preset.members <= 1
              ? 1
              : coRoll < 0.5
              ? 1
              : coRoll < 0.85
              ? 2
              : 3;
          final episodeMembers = <String>{};
          while (episodeMembers.length < min(memberCount, preset.members)) {
            episodeMembers.add(
              memberIds[_pickCumulative(rng, memberCumulative)],
            );
          }

          final startOffset = Duration(
            seconds: rng.nextInt(timeSpan.inSeconds),
          );
          final episodeStart = earliest.add(startOffset);
          final episodeMinutes = 30 + rng.nextInt(450); // 30 min to 8 hr
          final episodeEnd = episodeStart.add(
            Duration(minutes: episodeMinutes),
          );

          // ~3% of episodes are still active (no end on at least one row).
          final isActiveEpisode = rng.nextDouble() < 0.03;

          final memberList = episodeMembers.toList();
          final episodeFronters = <String>[];
          for (var m = 0; m < memberList.length; m++) {
            if (sessionRowsWritten >= preset.sessions) break;
            final memberId = memberList[m];
            // Stagger start/end for non-primary members so we exercise
            // partial-overlap arithmetic.  The primary (m == 0) anchors the
            // episode; co-fronters can join up to 25% late or leave up to
            // 25% early.
            final memberStart = m == 0
                ? episodeStart
                : episodeStart.add(
                    Duration(
                      minutes: rng.nextInt((episodeMinutes * 0.25).floor() + 1),
                    ),
                  );
            DateTime? memberEnd;
            if (isActiveEpisode && m == 0) {
              memberEnd = null; // primary still fronting
            } else {
              final earlyLeave = m == 0
                  ? 0
                  : rng.nextInt((episodeMinutes * 0.25).floor() + 1);
              memberEnd = episodeEnd.subtract(Duration(minutes: earlyLeave));
              // Guard: never end before start.
              if (!memberEnd.isAfter(memberStart)) {
                memberEnd = memberStart.add(const Duration(minutes: 1));
              }
            }

            batch.insert(
              _db.frontingSessions,
              FrontingSessionsCompanion.insert(
                // Composite id keeps the `stress-` prefix (clearStressData
                // relies on it) while remaining unique per (episode, member).
                // Plain sequential — no v5 namespace; the namespaces in
                // core/constants/fronting_namespaces.dart are reserved for
                // SP/PK/migration/split derivation.
                id: 'stress-session-$episodeIdx-$m',
                startTime: memberStart,
                endTime: memberEnd == null
                    ? const Value.absent()
                    : Value(memberEnd),
                memberId: Value(memberId),
                // co_fronter_ids intentionally NOT set — the column still
                // exists in v7 for legacy/unread storage but new writes
                // leave it at the default (`'[]'`).  Co-fronting under the
                // new model is the overlap of the per-member rows above.
                notes: sessionRowsWritten % 5 == 0
                    ? Value(_generateText(rng, _noteWords, 10, 30))
                    : const Value.absent(),
                confidence: Value(rng.nextInt(5)),
              ),
            );
            episodeFronters.add(memberId);
            sessionRowsWritten++;
          }

          if (episodeFronters.isNotEmpty) {
            episodes.add(
              _StressEpisode(
                start: episodeStart,
                end: episodeEnd,
                firstRowId: 'stress-session-$episodeIdx-0',
              ),
            );
          }
          episodeIdx++;
        }
      });
      sink.add(
        StressProgress(
          'Fronting Sessions',
          sessionRowsWritten,
          preset.sessions,
        ),
      );
    }

    // --- Sleep Sessions ---
    // Generate ~1 sleep session per 2 days across the time span.
    final sleepCount = preset.years * 365 ~/ 2;
    sink.add(StressProgress('Sleep Sessions', 0, sleepCount));
    for (var chunk = 0; chunk < sleepCount; chunk += _chunkSize) {
      final end = min(chunk + _chunkSize, sleepCount);
      await _db.batch((batch) {
        for (var i = chunk; i < end; i++) {
          // Sleep sessions: start in the evening, end in the morning.
          final dayOffset = i * 2 + rng.nextInt(2);
          final sleepStart = earliest
              .add(Duration(days: dayOffset))
              .copyWith(hour: 21 + rng.nextInt(3), minute: rng.nextInt(60));
          final sleepHours = 5 + rng.nextInt(5); // 5-9 hours
          final sleepEnd = sleepStart.add(
            Duration(hours: sleepHours, minutes: rng.nextInt(60)),
          );
          batch.insert(
            _db.sleepSessions,
            SleepSessionsCompanion.insert(
              id: 'stress-sleep-$i',
              startTime: sleepStart,
              endTime: Value(sleepEnd),
              quality: Value(rng.nextInt(5)),
              notes: i % 4 == 0
                  ? Value(_generateText(rng, _noteWords, 3, 10))
                  : const Value.absent(),
            ),
          );
        }
      });
      sink.add(StressProgress('Sleep Sessions', end, sleepCount));
    }

    // --- Conversation Categories ---
    const categoryNames = [
      'General',
      'System Talk',
      'Fun',
      'Venting',
      'Planning',
    ];
    final categoryCount = min(categoryNames.length, preset.conversations ~/ 4);
    final categoryIds = List.generate(categoryCount, (i) => 'stress-cat-$i');
    if (categoryCount > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < categoryCount; i++) {
          batch.insert(
            _db.conversationCategories,
            ConversationCategoriesCompanion.insert(
              id: categoryIds[i],
              name: categoryNames[i],
              displayOrder: Value(i),
              createdAt: earliest,
              modifiedAt: earliest,
            ),
          );
        }
      });
    }

    // --- Conversations & Messages ---
    final conversationIds = List.generate(
      preset.conversations,
      (i) => 'stress-conv-$i',
    );

    // Build participant lists during creation so messages can reference them.
    final convParticipants = <String, List<String>>{};

    sink.add(StressProgress('Conversations', 0, preset.conversations));
    if (preset.conversations > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < preset.conversations; i++) {
          final isDm = i < preset.conversations ~/ 3; // ~33% DMs
          final participantCount = isDm ? 2 : (3 + rng.nextInt(6));
          final participants = <String>[];
          while (participants.length < min(participantCount, preset.members)) {
            final p = memberIds[rng.nextInt(preset.members)];
            if (!participants.contains(p)) participants.add(p);
          }
          convParticipants[conversationIds[i]] = participants;
          final created = earliest.add(
            Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
          );
          // Assign ~60% of group chats to a category.
          final assignCategory =
              !isDm && categoryCount > 0 && rng.nextDouble() < 0.6;
          batch.insert(
            _db.conversations,
            ConversationsCompanion.insert(
              id: conversationIds[i],
              createdAt: created,
              lastActivityAt: now,
              title: isDm ? const Value.absent() : Value('Chat Room $i'),
              emoji: isDm
                  ? const Value.absent()
                  : Value(_emojis[i % _emojis.length]),
              isDirectMessage: Value(isDm),
              creatorId: Value(participants.first),
              participantIds: Value(jsonEncode(participants)),
              categoryId: assignCategory
                  ? Value(categoryIds[rng.nextInt(categoryCount)])
                  : const Value.absent(),
            ),
          );
        }
      });
    }
    sink.add(
      StressProgress(
        'Conversations',
        preset.conversations,
        preset.conversations,
      ),
    );

    // Messages distributed with power law across conversations.
    sink.add(StressProgress('Messages', 0, preset.messages));
    if (preset.messages > 0 && preset.conversations > 0) {
      final convCumulative = _buildCumulative(
        preset.conversations,
        (i) => (preset.conversations - i).toDouble(),
      );

      for (var chunk = 0; chunk < preset.messages; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.messages);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final convId =
                conversationIds[_pickCumulative(rng, convCumulative)];
            final participants = convParticipants[convId]!;
            final authorId = participants[rng.nextInt(participants.length)];
            final msgTime = earliest.add(
              Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
            );
            final contentLength = 5 + rng.nextInt(196);
            final content = _generateText(
              rng,
              _messageWords,
              1,
              contentLength ~/ 5 + 1,
            );

            // ~5% have reactions
            String? reactionsJson;
            if (rng.nextDouble() < 0.05) {
              reactionsJson = jsonEncode([
                {
                  'emoji': _emojis[rng.nextInt(_emojis.length)],
                  'memberId': authorId,
                },
              ]);
            }

            // ~3% are replies to a prior message
            String? replyToId;
            if (i > 0 && rng.nextDouble() < 0.03) {
              replyToId = 'stress-msg-${rng.nextInt(i)}';
            }

            batch.insert(
              _db.chatMessages,
              ChatMessagesCompanion.insert(
                id: 'stress-msg-$i',
                content: content,
                timestamp: msgTime,
                authorId: Value(authorId),
                conversationId: convId,
                reactions: reactionsJson != null
                    ? Value(reactionsJson)
                    : const Value.absent(),
                replyToId: Value(replyToId),
              ),
            );
          }
        });
        sink.add(StressProgress('Messages', end, preset.messages));
      }
    }

    // --- Habits ---
    final habitIds = List.generate(preset.habits, (i) => 'stress-habit-$i');
    sink.add(StressProgress('Habits', 0, preset.habits));
    if (preset.habits > 0) {
      for (var chunk = 0; chunk < preset.habits; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.habits);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final created = earliest.add(
              Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
            );
            batch.insert(
              _db.habits,
              HabitsCompanion.insert(
                id: habitIds[i],
                name: _habitNames[i % _habitNames.length],
                description: Value('Stress test habit $i'),
                colorHex: Value(_colorPalette[i % _colorPalette.length]),
                createdAt: created,
                modifiedAt: created,
                assignedMemberId: i % 4 == 0
                    ? Value(memberIds[i % preset.members])
                    : const Value.absent(),
              ),
            );
          }
        });
        sink.add(StressProgress('Habits', end, preset.habits));
      }
    }

    // --- Habit Completions ---
    sink.add(StressProgress('Completions', 0, preset.completions));
    if (preset.completions > 0 && preset.habits > 0) {
      for (var chunk = 0; chunk < preset.completions; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.completions);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final habitId = habitIds[i % preset.habits];
            final completedAt = earliest.add(
              Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
            );
            batch.insert(
              _db.habitCompletions,
              HabitCompletionsCompanion.insert(
                id: 'stress-hc-$i',
                habitId: habitId,
                completedAt: completedAt,
                completedByMemberId: Value(
                  memberIds[rng.nextInt(preset.members)],
                ),
                createdAt: completedAt,
                modifiedAt: completedAt,
              ),
            );
          }
        });
        sink.add(StressProgress('Completions', end, preset.completions));
      }
    }

    // --- Reminders ---
    const reminderNames = [
      'Check in with everyone',
      'Take meds',
      'Stretch break',
      'Log fronting',
      'Drink water',
      'Therapy prep',
      'Update journal',
      'System meeting',
    ];
    final reminderCount = min(reminderNames.length, preset.habits ~/ 3);
    if (reminderCount > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < reminderCount; i++) {
          final created = earliest.add(
            Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
          );
          batch.insert(
            _db.reminders,
            RemindersCompanion.insert(
              id: 'stress-reminder-$i',
              name: reminderNames[i],
              message: 'Time to ${reminderNames[i].toLowerCase()}!',
              createdAt: created,
              modifiedAt: created,
              trigger: Value(rng.nextInt(3)),
              intervalDays: Value(1 + rng.nextInt(7)),
              isActive: Value(i % 3 != 0), // ~66% active
            ),
          );
        }
      });
    }

    // --- Notes ---
    sink.add(StressProgress('Notes', 0, preset.notes));
    if (preset.notes > 0) {
      for (var chunk = 0; chunk < preset.notes; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.notes);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final date = earliest.add(
              Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
            );
            batch.insert(
              _db.notes,
              NotesCompanion.insert(
                id: 'stress-note-$i',
                title: 'Note $i',
                body: _generateText(rng, _noteWords, 10, 50),
                colorHex: Value(_colorPalette[i % _colorPalette.length]),
                memberId: Value(memberIds[i % preset.members]),
                date: date,
                createdAt: date,
                modifiedAt: date,
              ),
            );
          }
        });
        sink.add(StressProgress('Notes', end, preset.notes));
      }
    }

    // --- Polls ---
    final pollIds = List.generate(preset.polls, (i) => 'stress-poll-$i');
    sink.add(StressProgress('Polls', 0, preset.polls));
    if (preset.polls > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < preset.polls; i++) {
          final created = earliest.add(
            Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
          );
          batch.insert(
            _db.polls,
            PollsCompanion.insert(
              id: pollIds[i],
              question: 'Stress poll question $i?',
              description: Value('Description for poll $i'),
              createdAt: created,
            ),
          );
        }
      });

      // 3-6 options per poll.
      final optionCompanions = <PollOptionsCompanion>[];
      final pollOptionIds = <String, List<String>>{};
      for (var p = 0; p < preset.polls; p++) {
        final optionCount = 3 + rng.nextInt(4);
        final optIds = <String>[];
        for (var o = 0; o < optionCount; o++) {
          final optId = 'stress-pollopt-$p-$o';
          optIds.add(optId);
          optionCompanions.add(
            PollOptionsCompanion.insert(
              id: optId,
              pollId: pollIds[p],
              optionText: 'Option $o for poll $p',
              sortOrder: Value(o),
            ),
          );
        }
        pollOptionIds[pollIds[p]] = optIds;
      }
      for (
        var chunk = 0;
        chunk < optionCompanions.length;
        chunk += _chunkSize
      ) {
        final end = min(chunk + _chunkSize, optionCompanions.length);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            batch.insert(_db.pollOptions, optionCompanions[i]);
          }
        });
      }

      // Some votes.
      final voteCompanions = <PollVotesCompanion>[];
      var voteIndex = 0;
      for (var p = 0; p < preset.polls; p++) {
        final voterCount = min(preset.members, 5 + rng.nextInt(10));
        final options = pollOptionIds[pollIds[p]]!;
        for (var v = 0; v < voterCount; v++) {
          final optId = options[rng.nextInt(options.length)];
          voteCompanions.add(
            PollVotesCompanion.insert(
              id: 'stress-vote-$voteIndex',
              pollOptionId: optId,
              memberId: memberIds[v % preset.members],
              votedAt: now.subtract(Duration(days: rng.nextInt(365))),
            ),
          );
          voteIndex++;
        }
      }
      for (var chunk = 0; chunk < voteCompanions.length; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, voteCompanions.length);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            batch.insert(_db.pollVotes, voteCompanions[i]);
          }
        });
      }
    }
    sink.add(StressProgress('Polls', preset.polls, preset.polls));

    // --- Front Session Comments ---
    //
    // Restored session-attached comments: each comment belongs to a real
    // generated fronting session row, while `timestamp` remains the visible
    // moment the comment is about.
    //
    // Add comments to ~10% of episodes (rather than ~10% of rows, so a
    // multi-member episode doesn't get N times the comments).
    final commentCount = episodes.isEmpty ? 0 : episodes.length ~/ 10;
    sink.add(StressProgress('Comments', 0, commentCount));
    if (commentCount > 0) {
      for (var chunk = 0; chunk < commentCount; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, commentCount);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final episode = episodes[rng.nextInt(episodes.length)];
            // Keep the comment's visible timestamp inside the episode's
            // wall-clock range while attaching it to a real generated row.
            final episodeSpan = episode.end.difference(episode.start);
            final spanSeconds = episodeSpan.inSeconds <= 0
                ? 1
                : episodeSpan.inSeconds;
            final commentTime = episode.start.add(
              Duration(seconds: rng.nextInt(spanSeconds)),
            );
            // createdAt can lag the moment it's about (users back-date
            // notes); pick something between commentTime and now.
            final maxLagSeconds = now
                .difference(commentTime)
                .inSeconds
                .clamp(1, 86400);
            final createdAt = commentTime.add(
              Duration(seconds: rng.nextInt(maxLagSeconds)),
            );
            batch.insert(
              _db.frontSessionComments,
              FrontSessionCommentsCompanion.insert(
                id: 'stress-comment-$i',
                sessionId: episode.firstRowId,
                body: _generateText(rng, _noteWords, 5, 20),
                timestamp: commentTime,
                createdAt: createdAt,
              ),
            );
          }
        });
        sink.add(StressProgress('Comments', end, commentCount));
      }
    }

    sink.add(const StressProgress('Done', 1, 1));
  }

  /// Delete all data with IDs starting with 'stress-'.
  ///
  /// Key insight: the `chat_messages_fts_delete` trigger fires for every row
  /// deleted from `chat_messages`, doing a full FTS table scan each time
  /// (`message_id` is UNINDEXED). With thousands of stress messages this
  /// takes minutes. Fix: delete FTS rows FIRST so the trigger is a no-op,
  /// then delete the base rows.
  ///
  /// Uses a single `transaction` + `customStatement` (silent — no per-table
  /// stream notifications) then one `notifyUpdates` call after commit.
  Future<void> clearStressData() async {
    const tableNames = [
      // FTS first — removes the rows that chat_messages_fts_delete trigger
      // would otherwise scan for on every chat_messages row deletion.
      'chat_messages_fts',
      // Then referencing rows before referenced rows.
      'chat_messages',
      'front_session_comments',
      'habit_completions',
      'poll_votes',
      'poll_options',
      'custom_field_values',
      'member_group_entries',
      'fronting_sessions',
      'sleep_sessions',
      'conversations',
      'conversation_categories',
      'habits',
      'reminders',
      'notes',
      'polls',
      'custom_fields',
      'member_groups',
      'members',
    ];

    // The id column in chat_messages_fts is message_id, not id.
    const ftsWhere = "WHERE message_id LIKE 'stress-%'";
    const defaultWhere = "WHERE id LIKE 'stress-%'";

    await _db.transaction(() async {
      for (final table in tableNames) {
        final where = table == 'chat_messages_fts' ? ftsWhere : defaultWhere;
        await _db.customStatement('DELETE FROM $table $where');
      }
    });

    // Single bulk notification so all Drift stream watchers refresh at once.
    _db.notifyUpdates({
      for (final table in tableNames)
        if (table != 'chat_messages_fts') TableUpdate(table),
    });
  }

  /// Check if any stress data exists in the database.
  Future<bool> hasStressData() async {
    final result = await _db
        .customSelect(
          "SELECT COUNT(*) as c FROM members WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    return result.read<int>('c') > 0;
  }

  /// Check if database has any non-stress data (for the "non-empty DB" warning).
  Future<bool> hasExistingData() async {
    final result = await _db
        .customSelect(
          "SELECT COUNT(*) as c FROM members WHERE id NOT LIKE 'stress-%' AND is_deleted = 0",
        )
        .getSingle();
    return result.read<int>('c') > 0;
  }

  /// Build a cumulative-weight array for O(log N) weighted sampling.
  /// The last entry equals the total weight.
  static List<double> _buildCumulative(int n, double Function(int) weight) {
    final out = List<double>.filled(n, 0);
    var running = 0.0;
    for (var i = 0; i < n; i++) {
      running += weight(i);
      out[i] = running;
    }
    return out;
  }

  /// Pick an index using a precomputed cumulative-weight array via binary
  /// search. O(log N) per call vs. O(N) for the previous linear scan —
  /// the difference between milliseconds and minutes on large presets.
  static int _pickCumulative(Random rng, List<double> cumulative) {
    final roll = rng.nextDouble() * cumulative.last;
    var lo = 0;
    var hi = cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] < roll) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Generate random text from a word pool.
  static String _generateText(
    Random rng,
    List<String> words,
    int minWords,
    int maxWords,
  ) {
    final count = minWords + rng.nextInt(maxWords - minWords + 1);
    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      if (i > 0) buffer.write(' ');
      buffer.write(words[rng.nextInt(words.length)]);
    }
    return buffer.toString();
  }
}
