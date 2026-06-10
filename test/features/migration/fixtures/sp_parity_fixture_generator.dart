// ignore_for_file: use_null_aware_elements, unnecessary_brace_in_string_interps
// Generator for the SP-import parity-harness fixtures.
//
// Hand-written fixtures for small/medium/unpaired are fine, but the `large`
// fixture (~10k messages, ~2k poll votes) is impractical to hand-roll. Both
// the generator output AND the resulting JSON are committed; the generator
// exists so the fixtures are reproducible and so anyone reviewing this PR
// can verify the shape without grokking 30k lines of JSON.
//
// Run via:
//   flutter test test/features/migration/fixtures/sp_parity_fixture_generator.dart \
//       --tags=fixture-gen
//
// (Gated behind a tag so it does not run in normal CI.)
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fixture-gen', () {
    test('write small/medium/large/unpaired/failing_tx', () {
      _writeFixture('sp_parity_small.json', _makeSmall());
      _writeFixture('sp_parity_medium.json', _makeMedium());
      _writeFixture('sp_parity_large.json', _makeLarge());
      _writeFixture('sp_parity_unpaired.json', _makeUnpaired());
      _writeFixture('sp_parity_failing_tx.json', _makeFailingTx());
    }, tags: ['fixture-gen']);

    // Power-user smoke fixture for real-device perf testing. NOT part of the
    // parity suite (no golden, no diff check) — separate tag so neither default
    // CI nor `--tags=fixture-gen` regenerates it. Output is committed.
    test(
      'generate power-user smoke fixture',
      () {
        _writeFixtureCompact('sp_smoke_power_user.json', _makePowerUser());
      },
      tags: ['smoke-fixture'],
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

void _writeFixture(String name, Map<String, dynamic> data) {
  // Write to the same directory as this generator.
  final out = File('test/features/migration/fixtures/$name');
  const encoder = JsonEncoder.withIndent('  ');
  out.writeAsStringSync('${encoder.convert(data)}\n');
  // ignore: avoid_print
  print('Wrote $name (${out.lengthSync()} bytes)');
}

/// Compact JSON variant for the power-user smoke fixture. SP server emits
/// compact JSON, and at this size pretty-printing roughly triples the file.
void _writeFixtureCompact(String name, Map<String, dynamic> data) {
  final out = File('test/features/migration/fixtures/$name');
  out.writeAsStringSync(jsonEncode(data));
  // ignore: avoid_print
  print('Wrote $name (${out.lengthSync()} bytes)');
}

// ---------------------------------------------------------------------------
// Schema builders
// ---------------------------------------------------------------------------

/// SP `members` entry shape (mirrors `SpMember.fromJson`).
Map<String, dynamic> _member({
  required String id,
  required String name,
  String? pronouns,
  String? color,
  String? desc,
  bool archived = false,
}) => {
  '_id': id,
  'name': name,
  if (pronouns != null) 'pronouns': pronouns,
  if (color != null) 'color': color,
  if (desc != null) 'desc': desc,
  if (archived) 'archived': true,
};

/// SP `groups` entry shape (mirrors `SpGroup.fromJson`).
Map<String, dynamic> _group({
  required String id,
  required String name,
  List<String> memberIds = const [],
  String? color,
  String? emoji,
  String? parent,
  String? desc,
}) => {
  '_id': id,
  'name': name,
  if (desc != null) 'desc': desc,
  'members': memberIds,
  if (color != null) 'color': color,
  if (emoji != null) 'emoji': emoji,
  if (parent != null) 'parent': parent,
};

/// SP `channels` entry shape.
Map<String, dynamic> _channel({
  required String id,
  required String name,
  List<String> memberIds = const [],
  String? desc,
  int? createdAtMs,
}) => {
  '_id': id,
  'name': name,
  if (desc != null) 'desc': desc,
  'members': memberIds,
  if (createdAtMs != null)
    'createdAt': DateTime.fromMillisecondsSinceEpoch(
      createdAtMs,
    ).toIso8601String(),
};

/// SP `frontHistory` entry shape.
Map<String, dynamic> _frontHistory({
  required String id,
  required String memberId,
  required int startMs,
  required int endMs,
}) => {'_id': id, 'member': memberId, 'startTime': startMs, 'endTime': endMs};

/// SP `chatMessages` entry shape.
Map<String, dynamic> _message({
  required String id,
  required String channelId,
  required String senderId,
  required String content,
  required int timestampMs,
}) => {
  '_id': id,
  'channel': channelId,
  'sender': senderId,
  'message': content,
  'timestamp': timestampMs,
};

/// SP `polls` entry shape.
Map<String, dynamic> _poll({
  required String id,
  required String question,
  required List<Map<String, dynamic>> options,
  required List<Map<String, dynamic>> votes,
  bool allowMultiple = false,
}) => {
  '_id': id,
  'question': question,
  'options': options,
  'votes': votes,
  if (allowMultiple) 'allowMultiple': true,
};

Map<String, dynamic> _pollOption(String name, [String? color]) => {
  'name': name,
  if (color != null) 'color': color,
};

Map<String, dynamic> _pollVote({
  required String memberId,
  required String optionName,
  String? comment,
}) => {
  'id': memberId,
  'vote': optionName,
  if (comment != null) 'comment': comment,
};

Map<String, dynamic> _customFieldDef({
  required String id,
  required String name,
  int type = 0,
  bool supportMarkdown = false,
}) => {
  '_id': id,
  'name': name,
  'type': type,
  if (supportMarkdown) 'supportMarkdown': true,
};

// ---------------------------------------------------------------------------
// Fixture composition
// ---------------------------------------------------------------------------

/// `small` — 5 members, 1 group, 10 sessions, 20 messages. No polls, no
/// custom fields. Used as the fast-feedback fixture for every test run.
Map<String, dynamic> _makeSmall() {
  const baseStart = 1_700_000_000_000; // 2023-11-14 UTC
  const sessionDur = 60 * 60 * 1000; // 1h

  final members = List.generate(
    5,
    (i) => _member(
      id: 'sp-mem-${_pad(i)}',
      name: 'Member ${_pad(i)}',
      pronouns: i.isEven ? 'they/them' : 'she/her',
      color: '#${i.toRadixString(16).padLeft(2, '0')}aabb',
    ),
  );

  final groups = [
    _group(
      id: 'sp-grp-00',
      name: 'Group 00',
      memberIds: ['sp-mem-00', 'sp-mem-01', 'sp-mem-02'],
    ),
  ];

  final channels = [
    _channel(
      id: 'sp-chan-00',
      name: 'general',
      memberIds: ['sp-mem-00', 'sp-mem-01'],
      createdAtMs: baseStart,
    ),
  ];

  final frontHistory = List.generate(
    10,
    (i) => _frontHistory(
      id: 'sp-front-${_pad(i)}',
      memberId: 'sp-mem-${_pad(i % 5)}',
      startMs: baseStart + i * sessionDur,
      endMs: baseStart + (i + 1) * sessionDur - 1,
    ),
  );

  final messages = List.generate(
    20,
    (i) => _message(
      id: 'sp-msg-${_pad(i)}',
      channelId: 'sp-chan-00',
      senderId: 'sp-mem-${_pad(i % 5)}',
      content: 'Hello $i',
      timestampMs: baseStart + i * 60 * 1000,
    ),
  );

  return {
    'settings': {'systemName': 'Small System'},
    'users': [
      {
        'username': 'small-user',
        'color': '#112233',
        'desc': 'Small system description.',
        'uid': 'uid-small',
      },
    ],
    'members': members,
    'frontStatuses': <Map<String, dynamic>>[],
    'frontHistory': frontHistory,
    'groups': groups,
    'channels': channels,
    'chatMessages': messages,
    'polls': <Map<String, dynamic>>[],
    'notes': <Map<String, dynamic>>[],
    'comments': <Map<String, dynamic>>[],
    'customFields': <Map<String, dynamic>>[],
    'boardMessages': <Map<String, dynamic>>[],
  };
}

/// `medium` — 20 members, 5 groups, 200 sessions, 500 messages, 3 polls ×
/// 50 votes, custom fields, system settings.
Map<String, dynamic> _makeMedium() {
  const baseStart = 1_700_000_000_000;
  const sessionDur = 30 * 60 * 1000; // 30m

  final customFields = List.generate(
    3,
    (i) => _customFieldDef(
      id: 'sp-cf-${_pad(i)}',
      name: 'Custom Field $i',
      type: 0,
    ),
  );

  final members = List.generate(20, (i) {
    final m = _member(
      id: 'sp-mem-${_pad(i)}',
      name: 'Medium Member $i',
      pronouns: i.isEven ? 'they/them' : 'she/her',
      color:
          '#${(i * 7).toRadixString(16).padLeft(2, '0').substring(0, 2)}beef',
      desc: 'Member $i bio.',
      archived: i % 9 == 0,
    );
    return {
      ...m,
      'info': {
        for (var j = 0; j < customFields.length; j++)
          'sp-cf-${_pad(j)}': 'value-${i}-${j}',
      },
    };
  });

  final groups = List.generate(
    5,
    (i) => _group(
      id: 'sp-grp-${_pad(i)}',
      name: 'Medium Group $i',
      memberIds: List.generate(4, (k) => 'sp-mem-${_pad(i * 4 + k)}'),
    ),
  );

  final channels = List.generate(
    3,
    (i) => _channel(
      id: 'sp-chan-${_pad(i)}',
      name: 'channel-$i',
      memberIds: List.generate(5, (k) => 'sp-mem-${_pad(k)}'),
      createdAtMs: baseStart,
    ),
  );

  final frontHistory = List.generate(
    200,
    (i) => _frontHistory(
      id: 'sp-front-${_pad(i)}',
      memberId: 'sp-mem-${_pad(i % 20)}',
      startMs: baseStart + i * sessionDur,
      endMs: baseStart + (i + 1) * sessionDur - 1,
    ),
  );

  final messages = List.generate(
    500,
    (i) => _message(
      id: 'sp-msg-${_pad(i)}',
      channelId: 'sp-chan-${_pad(i % 3)}',
      senderId: 'sp-mem-${_pad(i % 20)}',
      content: 'Medium message $i',
      timestampMs: baseStart + i * 30 * 1000,
    ),
  );

  final polls = List.generate(3, (p) {
    final optionNames = ['Yes', 'No', 'Maybe'];
    return _poll(
      id: 'sp-poll-${_pad(p)}',
      question: 'Poll $p question?',
      options: optionNames.map(_pollOption).toList(),
      votes: List.generate(50, (v) {
        return _pollVote(
          memberId: 'sp-mem-${_pad(v % 20)}',
          optionName: optionNames[v % optionNames.length],
          comment: v.isEven ? null : 'comment-$v',
        );
      }),
    );
  });

  return {
    'settings': {'systemName': 'Medium System'},
    'users': [
      {
        'username': 'medium-user',
        'color': '#44ff99',
        'desc': 'Medium system description.',
        'uid': 'uid-medium',
      },
    ],
    'members': members,
    'frontStatuses': <Map<String, dynamic>>[],
    'frontHistory': frontHistory,
    'groups': groups,
    'channels': channels,
    'chatMessages': messages,
    'polls': polls,
    'customFields': customFields,
    'notes': <Map<String, dynamic>>[],
    'comments': <Map<String, dynamic>>[],
    'boardMessages': <Map<String, dynamic>>[],
  };
}

/// `large` — 100 members, 20 groups, 2k sessions, 10k messages, 10 polls ×
/// 200 votes, full custom fields, board posts.
Map<String, dynamic> _makeLarge() {
  const baseStart = 1_700_000_000_000;
  const sessionDur = 15 * 60 * 1000;

  final customFields = List.generate(
    5,
    (i) => _customFieldDef(
      id: 'sp-cf-${_pad(i)}',
      name: 'Large CF $i',
      type: i % 2,
    ),
  );

  final members = List.generate(100, (i) {
    final m = _member(
      id: 'sp-mem-${_pad(i)}',
      name: 'Large Member $i',
      pronouns: ['they/them', 'she/her', 'he/him'][i % 3],
      color: '#${i.toRadixString(16).padLeft(6, '0').substring(0, 6)}',
      desc: 'Bio $i.',
      archived: i % 17 == 0,
    );
    return {
      ...m,
      'info': {
        for (var j = 0; j < customFields.length; j++)
          'sp-cf-${_pad(j)}': 'v$i-$j',
      },
    };
  });

  final groups = List.generate(
    20,
    (i) => _group(
      id: 'sp-grp-${_pad(i)}',
      name: 'Large Group $i',
      memberIds: List.generate(5, (k) => 'sp-mem-${_pad((i * 5 + k) % 100)}'),
    ),
  );

  final channels = List.generate(
    5,
    (i) => _channel(
      id: 'sp-chan-${_pad(i)}',
      name: 'large-channel-$i',
      memberIds: List.generate(10, (k) => 'sp-mem-${_pad(k)}'),
      createdAtMs: baseStart,
    ),
  );

  final frontHistory = List.generate(
    2000,
    (i) => _frontHistory(
      id: 'sp-front-${_pad(i, width: 5)}',
      memberId: 'sp-mem-${_pad(i % 100)}',
      startMs: baseStart + i * sessionDur,
      endMs: baseStart + (i + 1) * sessionDur - 1,
    ),
  );

  final messages = List.generate(
    10000,
    (i) => _message(
      id: 'sp-msg-${_pad(i, width: 6)}',
      channelId: 'sp-chan-${_pad(i % 5)}',
      senderId: 'sp-mem-${_pad(i % 100)}',
      content: 'msg $i',
      timestampMs: baseStart + i * 6000,
    ),
  );

  final polls = List.generate(10, (p) {
    final names = ['Yes', 'No', 'Abstain', 'Veto'];
    return _poll(
      id: 'sp-poll-${_pad(p)}',
      question: 'Large poll $p?',
      options: names.map(_pollOption).toList(),
      votes: List.generate(
        200,
        (v) => _pollVote(
          memberId: 'sp-mem-${_pad(v % 100)}',
          optionName: names[v % names.length],
          comment: v % 7 == 0 ? 'large-comment-$v' : null,
        ),
      ),
    );
  });

  final boardMessages = List.generate(
    50,
    (i) => {
      '_id': 'sp-board-${_pad(i)}',
      'writtenFor': 'sp-mem-${_pad(i % 100)}',
      'writtenBy': 'sp-mem-${_pad((i + 1) % 100)}',
      'message': 'Board $i body',
      'writtenAt': baseStart + i * 1000 * 60,
      'read': i.isEven,
    },
  );

  // exercise Phase 6 batch paths for notes,
  // comments, conversation (channel) categories, and reminders. The small and
  // medium fixtures stay deliberately minimal so the large fixture carries the
  // breadth here.

  // 10 notes (`batchInsertNotes`). Bind a subset to specific members and leave
  // others system-level (null `member`) to cover both shapes.
  final notes = List.generate(
    10,
    (i) => {
      '_id': 'sp-note-${_pad(i)}',
      'title': 'Note $i title',
      'note': 'Body of note $i with a few words of content.',
      if (i % 3 != 0) 'color': '#${i.toRadixString(16).padLeft(6, '0')}',
      if (i.isEven) 'member': 'sp-mem-${_pad(i % 100)}',
      'date': baseStart + i * 60 * 60 * 1000,
    },
  );

  // 10 front-session comments (`batchInsertComments`). `collection` must be
  // `frontHistory` and `documentId` must match a `frontHistory._id` or the
  // mapper drops it (see sp_mapper.dart:_mapFrontComments). Bind them to the
  // first 10 front history ids so all 10 successfully map and emit.
  final comments = List.generate(
    10,
    (i) => {
      '_id': 'sp-comment-${_pad(i)}',
      'documentId': 'sp-front-${_pad(i, width: 5)}',
      'collection': 'frontHistory',
      'text': 'Comment $i on front session.',
      'time': baseStart + i * 5 * 60 * 1000,
    },
  );

  // 5 conversation (channel) categories (`batchInsertCategories`). The mapper
  // doesn't require a non-empty `channels` array, but include one for shape
  // realism on a subset.
  final channelCategories = List.generate(
    5,
    (i) => {
      '_id': 'sp-cat-${_pad(i)}',
      'name': 'Category $i',
      'channels': i.isEven ? <String>['sp-chan-${_pad(i % 5)}'] : <String>[],
    },
  );

  // 5 reminders, split across `automatedReminders` (3) and `repeatedReminders`
  // (2) so both branches of `_mapTimers` run. Both flow into the same
  // `batchInsertReminders` Phase 6 batch.
  //
  // Use type 2 (any front change) for automated timers so we don't have to
  // resolve a target member id; that keeps the reminder count deterministic
  // (`_mapTimers` never drops these for unresolved targets).
  final automatedReminders = List.generate(
    3,
    (i) => {
      '_id': 'sp-auto-${_pad(i)}',
      'name': 'Auto timer $i',
      'message': 'Switch reminder $i',
      'delayInHours': i + 1,
      'enabled': i != 1,
      'type': 2,
    },
  );
  final repeatedReminders = List.generate(
    2,
    (i) => {
      '_id': 'sp-rep-${_pad(i)}',
      'name': 'Repeated timer $i',
      'message': 'Daily ping $i',
      'dayInterval': i + 1,
      'time': '09:${i.toString().padLeft(2, '0')}',
      'enabled': true,
    },
  );

  return {
    'settings': {'systemName': 'Large System'},
    'users': [
      {
        'username': 'large-user',
        'color': '#ff0066',
        'desc': 'Large system description.',
        'uid': 'uid-large',
      },
    ],
    'members': members,
    'frontStatuses': <Map<String, dynamic>>[],
    'frontHistory': frontHistory,
    'groups': groups,
    'channels': channels,
    'channelCategories': channelCategories,
    'chatMessages': messages,
    'polls': polls,
    'customFields': customFields,
    'boardMessages': boardMessages,
    'notes': notes,
    'comments': comments,
    'automatedReminders': automatedReminders,
    'repeatedReminders': repeatedReminders,
  };
}

/// `power-user` — independent smoke fixture sized for a 5-6 year SP daily
/// driver. Generated separately from the parity suite (no golden, no parity
/// diff). Tagged `smoke-fixture` in the test runner so it is not regenerated
/// by default; the committed JSON is the artifact the real-device perf smoke
/// test consumes.
///
/// Counts (see Phase smoke plan):
///   - 5,000 members          - 10,000 front sessions
///   - 15 custom fields       - ~45k field values (60% fill)
///   - 50 groups              - ~15k group memberships (~3/member, randomized)
///   - 20 channels            - 10 channel categories
///   - 50,000 messages        - 30 polls × 5 options × 20 votes = 3,000 votes
///   - 100 notes              - 5,000 front-session comments (~1 per 2)
///   - 200 board posts        - 8 automated + 12 repeated reminders
///
/// Determinism: a fixed-seed `Random` drives all randomized fields (group
/// memberships, custom-field fill, comment binding, etc.) so anyone running
/// the generator gets byte-identical output across machines / Dart versions.
Map<String, dynamic> _makePowerUser() {
  final rng = Random(42);
  const baseStart = 1_700_000_000_000; // 2023-11-14 UTC
  const sessionDur = 15 * 60 * 1000; // 15m

  // -- Custom field defs (15) ------------------------------------------------
  final customFields = List.generate(
    15,
    (i) => _customFieldDef(
      id: 'sp-cf-${_pad(i, width: 2)}',
      name: 'Power CF $i',
      type: i % 2,
      supportMarkdown: i % 4 == 0,
    ),
  );

  // -- Members (5,000) -------------------------------------------------------
  // 60% fill rate per (member × field) — randomized, deterministic.
  // ~70% of members also get an `avatarUrl` pointing at a deterministic
  // Picsum seed so the real-device smoke exercises Phase 2's chunked
  // parallel avatar fetch path. Seed = the member's _id ⇒ same image bytes
  // every run, same fixture every run.
  final members = List.generate(5000, (i) {
    final memberId = 'sp-mem-${_pad(i, width: 4)}';
    final m = _member(
      id: memberId,
      name: 'Power Member $i',
      pronouns: ['they/them', 'she/her', 'he/him', 'xe/xem', 'it/its'][i % 5],
      color: '#${i.toRadixString(16).padLeft(6, '0').substring(0, 6)}',
      desc:
          'Bio for member $i. '
          'Some longer narrative content to approximate a real heavy user.',
      archived: i % 23 == 0,
    );
    final info = <String, dynamic>{};
    for (var j = 0; j < customFields.length; j++) {
      if (rng.nextDouble() < 0.6) {
        info['sp-cf-${_pad(j, width: 2)}'] = 'v$i-$j';
      }
    }
    // Avatar fill: ~70% of members get a URL. Must use the same seeded rng
    // so the fixture stays byte-identical across runs.
    final hasAvatar = rng.nextDouble() < 0.7;
    return {
      ...m,
      'info': info,
      if (hasAvatar) 'avatarUrl': 'https://picsum.photos/seed/$memberId/256',
    };
  });

  // -- Groups (50) with randomized memberships (~3 groups per member) --------
  // Strategy: for each member, sample ~3 distinct group indices, then invert
  // the map. Average target = 5000 * 3 = 15,000 memberships total.
  final groupMemberLists = List.generate(50, (_) => <String>[]);
  for (var i = 0; i < 5000; i++) {
    // Per-member count: 2-4 (avg ~3), randomized.
    final perMember = 2 + rng.nextInt(3); // 2, 3, or 4
    final picked = <int>{};
    while (picked.length < perMember) {
      picked.add(rng.nextInt(50));
    }
    for (final g in picked) {
      groupMemberLists[g].add('sp-mem-${_pad(i, width: 4)}');
    }
  }
  final groups = List.generate(
    50,
    (i) => _group(
      id: 'sp-grp-${_pad(i, width: 2)}',
      name: 'Power Group $i',
      desc: 'Group $i description.',
      memberIds: groupMemberLists[i],
      color: '#${(i * 13).toRadixString(16).padLeft(6, '0').substring(0, 6)}',
      emoji: i % 4 == 0 ? '★' : null,
    ),
  );

  // -- Channels (20) and categories (10) ------------------------------------
  final channels = List.generate(
    20,
    (i) => _channel(
      id: 'sp-chan-${_pad(i, width: 2)}',
      name: 'power-channel-$i',
      desc: 'Conversation $i.',
      // First 20 member ids in each channel — fine for shape.
      memberIds: List.generate(20, (k) => 'sp-mem-${_pad(k, width: 4)}'),
      createdAtMs: baseStart,
    ),
  );

  final channelCategories = List.generate(
    10,
    (i) => {
      '_id': 'sp-cat-${_pad(i, width: 2)}',
      'name': 'Category $i',
      // Each category claims 2 channels (deterministic, non-overlapping).
      'channels': <String>[
        'sp-chan-${_pad(i * 2, width: 2)}',
        'sp-chan-${_pad(i * 2 + 1, width: 2)}',
      ],
    },
  );

  // -- Front history (10,000 sessions) --------------------------------------
  final frontHistory = List.generate(
    10000,
    (i) => _frontHistory(
      id: 'sp-front-${_pad(i, width: 5)}',
      memberId: 'sp-mem-${_pad(i % 5000, width: 4)}',
      startMs: baseStart + i * sessionDur,
      endMs: baseStart + (i + 1) * sessionDur - 1,
    ),
  );

  // -- Messages (50,000 across 20 channels) ---------------------------------
  final messages = List.generate(
    50000,
    (i) => _message(
      id: 'sp-msg-${_pad(i, width: 5)}',
      channelId: 'sp-chan-${_pad(i % 20, width: 2)}',
      senderId: 'sp-mem-${_pad(i % 5000, width: 4)}',
      content: 'power message $i',
      timestampMs:
          baseStart + i * 1200, // 1.2s apart, spans ~21h * 60k ≈ months
    ),
  );

  // -- Polls (30 × 5 options × 20 votes = 3,000 votes) ----------------------
  final polls = List.generate(30, (p) {
    final names = ['Option A', 'Option B', 'Option C', 'Option D', 'Option E'];
    return _poll(
      id: 'sp-poll-${_pad(p, width: 2)}',
      question: 'Power poll $p?',
      options: names.map(_pollOption).toList(),
      // 5 options × 20 votes each = 100 votes per poll.
      votes: List.generate(100, (v) {
        return _pollVote(
          memberId: 'sp-mem-${_pad(v % 5000, width: 4)}',
          optionName: names[v % names.length],
          comment: v % 11 == 0 ? 'power-comment-$v' : null,
        );
      }),
      allowMultiple: p % 5 == 0,
    );
  });

  // -- Board posts (200 across members) -------------------------------------
  final boardMessages = List.generate(
    200,
    (i) => {
      '_id': 'sp-board-${_pad(i, width: 3)}',
      'writtenFor': 'sp-mem-${_pad(i % 5000, width: 4)}',
      'writtenBy': 'sp-mem-${_pad((i * 17 + 3) % 5000, width: 4)}',
      'message':
          'Board post $i body — a short note from one member to another.',
      'writtenAt': baseStart + i * 60 * 60 * 1000,
      'read': i.isEven,
    },
  );

  // -- Notes (100; mix member-bound + system-level) -------------------------
  final notes = List.generate(
    100,
    (i) => {
      '_id': 'sp-note-${_pad(i, width: 3)}',
      'title': 'Note $i title',
      'note': 'Body of note $i with a few sentences of content for realism.',
      if (i % 3 != 0)
        'color':
            '#${(i * 7).toRadixString(16).padLeft(6, '0').substring(0, 6)}',
      // ~70% member-bound, ~30% system-level (null/missing member field).
      if (i % 10 < 7) 'member': 'sp-mem-${_pad(i % 5000, width: 4)}',
      'date': baseStart + i * 60 * 60 * 1000,
    },
  );

  // -- Front-session comments (5,000 ≈ 1 per 2 sessions) --------------------
  // Bind to the first 5000 front sessions so every comment maps successfully
  // (see sp_mapper.dart:_mapFrontComments — drops unresolved documentId).
  final comments = List.generate(
    5000,
    (i) => {
      '_id': 'sp-comment-${_pad(i, width: 4)}',
      'documentId': 'sp-front-${_pad(i, width: 5)}',
      'collection': 'frontHistory',
      'text':
          'Comment $i on a front session — a real user would scribble here.',
      'time': baseStart + i * 5 * 60 * 1000,
    },
  );

  // -- Reminders: 8 automated + 12 repeated ---------------------------------
  // Use type 2 (any front change) for automated so we don't need to resolve a
  // target member id (mirrors _makeLarge convention).
  final automatedReminders = List.generate(
    8,
    (i) => {
      '_id': 'sp-auto-${_pad(i, width: 2)}',
      'name': 'Auto timer $i',
      'message': 'Switch reminder $i',
      'delayInHours': i + 1,
      'enabled': i != 3,
      'type': 2,
    },
  );
  final repeatedReminders = List.generate(
    12,
    (i) => {
      '_id': 'sp-rep-${_pad(i, width: 2)}',
      'name': 'Repeated timer $i',
      'message': 'Daily ping $i',
      'dayInterval': (i % 4) + 1,
      'time':
          '${(7 + i % 12).toString().padLeft(2, '0')}:${(i * 5 % 60).toString().padLeft(2, '0')}',
      'enabled': i != 5,
    },
  );

  return {
    'settings': {'systemName': 'Power-User System'},
    'users': [
      {
        'username': 'power-user',
        'color': '#7733cc',
        'desc': 'Five-plus years of daily SP usage. Smoke fixture.',
        'uid': 'uid-power',
        // System avatar: SP exports surface this via `users[0].avatarUrl`
        // (see sp_parser.dart — it does NOT read a top-level
        // `systemAvatarUrl` key). Picsum seed keeps the bytes deterministic.
        'avatarUrl':
            'https://picsum.photos/seed/sp-smoke-power-user-system/256',
      },
    ],
    'members': members,
    'frontStatuses': <Map<String, dynamic>>[],
    'frontHistory': frontHistory,
    'groups': groups,
    'channels': channels,
    'channelCategories': channelCategories,
    'chatMessages': messages,
    'polls': polls,
    'customFields': customFields,
    'boardMessages': boardMessages,
    'notes': notes,
    'comments': comments,
    'automatedReminders': automatedReminders,
    'repeatedReminders': repeatedReminders,
  };
}

/// `unpaired` — same shape as small. The difference (sync handle is null and
/// thus the FFI is never reached) is enforced at the test layer, not the
/// fixture.
Map<String, dynamic> _makeUnpaired() => _makeSmall();

/// `failing_tx` — small fixture; the test layer injects a mid-import DAO
/// error to force a transaction rollback.
Map<String, dynamic> _makeFailingTx() => _makeSmall();

String _pad(int i, {int width = 2}) => i.toString().padLeft(width, '0');
