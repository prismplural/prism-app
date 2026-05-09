import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';

void main() {
  late AppDatabase db;
  late ChatMessagesDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.chatMessagesDao;

    // Insert test messages — triggers will auto-index in FTS.
    await dao.insertMessage(ChatMessagesCompanion.insert(
      id: 'msg-1',
      content: 'Hello world this is a test message',
      timestamp: DateTime(2025, 1, 15, 10, 30),
      conversationId: 'conv-1',
      authorId: const Value('author-1'),
    ));
    await dao.insertMessage(ChatMessagesCompanion.insert(
      id: 'msg-2',
      content: 'Another message with special chars',
      timestamp: DateTime(2025, 1, 15, 11, 0),
      conversationId: 'conv-1',
      authorId: const Value('author-1'),
    ));
  });

  tearDown(() async {
    await db.close();
  });

  group('FTS5 searchMessages', () {
    test('finds messages by keyword', () async {
      final results = await dao.searchMessages('hello');
      expect(results, hasLength(1));
      expect(results.first.messageId, 'msg-1');
    });

    test('matches on prefix (fuzzy)', () async {
      final results = await dao.searchMessages('hel');
      expect(results, hasLength(1));
      expect(results.first.messageId, 'msg-1');
    });

    test('returns empty for no match', () async {
      final results = await dao.searchMessages('nonexistent');
      expect(results, isEmpty);
    });

    test('handles double quotes in query', () async {
      final results = await dao.searchMessages('hello "world"');
      expect(results, isA<List>());
    });

    test('handles FTS5 operators safely (OR)', () async {
      final results = await dao.searchMessages('hello OR goodbye');
      expect(results, isA<List>());
    });

    test('handles parentheses', () async {
      final results = await dao.searchMessages('(hello)');
      expect(results, isA<List>());
    });

    test('handles asterisk wildcard char', () async {
      final results = await dao.searchMessages('test*');
      expect(results, isA<List>());
    });

    test('handles NOT keyword', () async {
      final results = await dao.searchMessages('NOT this');
      expect(results, isA<List>());
    });

    test('handles column filter syntax', () async {
      final results = await dao.searchMessages('content:hello');
      expect(results, isA<List>());
    });

    test('returns correct timestamp from joined chat_messages', () async {
      final results = await dao.searchMessages('hello');
      expect(results, hasLength(1));
      final dt = results.first.timestamp;
      expect(dt.year, 2025);
      expect(dt.month, 1);
      expect(dt.day, 15);
    });

    test('does not index system messages', () async {
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-sys',
        content: 'System notification about joining',
        timestamp: DateTime(2025, 1, 15, 12, 0),
        conversationId: 'conv-1',
        isSystemMessage: const Value(true),
      ));
      final results = await dao.searchMessages('notification');
      expect(results, isEmpty);
    });

    test('does not index deleted messages', () async {
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-del',
        content: 'This was deleted',
        timestamp: DateTime(2025, 1, 15, 12, 0),
        conversationId: 'conv-1',
        isDeleted: const Value(true),
      ));
      final results = await dao.searchMessages('deleted');
      expect(results, isEmpty);
    });

    test('removes from index when soft-deleted', () async {
      var results = await dao.searchMessages('special');
      expect(results, hasLength(1));

      await dao.softDeleteMessage('msg-2');

      results = await dao.searchMessages('special');
      expect(results, isEmpty);
    });

    test('removes from index when message becomes a system message', () async {
      var results = await dao.searchMessages('special');
      expect(results, hasLength(1));

      await dao.updateMessage(const ChatMessagesCompanion(
        id: Value('msg-2'),
        isSystemMessage: Value(true),
      ));

      results = await dao.searchMessages('special');
      expect(results, isEmpty,
          reason: 'fts update trigger must fire on is_system_message flip');
    });

    test('updates fts conversation_id when message moves conversation',
        () async {
      await dao.updateMessage(const ChatMessagesCompanion(
        id: Value('msg-2'),
        conversationId: Value('conv-2'),
      ));

      final rows = await db.customSelect(
        'SELECT conversation_id FROM chat_messages_fts '
        "WHERE message_id = 'msg-2'",
      ).get();
      expect(rows, hasLength(1));
      expect(rows.first.read<String>('conversation_id'), 'conv-2',
          reason: 'fts update trigger must fire on conversation_id change');
    });

    test('drops single-char tokens to avoid range scans', () async {
      // Multi-token query made entirely of 1-char terms returns empty
      // rather than emitting three slow 1-char prefix scans.
      final results = await dao.searchMessages('a b c');
      expect(results, isEmpty);
    });

    test('keeps multi-char tokens even when one is single-char', () async {
      // 'h' is dropped, 'hello' survives → matches the seeded message.
      final results = await dao.searchMessages('h hello');
      expect(results, hasLength(1));
      expect(results.first.messageId, 'msg-1');
    });
  });

  // FTS5 `snippet()` picks a window that can start or end inside a
  // `||…||` spoiler span, stripping the `||` delimiters — so the downstream
  // `redactSpoilers` is a no-op and the raw spoiler text renders in the
  // results list. We mitigate that by building the snippet Dart-side from
  // the *redacted* full content. These tests lock that contract in.
  group('FTS5 snippet spoiler redaction', () {
    test(
        'match inside long spoiler never returns spoiler plaintext in snippet',
        () async {
      // A spoiler longer than the FTS snippet window (20 tokens) so the
      // old SQLite-snippet path would have returned a fragment with no
      // `||` delimiters around `lambda`.
      const spoilerBody =
          'alpha beta gamma delta epsilon zeta eta theta iota kappa '
          'lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega';
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-spoiler',
        content: 'context before ||$spoilerBody|| tail after',
        timestamp: DateTime(2025, 2, 1, 9, 0),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ));

      final results = await dao.searchMessages('lambda');
      expect(results, hasLength(1));
      final hit = results.first;
      expect(hit.messageId, 'msg-spoiler');
      // No word from inside the spoiler may appear in the snippet —
      // redaction converts the whole span to `▮` blocks before the
      // query-match window is computed.
      expect(hit.snippet.contains('lambda'), isFalse);
      expect(hit.snippet.contains('alpha'), isFalse);
      expect(hit.snippet.contains('omega'), isFalse);
      expect(hit.snippet.contains('▮'), isTrue);
    });

    test('match outside a spoiler still highlights with [brackets]', () async {
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-mixed',
        content: 'public intro ||hidden plot|| public outro',
        timestamp: DateTime(2025, 2, 1, 9, 30),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ));

      final results = await dao.searchMessages('intro');
      expect(results, hasLength(1));
      final hit = results.first;
      expect(hit.snippet.contains('[intro]'), isTrue);
      expect(hit.snippet.contains('plot'), isFalse);
      expect(hit.snippet.contains('hidden'), isFalse);
      expect(hit.snippet.contains('▮'), isTrue);
    });

    test('short non-spoiler message returns preview with highlighted match',
        () async {
      final results = await dao.searchMessages('hello');
      expect(results, hasLength(1));
      final hit = results.first;
      // Highlight preserves original casing; fixture uses `Hello`.
      expect(hit.snippet.contains('[Hello]'), isTrue);
      // No spoiler spans in these fixtures.
      expect(hit.snippet.contains('▮'), isFalse);
    });

    test('highlights a diacritic word with a diacritic query', () async {
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-dia',
        content: 'we went to the café yesterday',
        timestamp: DateTime(2025, 3, 1, 9, 30),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ));

      final results = await dao.searchMessages('café');
      expect(results, hasLength(1));
      expect(results.first.snippet.contains('[café]'), isTrue,
          reason: 'unicode-aware regex must match and bracket the full word');
    });

    test('highlights a Cyrillic word with a Cyrillic query', () async {
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-cyr',
        content: 'привет мир, это тест',
        timestamp: DateTime(2025, 3, 2, 9, 30),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ));

      final results = await dao.searchMessages('мир');
      expect(results, hasLength(1));
      expect(results.first.snippet.contains('[мир]'), isTrue,
          reason: '\\b must be Unicode-aware to bracket non-Latin scripts');
    });
  });

  // The snippet window slices ±40/80 chars around the first match. A 39-char
  // `@[uuid]` token can land partially across that boundary, leaving a stray
  // `[uuid` or `uuid]` fragment that no mention regex on the render side can
  // resolve. The window must snap outward to keep mention tokens whole.
  group('snippet window snaps mention tokens', () {
    // Asserts that no orphan UUID fragment leaked into the snippet. After
    // stripping every full `@[uuid]` token, any remaining run of 4+ hex
    // chars must be the tail/head of a bisected mention — fixtures contain
    // no legitimate hex sequences of that length.
    final mentionTokenPattern = RegExp(
      r'@\[[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\]',
    );
    final hexFragmentPattern = RegExp(r'[0-9a-f]{4,}');
    void expectNoBisectedToken(String snippet) {
      final stripped = snippet.replaceAll(mentionTokenPattern, '');
      expect(hexFragmentPattern.hasMatch(stripped), isFalse,
          reason:
              'snippet contains UUID fragment after stripping valid mentions: '
              '"$snippet" -> "$stripped"');
    }

    test('mention preceding the match is kept whole', () async {
      const aliceId = '11111111-2222-3333-4444-555555555555';
      // Place the mention at the start so a 40-char left window would land
      // mid-UUID without the snap. 30 chars of padding keeps `trampoline`
      // close enough that the window starts inside the token.
      final padding = 'x' * 30;
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-mention-before',
        content: '@[$aliceId] $padding trampoline tail',
        timestamp: DateTime(2026, 5, 1, 9, 0),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ));

      final results = await dao.searchMessages('trampoline');
      expect(results, hasLength(1));
      expectNoBisectedToken(results.first.snippet);
    });

    test('mention following the match is kept whole', () async {
      const bobId = '99999999-8888-7777-6666-aaaaaaaaaaaa';
      // Right window is +80 chars from the match end; pad so the mention's
      // closing `]` sits just past the boundary.
      final padding = 'word ' * 14;
      await dao.insertMessage(ChatMessagesCompanion.insert(
        id: 'msg-mention-after',
        content: 'pineapple $padding @[$bobId] tail',
        timestamp: DateTime(2026, 5, 1, 9, 30),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ));

      final results = await dao.searchMessages('pineapple');
      expect(results, hasLength(1));
      expectNoBisectedToken(results.first.snippet);
    });
  });
}
