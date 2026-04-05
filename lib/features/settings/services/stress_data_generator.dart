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
}

/// Progress update emitted during generation.
class StressProgress {
  const StressProgress(this.phase, this.current, this.total);
  final String phase;
  final int current;
  final int total;
  double get fraction => total > 0 ? current / total : 0;
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
    'FF6B6B', 'FFA07A', 'FFD93D', '6BCB77', '4D96FF',
    '9B59B6', 'E91E63', '00BCD4', 'FF9800', '8BC34A',
    '3F51B5', '795548', '607D8B', 'F44336', '009688',
  ];

  static const _emojis = [
    '\u{1F60A}', '\u{1F31F}', '\u{1F308}', '\u{2728}', '\u{1F33B}',
    '\u{1F338}', '\u{1F984}', '\u{1F431}', '\u{1F436}', '\u{1F985}',
    '\u{1F989}', '\u{1F98B}', '\u{1F33A}', '\u{2B50}', '\u{1F525}',
    '\u{1F30A}', '\u{2744}\u{FE0F}', '\u{1F343}', '\u{1FA90}', '\u{1F48E}',
  ];

  static const _habitNames = [
    'Exercise', 'Journaling', 'Meditation', 'Reading', 'Hydration',
    'Stretching', 'Walk outside', 'Gratitude list', 'Art practice',
    'Music practice', 'Cooking', 'Cleaning', 'Study session', 'Yoga',
    'Deep breathing', 'Therapy homework', 'Social time', 'Self-care',
    'Vitamins', 'Screen break',
  ];

  static const _noteWords = [
    'Today', 'feeling', 'noticed', 'worked', 'talked', 'thought',
    'remembered', 'tried', 'started', 'finished', 'felt', 'happy',
    'calm', 'anxious', 'tired', 'energetic', 'creative', 'focused',
    'distracted', 'peaceful', 'about', 'the', 'and', 'with', 'a',
    'some', 'really', 'quite', 'very', 'somewhat',
  ];

  static const _messageWords = [
    'hey', 'hi', 'hello', 'how', 'are', 'you', 'doing', 'good',
    'great', 'thanks', 'yeah', 'sure', 'okay', 'sounds', 'nice',
    'cool', 'awesome', 'interesting', 'agree', 'think', 'maybe',
    'probably', 'definitely', 'absolutely', 'right', 'exactly',
    'lol', 'haha', 'true', 'same', 'I', 'we', 'they', 'it',
    'was', 'is', 'that', 'this', 'not', 'but', 'and', 'the',
  ];

  /// Generate stress data, yielding progress updates.
  Stream<StressProgress> generate(StressPreset preset) async* {
    final rng = Random(42); // Deterministic for reproducibility

    // Build Zipf-like member weights for session distribution.
    // Harmonic series: weight(rank) = 1/rank^0.8, so top 10% gets ~60%.
    final memberIds = List.generate(preset.members, (i) => 'stress-member-$i');
    final weights = List.generate(
      preset.members,
      (i) => 1.0 / pow(i + 1, 0.8),
    );
    final totalWeight = weights.reduce((a, b) => a + b);

    // --- Members ---
    yield StressProgress('Members', 0, preset.members);
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
              pronouns: Value(i % 3 == 0 ? 'they/them' : (i % 3 == 1 ? 'she/her' : 'he/him')),
              emoji: Value(_emojis[i % _emojis.length]),
              createdAt: DateTime(2020, 1, 1).add(Duration(days: i)),
              customColorEnabled: const Value(true),
              customColorHex: Value(color),
              displayOrder: Value(i),
            ),
          );
        }
      });
      yield StressProgress('Members', end, preset.members);
    }

    // --- Member Groups ---
    final groupIds = List.generate(preset.groups, (i) => 'stress-group-$i');
    yield StressProgress('Groups', 0, preset.groups);
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
        entryCompanions.add(MemberGroupEntriesCompanion.insert(
          id: 'stress-mge-$m-$groupIndex',
          groupId: groupIds[groupIndex],
          memberId: memberIds[m],
        ));
        if (m % 3 == 0 && preset.groups > 1) {
          final secondGroup = (groupIndex + 1) % preset.groups;
          entryCompanions.add(MemberGroupEntriesCompanion.insert(
            id: 'stress-mge-$m-$secondGroup',
            groupId: groupIds[secondGroup],
            memberId: memberIds[m],
          ));
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
    yield StressProgress('Groups', preset.groups, preset.groups);

    // --- Custom Fields ---
    final fieldIds = List.generate(
      preset.customFields,
      (i) => 'stress-field-$i',
    );
    yield StressProgress('Custom Fields', 0, preset.customFields);
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
          valueCompanions.add(CustomFieldValuesCompanion.insert(
            id: 'stress-cfv-$f-$m',
            customFieldId: fieldIds[f],
            memberId: memberIds[m],
            value: 'Value $f for member $m',
          ));
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
    yield StressProgress('Custom Fields', preset.customFields, preset.customFields);

    // --- Fronting Sessions ---
    final now = DateTime.now();
    final timeSpan = Duration(days: preset.years * 365);
    final earliest = now.subtract(timeSpan);

    yield StressProgress('Fronting Sessions', 0, preset.sessions);
    for (var chunk = 0; chunk < preset.sessions; chunk += _chunkSize) {
      final end = min(chunk + _chunkSize, preset.sessions);
      await _db.batch((batch) {
        for (var i = chunk; i < end; i++) {
          final memberId = _pickWeighted(rng, memberIds, weights, totalWeight);
          final startOffset = Duration(
            seconds: rng.nextInt(timeSpan.inSeconds),
          );
          final start = earliest.add(startOffset);
          final durationMinutes = 30 + rng.nextInt(450); // 30min to 8hr
          final endTime = start.add(Duration(minutes: durationMinutes));

          // ~20% have co-fronters
          String? coFronterJson;
          if (rng.nextDouble() < 0.2 && preset.members > 1) {
            final count = 1 + rng.nextInt(min(3, preset.members - 1));
            final coFronters = <String>[];
            for (var c = 0; c < count; c++) {
              final cf = memberIds[rng.nextInt(preset.members)];
              if (cf != memberId && !coFronters.contains(cf)) {
                coFronters.add(cf);
              }
            }
            if (coFronters.isNotEmpty) {
              coFronterJson = jsonEncode(coFronters);
            }
          }

          batch.insert(
            _db.frontingSessions,
            FrontingSessionsCompanion.insert(
              id: 'stress-session-$i',
              startTime: start,
              endTime: Value(endTime),
              memberId: Value(memberId),
              coFronterIds: coFronterJson != null
                  ? Value(coFronterJson)
                  : const Value.absent(),
              notes: i % 5 == 0
                  ? Value(_generateText(rng, _noteWords, 10, 30))
                  : const Value.absent(),
              confidence: Value(rng.nextInt(5)),
            ),
          );
        }
      });
      yield StressProgress('Fronting Sessions', end, preset.sessions);
    }

    // --- Conversations & Messages ---
    final conversationIds = List.generate(
      preset.conversations,
      (i) => 'stress-conv-$i',
    );

    // Build participant lists during creation so messages can reference them.
    final convParticipants = <String, List<String>>{};

    yield StressProgress('Conversations', 0, preset.conversations);
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
          final created = earliest.add(Duration(
            seconds: rng.nextInt(timeSpan.inSeconds),
          ));
          batch.insert(
            _db.conversations,
            ConversationsCompanion.insert(
              id: conversationIds[i],
              createdAt: created,
              lastActivityAt: now,
              title: isDm ? const Value.absent() : Value('Chat Room $i'),
              emoji: isDm ? const Value.absent() : Value(_emojis[i % _emojis.length]),
              isDirectMessage: Value(isDm),
              creatorId: Value(participants.first),
              participantIds: Value(jsonEncode(participants)),
            ),
          );
        }
      });
    }
    yield StressProgress('Conversations', preset.conversations, preset.conversations);

    // Messages distributed with power law across conversations.
    yield StressProgress('Messages', 0, preset.messages);
    if (preset.messages > 0 && preset.conversations > 0) {
      // Power-law weights for conversations (double for _pickWeighted).
      final convWeights = List.generate(
        preset.conversations,
        (i) => (preset.conversations - i).toDouble(),
      );
      final convTotalWeight = convWeights.reduce((a, b) => a + b);

      for (var chunk = 0; chunk < preset.messages; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.messages);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final convId = _pickWeighted(
              rng,
              conversationIds,
              convWeights,
              convTotalWeight,
            );
            final participants = convParticipants[convId]!;
            final authorId = participants[rng.nextInt(participants.length)];
            final msgTime = earliest.add(Duration(
              seconds: rng.nextInt(timeSpan.inSeconds),
            ));
            final contentLength = 5 + rng.nextInt(196);
            final content = _generateText(rng, _messageWords, 1, contentLength ~/ 5 + 1);

            // ~5% have reactions
            String? reactionsJson;
            if (rng.nextDouble() < 0.05) {
              reactionsJson = jsonEncode([
                {'emoji': _emojis[rng.nextInt(_emojis.length)], 'memberId': authorId},
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
        yield StressProgress('Messages', end, preset.messages);
      }
    }

    // --- Habits ---
    final habitIds = List.generate(preset.habits, (i) => 'stress-habit-$i');
    yield StressProgress('Habits', 0, preset.habits);
    if (preset.habits > 0) {
      for (var chunk = 0; chunk < preset.habits; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.habits);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final created = earliest.add(Duration(
              seconds: rng.nextInt(timeSpan.inSeconds),
            ));
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
        yield StressProgress('Habits', end, preset.habits);
      }
    }

    // --- Habit Completions ---
    yield StressProgress('Completions', 0, preset.completions);
    if (preset.completions > 0 && preset.habits > 0) {
      for (var chunk = 0; chunk < preset.completions; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.completions);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final habitId = habitIds[i % preset.habits];
            final completedAt = earliest.add(Duration(
              seconds: rng.nextInt(timeSpan.inSeconds),
            ));
            batch.insert(
              _db.habitCompletions,
              HabitCompletionsCompanion.insert(
                id: 'stress-hc-$i',
                habitId: habitId,
                completedAt: completedAt,
                completedByMemberId: Value(memberIds[rng.nextInt(preset.members)]),
                createdAt: completedAt,
                modifiedAt: completedAt,
              ),
            );
          }
        });
        yield StressProgress('Completions', end, preset.completions);
      }
    }

    // --- Notes ---
    yield StressProgress('Notes', 0, preset.notes);
    if (preset.notes > 0) {
      for (var chunk = 0; chunk < preset.notes; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, preset.notes);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final date = earliest.add(Duration(
              seconds: rng.nextInt(timeSpan.inSeconds),
            ));
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
        yield StressProgress('Notes', end, preset.notes);
      }
    }

    // --- Polls ---
    final pollIds = List.generate(preset.polls, (i) => 'stress-poll-$i');
    yield StressProgress('Polls', 0, preset.polls);
    if (preset.polls > 0) {
      await _db.batch((batch) {
        for (var i = 0; i < preset.polls; i++) {
          final created = earliest.add(Duration(
            seconds: rng.nextInt(timeSpan.inSeconds),
          ));
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
          optionCompanions.add(PollOptionsCompanion.insert(
            id: optId,
            pollId: pollIds[p],
            optionText: 'Option $o for poll $p',
            sortOrder: Value(o),
          ));
        }
        pollOptionIds[pollIds[p]] = optIds;
      }
      for (var chunk = 0; chunk < optionCompanions.length; chunk += _chunkSize) {
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
          voteCompanions.add(PollVotesCompanion.insert(
            id: 'stress-vote-$voteIndex',
            pollOptionId: optId,
            memberId: memberIds[v % preset.members],
            votedAt: now.subtract(Duration(days: rng.nextInt(365))),
          ));
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
    yield StressProgress('Polls', preset.polls, preset.polls);

    // --- Front Session Comments ---
    // Add comments to ~10% of sessions.
    final commentCount = preset.sessions ~/ 10;
    yield StressProgress('Comments', 0, commentCount);
    if (commentCount > 0) {
      for (var chunk = 0; chunk < commentCount; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, commentCount);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final sessionIdx = rng.nextInt(preset.sessions);
            final ts = now.subtract(Duration(days: rng.nextInt(365)));
            batch.insert(
              _db.frontSessionComments,
              FrontSessionCommentsCompanion.insert(
                id: 'stress-comment-$i',
                sessionId: 'stress-session-$sessionIdx',
                body: _generateText(rng, _noteWords, 5, 20),
                timestamp: ts,
                createdAt: ts,
              ),
            );
          }
        });
        yield StressProgress('Comments', end, commentCount);
      }
    }

    yield const StressProgress('Done', 1, 1);
  }

  /// Delete all data with IDs starting with 'stress-'.
  Future<void> clearStressData() async {
    const tables = [
      'chat_messages',
      'front_session_comments',
      'habit_completions',
      'poll_votes',
      'poll_options',
      'custom_field_values',
      'member_group_entries',
      'fronting_sessions',
      'conversations',
      'habits',
      'notes',
      'polls',
      'custom_fields',
      'member_groups',
      'members',
    ];
    for (final table in tables) {
      await _db.customStatement(
        "DELETE FROM $table WHERE id LIKE 'stress-%'",
      );
    }
    // Clean up FTS entries for deleted messages.
    await _db.customStatement(
      "DELETE FROM chat_messages_fts WHERE message_id LIKE 'stress-%'",
    );
  }

  /// Check if any stress data exists in the database.
  Future<bool> hasStressData() async {
    final result = await _db.customSelect(
      "SELECT COUNT(*) as c FROM members WHERE id LIKE 'stress-%'",
    ).getSingle();
    return result.read<int>('c') > 0;
  }

  /// Check if database has any non-stress data (for the "non-empty DB" warning).
  Future<bool> hasExistingData() async {
    final result = await _db.customSelect(
      "SELECT COUNT(*) as c FROM members WHERE id NOT LIKE 'stress-%' AND is_deleted = 0",
    ).getSingle();
    return result.read<int>('c') > 0;
  }

  /// Pick a random element using weighted distribution.
  static T _pickWeighted<T>(
    Random rng,
    List<T> items,
    List<double> weights,
    double totalWeight,
  ) {
    var roll = rng.nextDouble() * totalWeight;
    for (var i = 0; i < items.length; i++) {
      roll -= weights[i];
      if (roll < 0) return items[i];
    }
    return items.last;
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
