import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

const _fixturePath = 'test/fixtures/sp_reply_thread_export.json';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'SP fixture import preserves reply quote snapshots through database write',
    () async {
      final importer = SpImporter();
      final data = await importer.parseFile(_fixturePath);

      expect(data.messages, hasLength(3));
      expect(data.messages.where((m) => m.replyTo != null), hasLength(2));

      final result = await importer.executeImport(
        db: db,
        data: data,
        memberRepo: DriftMemberRepository(db.membersDao, null),
        sessionRepo: DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        ),
        conversationRepo: DriftConversationRepository(
          db.conversationsDao,
          null,
        ),
        messageRepo: DriftChatMessageRepository(db.chatMessagesDao, null),
        pollRepo: DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        ),
        downloadAvatars: false,
      );

      expect(result.messagesImported, 3);

      final messages = await db.chatMessagesDao.getAllMessages();
      final root = messages.singleWhere(
        (m) => m.content == 'Root message from SP fixture',
      );
      final reply = messages.singleWhere(
        (m) => m.content == 'Reply to root from SP fixture',
      );
      final chainReply = messages.singleWhere(
        (m) => m.content == 'Reply to the reply from SP fixture',
      );

      expect(root.replyToId, isNull);

      expect(reply.replyToId, root.id);
      expect(reply.replyToAuthorId, root.authorId);
      expect(reply.replyToContent, root.content);

      expect(chainReply.replyToId, reply.id);
      expect(chainReply.replyToAuthorId, reply.authorId);
      expect(chainReply.replyToContent, reply.content);
      expect(chainReply.editedAt, isNotNull);
    },
  );
}
