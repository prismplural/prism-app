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
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'messages sent within the same wall-clock second preserve send order',
    () async {
      // 250 ms apart in the same second — pre-v27 both rounded to identical
      // second ints with undefined sort order.
      final t1 = DateTime.utc(2026, 5, 23, 11, 30, 7, 100);
      final t2 = DateTime.utc(2026, 5, 23, 11, 30, 7, 350);

      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-first',
          content: 'first',
          timestamp: t1,
          conversationId: 'conv-1',
        ),
      );
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-second',
          content: 'second',
          timestamp: t2,
          conversationId: 'conv-1',
        ),
      );

      // DESC by timestamp: newest (second) should come first.
      final desc = await dao.getMessagesForConversation('conv-1');
      expect(desc.map((m) => m.id).toList(), ['msg-second', 'msg-first']);

      // Round-trip preserves the original ms-precision wall-clock value.
      final byId = {for (final m in desc) m.id: m};
      expect(byId['msg-first']!.timestamp.toUtc(), t1);
      expect(byId['msg-second']!.timestamp.toUtc(), t2);
    },
  );

  test(
    'truly-tied timestamps fall back to a stable id-based ordering',
    () async {
      // True ms tie — id-ASC tiebreaker makes the order stable.
      final t = DateTime.utc(2026, 5, 23, 11, 30, 7, 500);

      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-zz',
          content: 'zz',
          timestamp: t,
          conversationId: 'conv-1',
        ),
      );
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-aa',
          content: 'aa',
          timestamp: t,
          conversationId: 'conv-1',
        ),
      );

      final desc = await dao.getMessagesForConversation('conv-1');
      // DESC by timestamp (tied), then ASC by id: msg-aa before msg-zz.
      expect(desc.map((m) => m.id).toList(), ['msg-aa', 'msg-zz']);

      // And the watch stream returns the same order.
      final fromWatch = await dao.watchMessagesForConversation('conv-1').first;
      expect(fromWatch.map((m) => m.id).toList(), ['msg-aa', 'msg-zz']);
    },
  );

  test(
    'round-trip preserves local-zone wall-clock components',
    () async {
      // Chat UI calls .hour/.day on message.timestamp without .toLocal();
      // the converter must return local-zone to match Drift's old `dateTime()`,
      // or every message shifts by the user's UTC offset.
      final wall = DateTime(2026, 5, 23, 11, 30, 7, 100);
      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-local',
          content: 'local',
          timestamp: wall,
          conversationId: 'conv-local',
        ),
      );

      final read = await dao.getMessagesForConversation('conv-local');
      expect(read, hasLength(1));
      final got = read.single.timestamp;
      expect(got.isUtc, isFalse, reason: 'must match Drift dateTime() zone');
      expect(got.year, wall.year);
      expect(got.month, wall.month);
      expect(got.day, wall.day);
      expect(got.hour, wall.hour);
      expect(got.minute, wall.minute);
      expect(got.second, wall.second);
      expect(got.millisecond, wall.millisecond);
    },
  );

  test(
    'watchUnreadCount uses ms cutoff so sub-second messages are not dropped',
    () async {
      // Cutoff is mid-second; a 100ms-later message must count as unread.
      // Pre-v27 both truncated to the same second and `WHERE timestamp > ?`
      // excluded it.
      final since = DateTime.utc(2026, 5, 23, 11, 30, 7, 200);
      final messageTs = DateTime.utc(2026, 5, 23, 11, 30, 7, 300);

      await dao.insertMessage(
        ChatMessagesCompanion.insert(
          id: 'msg-unread',
          content: 'unread',
          timestamp: messageTs,
          conversationId: 'conv-1',
        ),
      );

      final count = await dao.watchUnreadCount('conv-1', since).first;
      expect(count, 1);
    },
  );
}
