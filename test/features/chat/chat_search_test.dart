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
      expect(results.first.read<String>('message_id'), 'msg-1');
    });

    test('matches on prefix (fuzzy)', () async {
      final results = await dao.searchMessages('hel');
      expect(results, hasLength(1));
      expect(results.first.read<String>('message_id'), 'msg-1');
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
      final rawTimestamp = results.first.read<int>('timestamp');
      final dt = DateTime.fromMillisecondsSinceEpoch(rawTimestamp * 1000);
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
}
