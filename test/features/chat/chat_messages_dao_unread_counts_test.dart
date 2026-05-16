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

    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-1',
        content: 'Unread message',
        timestamp: DateTime(2025, 1, 15, 10, 30),
        conversationId: 'conv-1',
        authorId: const Value('author-1'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'watchAllUnreadCounts skips zero-count conversations without null rows',
    () async {
      final counts = await dao.watchAllUnreadCounts({
        'conv-1': DateTime(2025, 1, 15, 10, 0),
        'conv-2': DateTime(2025, 1, 15, 10, 0),
      }).first;

      expect(counts, {'conv-1': 1});
    },
  );

  test('watchAllUnreadCounts batches large conversation maps', () async {
    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-2',
        content: 'Unread message 2',
        timestamp: DateTime(2025, 1, 15, 10, 45),
        conversationId: 'conv-401',
        authorId: const Value('author-2'),
      ),
    );

    final conversationSince = <String, DateTime>{
      for (var i = 1; i <= 401; i++) 'conv-$i': DateTime(2025, 1, 15, 10, 0),
    };

    final counts = await dao.watchAllUnreadCounts(conversationSince).first;

    expect(counts, {'conv-1': 1, 'conv-401': 1});
  });

  test(
    'watchConversationsWithMentions batches large conversation maps',
    () async {
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-3',
          content: 'Hello @[member-1]',
          timestamp: DateTime(2025, 1, 15, 10, 50),
          conversationId: 'conv-401',
          authorId: const Value('author-3'),
        ),
      );

      final conversationSince = <String, DateTime>{
        for (var i = 1; i <= 401; i++) 'conv-$i': DateTime(2025, 1, 15, 10, 0),
      };

      final mentionConversations = await dao
          .watchConversationsWithMentions(conversationSince, 'member-1')
          .first;

      expect(mentionConversations, {'conv-401'});
    },
  );

  test('watchUnreadMentionCount counts broadcast aliases', () async {
    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-2',
        content: 'Heads up @everyone',
        timestamp: DateTime(2025, 1, 15, 10, 45),
        conversationId: 'conv-1',
        authorId: const Value('author-2'),
      ),
    );
    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-3',
        content: 'Please read @all',
        timestamp: DateTime(2025, 1, 15, 10, 50),
        conversationId: 'conv-1',
        authorId: const Value('author-3'),
      ),
    );

    final count = await dao
        .watchUnreadMentionCount(
          'conv-1',
          DateTime(2025, 1, 15, 10, 0),
          'member-1',
        )
        .first;

    expect(count, 2);
  });

  test(
    'watchUnreadMentionCount counts direct and broadcast once per message',
    () async {
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-2',
          content: 'Hello @[member-1] and @everyone',
          timestamp: DateTime(2025, 1, 15, 10, 45),
          conversationId: 'conv-1',
          authorId: const Value('author-2'),
        ),
      );

      final count = await dao
          .watchUnreadMentionCount(
            'conv-1',
            DateTime(2025, 1, 15, 10, 0),
            'member-1',
          )
          .first;

      expect(count, 1);
    },
  );

  test('watchUnreadMentionCount ignores broadcast false positives', () async {
    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-2',
        content: 'not@all @alliance @everyoneish',
        timestamp: DateTime(2025, 1, 15, 10, 45),
        conversationId: 'conv-1',
        authorId: const Value('author-2'),
      ),
    );

    final count = await dao
        .watchUnreadMentionCount(
          'conv-1',
          DateTime(2025, 1, 15, 10, 0),
          'member-1',
        )
        .first;

    expect(count, 0);
  });

  test(
    'watchUnreadMentionCount keeps direct mention matching case-sensitive',
    () async {
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-2',
          content: 'Hello @[ABCDEF12-3456-7890-ABCD-EF1234567890]',
          timestamp: DateTime(2025, 1, 15, 10, 45),
          conversationId: 'conv-1',
          authorId: const Value('author-2'),
        ),
      );

      final count = await dao
          .watchUnreadMentionCount(
            'conv-1',
            DateTime(2025, 1, 15, 10, 0),
            'abcdef12-3456-7890-abcd-ef1234567890',
          )
          .first;

      expect(count, 0);
    },
  );

  test('watchConversationsWithMentions includes broadcast aliases', () async {
    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-2',
        content: 'Heads up @all',
        timestamp: DateTime(2025, 1, 15, 10, 45),
        conversationId: 'conv-2',
        authorId: const Value('author-2'),
      ),
    );
    await dao.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'msg-3',
        content: 'not@all @alliance @everyoneish',
        timestamp: DateTime(2025, 1, 15, 10, 50),
        conversationId: 'conv-3',
        authorId: const Value('author-3'),
      ),
    );

    final mentionConversations = await dao.watchConversationsWithMentions({
      'conv-1': DateTime(2025, 1, 15, 10, 0),
      'conv-2': DateTime(2025, 1, 15, 10, 0),
      'conv-3': DateTime(2025, 1, 15, 10, 0),
    }, 'member-1').first;

    expect(mentionConversations, {'conv-2'});
  });

  test(
    'watchConversationsWithMentions keeps direct mention matching case-sensitive',
    () async {
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-2',
          content: 'Hello @[ABCDEF12-3456-7890-ABCD-EF1234567890]',
          timestamp: DateTime(2025, 1, 15, 10, 45),
          conversationId: 'conv-2',
          authorId: const Value('author-2'),
        ),
      );

      final mentionConversations = await dao.watchConversationsWithMentions({
        'conv-1': DateTime(2025, 1, 15, 10, 0),
        'conv-2': DateTime(2025, 1, 15, 10, 0),
      }, 'abcdef12-3456-7890-abcd-ef1234567890').first;

      expect(mentionConversations, isEmpty);
    },
  );
}
