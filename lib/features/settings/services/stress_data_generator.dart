import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

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
    this.realisticProfiles = false,
    this.groupMembershipsPerMember,
    this.customFieldValueCoverage,
    this.imageLibraryItems = 0,
    this.memberAvatarEvery = 0,
    this.memberHeaderEvery = 0,
    this.groupAvatarEvery = 0,
    this.groupNestingDepth = 1,
    this.frontingDenseHistory = false,
    this.frontingMinMembersPerSession = 1,
    this.frontingMaxMembersPerSession = 3,
    this.activeFrontingMembers = 0,
  });

  final String label;
  final int members, sessions, conversations, messages, habits, completions;
  final int notes, polls, groups, customFields, years;
  final int estimatedSizeMb, estimatedSeconds;
  final bool realisticProfiles;
  final int? groupMembershipsPerMember;
  final double? customFieldValueCoverage;
  final int imageLibraryItems;
  final int memberAvatarEvery, memberHeaderEvery, groupAvatarEvery;
  final int groupNestingDepth;
  final bool frontingDenseHistory;
  final int frontingMinMembersPerSession, frontingMaxMembersPerSession;
  final int activeFrontingMembers;

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

  // User-report shape: ~1000 members and ~300 groups, with dense profile data.
  // This fixture is meant to reproduce large Android systems where editing
  // member custom fields or assigning group members stresses the mutation path.
  // Fronting history spans a few years with bounded co-front windows, so the
  // fixture stresses long lists without manufacturing impossible 100+ member
  // simultaneous fronts.
  static const reportedLarge = StressPreset(
    label: 'Reported Large',
    members: 1000,
    sessions: 120000,
    conversations: 300,
    messages: 120000,
    habits: 350,
    completions: 25000,
    notes: 2000,
    polls: 200,
    groups: 300,
    customFields: 40,
    years: 3,
    estimatedSizeMb: 1200,
    estimatedSeconds: 600,
    realisticProfiles: true,
    groupMembershipsPerMember: 12,
    customFieldValueCoverage: 0.9,
    imageLibraryItems: 200,
    memberAvatarEvery: 2,
    memberHeaderEvery: 5,
    groupAvatarEvery: 3,
    groupNestingDepth: 8,
    frontingDenseHistory: true,
    frontingMaxMembersPerSession: 10,
    activeFrontingMembers: 10,
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

  // 5000-member version of the user-report fixture. Keeps the same dense
  // group/profile ratios and bounded-fronting shape so it can serve as a
  // deliberately painful dogfood DB.
  static const heavyFiveThousand = StressPreset(
    label: 'Heavy 5K',
    members: 5000,
    sessions: 600000,
    conversations: 1200,
    messages: 600000,
    habits: 1000,
    completions: 125000,
    notes: 10000,
    polls: 750,
    groups: 1500,
    customFields: 80,
    years: 3,
    estimatedSizeMb: 6500,
    estimatedSeconds: 2400,
    realisticProfiles: true,
    groupMembershipsPerMember: 18,
    customFieldValueCoverage: 0.85,
    imageLibraryItems: 1000,
    memberAvatarEvery: 2,
    memberHeaderEvery: 5,
    groupAvatarEvery: 3,
    groupNestingDepth: 10,
    frontingDenseHistory: true,
    frontingMaxMembersPerSession: 10,
    activeFrontingMembers: 10,
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
    final imageTags = List.generate(
      preset.imageLibraryItems,
      (i) => 'stress-img-$i',
    );
    final avatarImages = preset.realisticProfiles
        ? _buildImagePalette(width: 96, height: 96)
        : const <Uint8List>[];
    final headerImages = preset.realisticProfiles
        ? _buildImagePalette(width: 480, height: 160)
        : const <Uint8List>[];

    // --- Shared Image Library ---
    if (preset.imageLibraryItems > 0) {
      sink.add(StressProgress('Media Library', 0, preset.imageLibraryItems));
      for (
        var chunk = 0;
        chunk < preset.imageLibraryItems;
        chunk += _chunkSize
      ) {
        final end = min(chunk + _chunkSize, preset.imageLibraryItems);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final bytes = headerImages.isNotEmpty
                ? headerImages[i % headerImages.length]
                : Uint8List(0);
            batch.insert(
              _db.mediaAttachments,
              MediaAttachmentsCompanion.insert(
                id: 'stress-media-$i',
                tag: Value(imageTags[i]),
                mediaId: Value('stress-media-id-$i'),
                mediaType: const Value('image'),
                encryptionKeyB64: Value(base64Encode(_fakeMediaKey(i))),
                contentHash: Value('stress-content-hash-$i'),
                plaintextHash: Value('stress-plaintext-hash-$i'),
                mimeType: const Value('image/png'),
                sizeBytes: Value(bytes.length),
                width: const Value(480),
                height: const Value(160),
                blurhash: const Value('LKO2?U%2Tw=w]~RBVZRi};RPxuwH'),
              ),
            );
          }
        });
        sink.add(
          StressProgress('Media Library', end, preset.imageLibraryItems),
        );
      }
    }

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
              age: preset.realisticProfiles
                  ? Value('${6 + (i % 70)}')
                  : const Value.absent(),
              bio: preset.realisticProfiles
                  ? Value(_generateMemberBio(i, imageTags))
                  : const Value.absent(),
              avatarImageData: _imageValue(
                avatarImages,
                i,
                preset.memberAvatarEvery,
              ),
              createdAt: DateTime(2020, 1, 1).add(Duration(days: i)),
              customColorEnabled: const Value(true),
              customColorHex: Value(color),
              displayName: preset.realisticProfiles
                  ? Value('Stress Member $i / ${_profileRole(i)}')
                  : const Value.absent(),
              birthday: preset.realisticProfiles
                  ? Value(
                      DateTime(
                        1980 + (i % 35),
                        1 + (i % 12),
                        1 + (i % 27),
                      ).toIso8601String().substring(0, 10),
                    )
                  : const Value.absent(),
              proxyTagsJson: preset.realisticProfiles
                  ? Value(
                      jsonEncode([
                        {'prefix': '[S$i]', 'suffix': null},
                        {'prefix': null, 'suffix': '//$i'},
                      ]),
                    )
                  : const Value.absent(),
              profileHeaderImageData: _imageValue(
                headerImages,
                i,
                preset.memberHeaderEvery,
              ),
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
              description: Value(
                preset.realisticProfiles
                    ? _generateGroupDescription(i)
                    : 'Stress test group $i',
              ),
              colorHex: Value(_colorPalette[i % _colorPalette.length]),
              emoji: Value(_emojis[i % _emojis.length]),
              avatarImageData: _imageValue(
                avatarImages,
                i,
                preset.groupAvatarEvery,
              ),
              displayOrder: Value(i),
              parentGroupId: _parentGroupIdForIndex(groupIds, i, preset),
              createdAt: DateTime(2020, 1, 1).add(Duration(days: i)),
            ),
          );
        }
      });

      // Assign members to groups. Standard presets keep the old 1-2 group
      // shape; heavy presets use dense, hot-spot memberships that resemble
      // large real systems with broad groups plus many narrower labels.
      final entryCompanions = <MemberGroupEntriesCompanion>[];
      final entriesByGroup = List.generate(preset.groups, (_) => <String>[]);
      void addEntry(int memberIndex, int groupIndex) {
        final id = 'stress-mge-$memberIndex-$groupIndex';
        entryCompanions.add(
          MemberGroupEntriesCompanion.insert(
            id: id,
            groupId: groupIds[groupIndex],
            memberId: memberIds[memberIndex],
          ),
        );
        entriesByGroup[groupIndex].add(id);
      }

      for (var m = 0; m < preset.members; m++) {
        if (preset.groupMembershipsPerMember == null) {
          final groupIndex = m % preset.groups;
          addEntry(m, groupIndex);
          if (m % 3 == 0 && preset.groups > 1) {
            addEntry(m, (groupIndex + 1) % preset.groups);
          }
          continue;
        }

        final target = min(preset.groups, preset.groupMembershipsPerMember!);
        final assigned = <int>{};
        assigned.add(m % preset.groups);
        assigned.add(m % min(8, preset.groups));
        assigned.add((m ~/ 4) % min(24, preset.groups));
        assigned.add((m ~/ 17) % min(64, preset.groups));
        while (assigned.length < target) {
          assigned.add(rng.nextInt(preset.groups));
        }
        for (final groupIndex in assigned) {
          addEntry(m, groupIndex);
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

      if (preset.realisticProfiles) {
        for (var chunk = 0; chunk < preset.groups; chunk += _chunkSize) {
          final end = min(chunk + _chunkSize, preset.groups);
          await _db.batch((batch) {
            for (var i = chunk; i < end; i++) {
              final order = entriesByGroup[i];
              if (order.isEmpty) continue;
              batch.update(
                _db.memberGroups,
                MemberGroupsCompanion(
                  sortState: Value(jsonEncode({'mode': 0, 'order': order})),
                ),
                where: (group) => group.id.equals(groupIds[i]),
              );
            }
          });
        }
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
      final fieldTypeIds = List.generate(
        preset.customFields,
        (i) => preset.realisticProfiles ? _heavyFieldTypeId(i) : null,
      );
      await _db.batch((batch) {
        for (var i = 0; i < preset.customFields; i++) {
          final fieldTypeId = fieldTypeIds[i];
          batch.insert(
            _db.customFields,
            CustomFieldsCompanion.insert(
              id: fieldIds[i],
              name: preset.realisticProfiles
                  ? _heavyFieldName(i, fieldTypeId!)
                  : 'Custom Field $i',
              fieldType: preset.realisticProfiles
                  ? _legacyFieldType(fieldTypeId!)
                  : i % 3, // 0=text, 1=number, 2=date
              datePrecision: preset.realisticProfiles && fieldTypeId == 'date'
                  ? Value(i % 6)
                  : const Value.absent(),
              displayOrder: Value(i),
              createdAt: DateTime(2020, 1, 1),
              fieldTypeId: fieldTypeId == null
                  ? const Value.absent()
                  : Value(fieldTypeId),
              parentFieldId:
                  preset.realisticProfiles && i % 10 >= 1 && i % 10 <= 2
                  ? Value(fieldIds[i - (i % 10)])
                  : const Value.absent(),
              typeConfigJson: fieldTypeId == null
                  ? const Value.absent()
                  : Value(_typeConfigJson(i, fieldTypeId)),
            ),
          );
        }
      });

      // Create values for members. Standard presets keep the historic tiny
      // subset so tests stay quick; heavy presets spread values across most
      // members to exercise profile reads and multi-field saves.
      final valueCompanions = <CustomFieldValuesCompanion>[];
      for (var f = 0; f < preset.customFields; f++) {
        final fieldTypeId = fieldTypeIds[f];
        if (fieldTypeId == 'group') continue;
        final legacyMembersWithValue = min(preset.members, 20);
        final coverage = preset.customFieldValueCoverage;
        final memberLimit = coverage == null
            ? legacyMembersWithValue
            : preset.members;
        for (var m = 0; m < memberLimit; m++) {
          if (coverage != null &&
              ((m * 31 + f * 17) % 100) >= (coverage * 100).round()) {
            continue;
          }
          valueCompanions.add(
            CustomFieldValuesCompanion.insert(
              id: 'stress-cfv-$f-$m',
              customFieldId: fieldIds[f],
              memberId: memberIds[m],
              value: preset.realisticProfiles
                  ? _customFieldValue(f, m, fieldTypeId!)
                  : 'Value $f for member $m',
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
    //   - duo / trio / larger co-fronts (up to the preset's configured max)
    //   - staggered start (member joins mid-front, shifted start_time)
    //   - staggered end (member leaves mid-front, shifted end_time)
    //   - tail-active current front (end_time IS NULL only near "now")
    // Dense fixtures place episodes chronologically across the whole span with
    // non-overlapping episode windows. Within one window, staggered per-member
    // rows exercise co-front arithmetic; across windows, the configured max is
    // the actual simultaneous-fronting cap instead of an accidental pile-up.
    final now = DateTime.now();
    final timeSpan = Duration(days: preset.years * 365);
    final earliest = now.subtract(timeSpan);
    final minEpisodeMembers = max(1, preset.frontingMinMembersPerSession);
    final maxEpisodeMembers = min(
      preset.members,
      max(minEpisodeMembers, preset.frontingMaxMembersPerSession),
    );
    final activeRowsToReserve =
        preset.frontingDenseHistory && preset.activeFrontingMembers > 0
        ? min(
            preset.sessions,
            min(maxEpisodeMembers, max(0, preset.activeFrontingMembers)),
          )
        : 0;
    final historicalSessionTarget = preset.sessions - activeRowsToReserve;
    final denseSpacingSeconds = max(
      60,
      timeSpan.inSeconds ~/ max(1, historicalSessionTarget),
    );

    sink.add(StressProgress('Fronting Sessions', 0, preset.sessions));
    var sessionRowsWritten = 0;
    var episodeIdx = 0;
    // Track per-episode metadata so we can layer new-shape comments on top.
    // (Bounded — kept just for the comment-attachment pass below.)
    final episodes = <_StressEpisode>[];
    while (sessionRowsWritten < historicalSessionTarget) {
      // Build one batch worth of episodes.
      final batchTargetEnd = min(
        sessionRowsWritten + _chunkSize,
        historicalSessionTarget,
      );
      await _db.batch((batch) {
        while (sessionRowsWritten < batchTargetEnd) {
          final memberCount = _frontingMemberCountForEpisode(
            rng,
            minMembers: minEpisodeMembers,
            maxMembers: maxEpisodeMembers,
            denseHistory: preset.frontingDenseHistory,
            episodeIndex: episodeIdx,
          );
          final episodeMembers = <String>{};
          while (episodeMembers.length < min(memberCount, preset.members)) {
            episodeMembers.add(
              memberIds[_pickCumulative(rng, memberCumulative)],
            );
          }

          final memberList = episodeMembers.toList();
          final episodeRowCount = min(
            memberList.length,
            historicalSessionTarget - sessionRowsWritten,
          );
          final episodeSlotSeconds = denseSpacingSeconds * episodeRowCount;
          final episodeStart = _frontingEpisodeStart(
            rng,
            denseHistory: preset.frontingDenseHistory,
            earliest: earliest,
            timeSpan: timeSpan,
            timelineSlot: sessionRowsWritten,
            spacingSeconds: denseSpacingSeconds,
          );
          final episodeMinutes = _frontingEpisodeMinutes(
            rng,
            denseHistory: preset.frontingDenseHistory,
            slotSeconds: episodeSlotSeconds,
          );
          final episodeEnd = episodeStart.add(
            Duration(minutes: episodeMinutes),
          );

          // Random-history legacy presets may still have a near-now active
          // front, but never an ancient open-ended row.
          final isActiveEpisode =
              !preset.frontingDenseHistory &&
              episodeStart.isAfter(now.subtract(const Duration(days: 1))) &&
              rng.nextDouble() < 0.25;

          final episodeFronters = <String>[];
          for (var m = 0; m < memberList.length; m++) {
            if (sessionRowsWritten >= historicalSessionTarget) break;
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

    if (activeRowsToReserve > 0) {
      await _db.batch((batch) {
        final activeMembers = <String>{};
        while (activeMembers.length < activeRowsToReserve) {
          activeMembers.add(memberIds[_pickCumulative(rng, memberCumulative)]);
        }
        final activeStart = now.subtract(const Duration(hours: 2));
        final activeList = activeMembers.toList();
        for (var m = 0; m < activeList.length; m++) {
          final memberStart = activeStart.add(Duration(minutes: m * 4));
          batch.insert(
            _db.frontingSessions,
            FrontingSessionsCompanion.insert(
              id: 'stress-session-$episodeIdx-$m',
              startTime: memberStart,
              memberId: Value(activeList[m]),
              notes: m == 0
                  ? Value(_generateText(rng, _noteWords, 10, 30))
                  : const Value.absent(),
              confidence: Value(rng.nextInt(5)),
            ),
          );
          sessionRowsWritten++;
        }
        episodes.add(
          _StressEpisode(
            start: activeStart,
            end: now,
            firstRowId: 'stress-session-$episodeIdx-0',
          ),
        );
        episodeIdx++;
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
            _db.frontingSessions,
            FrontingSessionsCompanion.insert(
              id: 'stress-sleep-$i',
              sessionType: const Value(1),
              startTime: sleepStart,
              endTime: Value(sleepEnd),
              quality: Value(rng.nextInt(6)),
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
          final groupIndex = i - preset.conversations ~/ 3;
          final includesAllMembers = !isDm && groupIndex % 5 == 0;
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
              title: isDm
                  ? const Value.absent()
                  : Value(
                      includesAllMembers
                          ? 'All Members Channel ${groupIndex ~/ 5 + 1}'
                          : 'Chat Room $i',
                    ),
              emoji: isDm
                  ? const Value.absent()
                  : Value(_emojis[i % _emojis.length]),
              isDirectMessage: Value(isDm),
              creatorId: Value(participants.first),
              participantIds: Value(jsonEncode(participants)),
              description: !isDm && preset.realisticProfiles
                  ? Value(_generateGroupDescription(i))
                  : const Value.absent(),
              categoryId: assignCategory
                  ? Value(categoryIds[rng.nextInt(categoryCount)])
                  : const Value.absent(),
              includesAllMembers: Value(includesAllMembers),
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

    // --- Board Messages ---
    final boardPostCount = _boardPostCountForPreset(preset);
    sink.add(StressProgress('Board Messages', 0, boardPostCount));
    if (boardPostCount > 0 && preset.members > 0) {
      for (var chunk = 0; chunk < boardPostCount; chunk += _chunkSize) {
        final end = min(chunk + _chunkSize, boardPostCount);
        await _db.batch((batch) {
          for (var i = chunk; i < end; i++) {
            final writtenAt = earliest.add(
              Duration(seconds: rng.nextInt(timeSpan.inSeconds)),
            );
            final authorId = memberIds[_pickCumulative(rng, memberCumulative)];
            final isPrivate = rng.nextDouble() < 0.35;
            final hasPublicTarget = !isPrivate && rng.nextDouble() < 0.65;
            String? targetMemberId;
            if (isPrivate || hasPublicTarget) {
              targetMemberId =
                  memberIds[_pickCumulative(rng, memberCumulative)];
              if (targetMemberId == authorId && preset.members > 1) {
                var replacementIndex = rng.nextInt(preset.members - 1);
                if (memberIds[replacementIndex] == authorId) {
                  replacementIndex = preset.members - 1;
                }
                targetMemberId = memberIds[replacementIndex];
              }
            }

            var body = _generateText(
              rng,
              _messageWords,
              preset.realisticProfiles ? 18 : 6,
              preset.realisticProfiles ? 80 : 28,
            );
            if (imageTags.isNotEmpty && i % 11 == 0) {
              body =
                  '$body\n\n![Stress board image ${i % imageTags.length}]'
                  '(${imageTags[i % imageTags.length]})';
            }

            batch.insert(
              _db.memberBoardPosts,
              MemberBoardPostsCompanion.insert(
                id: 'stress-board-post-$i',
                targetMemberId: targetMemberId == null
                    ? const Value.absent()
                    : Value(targetMemberId),
                authorId: Value(authorId),
                audience: isPrivate ? 'private' : 'public',
                title: i % 5 == 0
                    ? Value('Board update ${i + 1}')
                    : const Value.absent(),
                body: body,
                createdAt: writtenAt,
                writtenAt: writtenAt,
                editedAt: i % 13 == 0
                    ? Value(writtenAt.add(const Duration(minutes: 7)))
                    : const Value.absent(),
              ),
            );
          }
        });
        sink.add(StressProgress('Board Messages', end, boardPostCount));
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
      'member_board_posts',
      'front_session_comments',
      'habit_completions',
      'poll_votes',
      'poll_options',
      'custom_field_values',
      'member_group_entries',
      'media_attachments',
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
  ///
  /// Checks all major tables so orphaned rows (e.g. media or board posts left
  /// behind by a partial cleanup) don't hide as "nothing to wipe".
  Future<bool> hasStressData() async {
    const tables = [
      'members',
      'fronting_sessions',
      'member_board_posts',
      'media_attachments',
      'notes',
      'conversations',
      'habits',
      'member_groups',
    ];
    for (final table in tables) {
      final row = await _db
          .customSelect(
            "SELECT 1 FROM $table WHERE id LIKE 'stress-%' LIMIT 1",
          )
          .getSingleOrNull();
      if (row != null) return true;
    }
    return false;
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

  static Value<Uint8List?> _imageValue(
    List<Uint8List> images,
    int index,
    int every,
  ) {
    if (every <= 0 || images.isEmpty || index % every != 0) {
      return const Value.absent();
    }
    return Value(images[index % images.length]);
  }

  static List<Uint8List> _buildImagePalette({
    required int width,
    required int height,
  }) {
    return [
      for (final hex in _colorPalette)
        _solidPng(hex, width: width, height: height),
    ];
  }

  static Uint8List _solidPng(
    String hex, {
    required int width,
    required int height,
  }) {
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(r, g, b));
    return Uint8List.fromList(img.encodePng(image, level: 1));
  }

  static Uint8List _fakeMediaKey(int seed) =>
      Uint8List.fromList(List.generate(32, (i) => (seed * 31 + i * 17) & 0xff));

  static String _profileRole(int index) {
    const roles = [
      'Archivist',
      'Caretaker',
      'Protector',
      'Host',
      'Storykeeper',
      'Social',
      'Scout',
      'Analyst',
    ];
    return roles[index % roles.length];
  }

  static String _generateMemberBio(int index, List<String> imageTags) {
    final role = _profileRole(index);
    final image = imageTags.isEmpty
        ? ''
        : '\n\n![Profile reference ${index % imageTags.length}]'
              '(${imageTags[index % imageTags.length]}#50%)';
    return '''
## $role Notes

Stress Member $index has a deliberately long profile used to exercise markdown parsing, profile layout, custom-field spacing, proxy tag display, and image-bearing member rows on low-memory devices.

They usually prefer check-ins with context, low pressure, and enough space for several people to coordinate around the same plan. This paragraph is intentionally wordy so profile previews and edit sheets do real wrapping work instead of rendering a tiny placeholder.

- Communication: prefers clear questions and concise options.
- Scheduling: often overlaps with several other generated members.
- Comfort items: notebooks, color labels, and saved image references.$image

Additional notes: this generated biography includes repeated but realistic operational text so scrolling, preview toggles, markdown rendering, and save flows all have something substantial to process.
''';
  }

  static String _generateGroupDescription(int index) {
    final role = _profileRole(index);
    return '''
Group $index collects members with related roles, history, or day-to-day needs. It has a long description so group detail screens, markdown rendering, and search indexing handle something closer to a real large-system export.

Primary theme: $role. This generated text intentionally includes multiple sentences, punctuation, and repeated descriptive structure. Large systems often use groups for nested organization, temporary project teams, age ranges, fronts, subsystems, and private coordination notes.

The fixture keeps this public-safe and synthetic while still making every group row bigger than a toy example.
''';
  }

  static Value<String?> _parentGroupIdForIndex(
    List<String> groupIds,
    int index,
    StressPreset preset,
  ) {
    if (!preset.realisticProfiles || index == 0 || groupIds.isEmpty) {
      return const Value.absent();
    }

    final depth = min(preset.groups, max(1, preset.groupNestingDepth));
    if (depth <= 1) return const Value.absent();

    // First N groups form a guaranteed deep chain:
    // group-0 -> group-1 -> ... -> group-(depth - 1).
    if (index < depth) return Value(groupIds[index - 1]);

    // Most remaining groups branch from a deterministic level in the chain,
    // with occasional roots left flat so broad group lists stay realistic.
    if (index % 7 == 0) return const Value.absent();
    final parentDepth = 1 + (index % (depth - 1));
    return Value(groupIds[parentDepth - 1]);
  }

  static int _frontingMemberCountForEpisode(
    Random rng, {
    required int minMembers,
    required int maxMembers,
    required bool denseHistory,
    required int episodeIndex,
  }) {
    if (maxMembers <= minMembers) return minMembers;

    if (denseHistory && episodeIndex % 19 == 0) {
      return maxMembers;
    }

    final roll = rng.nextDouble();
    final preferred = maxMembers > 5
        ? roll < 0.38
              ? 1
              : roll < 0.62
              ? 2
              : roll < 0.77
              ? 3
              : roll < 0.87
              ? 4
              : roll < 0.94
              ? 5
              : 6 + rng.nextInt(maxMembers - 5)
        : maxMembers >= 5
        ? roll < 0.40
              ? 1
              : roll < 0.66
              ? 2
              : roll < 0.84
              ? 3
              : roll < 0.94
              ? 4
              : 5
        : roll < 0.50
        ? 1
        : roll < 0.85
        ? 2
        : 3;
    return min(max(preferred, minMembers), maxMembers);
  }

  static DateTime _frontingEpisodeStart(
    Random rng, {
    required bool denseHistory,
    required DateTime earliest,
    required Duration timeSpan,
    required int timelineSlot,
    required int spacingSeconds,
  }) {
    if (!denseHistory) {
      return earliest.add(Duration(seconds: rng.nextInt(timeSpan.inSeconds)));
    }

    final usableSeconds = max(
      1,
      timeSpan.inSeconds - const Duration(hours: 8).inSeconds,
    );
    final jitterSeconds = max(1, spacingSeconds ~/ 10);
    final rawOffset =
        timelineSlot * spacingSeconds + rng.nextInt(jitterSeconds);
    return earliest.add(Duration(seconds: min(rawOffset, usableSeconds)));
  }

  static int _frontingEpisodeMinutes(
    Random rng, {
    required bool denseHistory,
    required int slotSeconds,
  }) {
    if (!denseHistory) return 30 + rng.nextInt(450);

    final maxMinutes = max(5, min(180, (slotSeconds * 0.65 / 60).floor()));
    final minMinutes = max(5, min(30, maxMinutes ~/ 2));
    return minMinutes + rng.nextInt(max(1, maxMinutes - minMinutes + 1));
  }

  static int _boardPostCountForPreset(StressPreset preset) {
    if (preset.members <= 0 || preset.messages <= 0) return 0;
    final perMemberFloor = preset.members * (preset.realisticProfiles ? 12 : 2);
    final messageRatio =
        preset.messages ~/ (preset.realisticProfiles ? 10 : 25);
    return max(1, min(preset.messages, max(perMemberFloor, messageRatio)));
  }

  static String _heavyFieldTypeId(int index) {
    const cycle = [
      'group',
      'text',
      'long_text',
      'choice',
      'scale',
      'slider',
      'date',
      'color',
      'text',
      'long_text',
    ];
    return cycle[index % cycle.length];
  }

  static int _legacyFieldType(String fieldTypeId) => switch (fieldTypeId) {
    'text' => 0,
    'color' => 1,
    'date' => 2,
    'long_text' => 3,
    'choice' => 4,
    'group' => 5,
    'scale' => 6,
    'slider' => 7,
    _ => 0,
  };

  static String _heavyFieldName(int index, String fieldTypeId) {
    final label = switch (fieldTypeId) {
      'group' => 'Profile Section',
      'text' => 'Short Detail',
      'long_text' => 'Long Notes',
      'choice' => 'Preference Choices',
      'scale' => 'Intensity Scale',
      'slider' => 'Spectrum Slider',
      'date' => 'Important Date',
      'color' => 'Color Swatch',
      _ => 'Custom Field',
    };
    return '$label $index';
  }

  static String _typeConfigJson(int index, String fieldTypeId) {
    final config = switch (fieldTypeId) {
      'group' => CustomFieldTypeConfig.group(
        icon: _emojis[index % _emojis.length],
        hideTitleOnProfile: index % 4 == 0,
      ),
      'text' => CustomFieldTypeConfig.text(hideTitleOnProfile: index % 6 == 0),
      'long_text' => CustomFieldTypeConfig.longText(
        hideTitleOnProfile: index % 6 == 0,
      ),
      'color' => CustomFieldTypeConfig.color(
        hideTitleOnProfile: index % 6 == 0,
      ),
      'date' => CustomFieldTypeConfig.date(hideTitleOnProfile: index % 6 == 0),
      'choice' => CustomFieldTypeConfig.choice(
        options: [
          for (var o = 0; o < 8; o++)
            ChoiceOption(
              id: 'stress-choice-$index-$o',
              label: 'Option ${index + 1}.${o + 1}',
              colorHex: '#${_colorPalette[(index + o) % _colorPalette.length]}',
              sortOrder: o,
            ),
        ],
        allowsMultiple: true,
        allowsOther: index % 2 == 0,
      ),
      'scale' => CustomFieldTypeConfig.scale(
        emoji: _emojis[index % _emojis.length],
        steps: 7,
        stepLabels: const [
          'Very low',
          'Low',
          'Mild',
          'Medium',
          'High',
          'Very high',
          'Maximum',
        ],
        displayLayout: index % 2 == 0 ? DisplayLayout.stacked : null,
      ),
      'slider' => const CustomFieldTypeConfig.slider(
        mode: SliderMode.numeric,
        leftLabel: 'Low',
        centerLabel: 'Balanced',
        rightLabel: 'High',
        min: 0,
        max: 100,
        step: 0.5,
        unit: '%',
        showTicks: true,
      ),
      _ => const CustomFieldTypeConfig.text(),
    };
    return jsonEncode(CustomFieldTypeConfigCodec.toJson(config));
  }

  static String _customFieldValue(
    int fieldIndex,
    int memberIndex,
    String fieldTypeId,
  ) {
    return switch (fieldTypeId) {
      'text' => 'Member $memberIndex detail ${fieldIndex % 9}',
      'long_text' =>
        'Generated long-form custom field value for member $memberIndex. '
            'This intentionally spans multiple sentences so custom field '
            'rendering, edit staging, and save commits process realistic text. '
            'Field $fieldIndex captures preferences, context, notes, and '
            'handoff details for a large synthetic system.',
      'color' =>
        '#${_colorPalette[(fieldIndex + memberIndex) % _colorPalette.length]}',
      'date' => DateTime(
        1990 + ((fieldIndex + memberIndex) % 30),
        1 + (memberIndex % 12),
        1 + (fieldIndex % 27),
      ).toIso8601String(),
      'choice' => jsonEncode({
        'options': [
          'stress-choice-$fieldIndex-${memberIndex % 8}',
          if (memberIndex % 5 == 0)
            'stress-choice-$fieldIndex-${(memberIndex + 3) % 8}',
        ],
        if (memberIndex % 11 == 0) 'other': 'Other note $memberIndex',
      }),
      'scale' => '${1 + ((fieldIndex + memberIndex) % 7)}',
      'slider' => ((fieldIndex * 7 + memberIndex) % 201 / 2).toString(),
      _ => 'Value $fieldIndex for member $memberIndex',
    };
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
