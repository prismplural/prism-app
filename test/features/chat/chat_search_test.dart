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
  });
}
