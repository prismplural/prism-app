import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  group('MediaAttachmentsDao', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('watchAllChatMedia excludes non-image chat attachments', () async {
      await db.mediaAttachmentsDao.insertAttachment(
        MediaAttachmentsCompanion.insert(
          id: 'chat-image',
          messageId: const Value('message-1'),
          mediaId: const Value('media-image'),
          mediaType: const Value('image'),
          mimeType: const Value('image/png'),
        ),
      );
      await db.mediaAttachmentsDao.insertAttachment(
        MediaAttachmentsCompanion.insert(
          id: 'chat-gif',
          messageId: const Value('message-1'),
          mediaType: const Value('gif'),
          mimeType: const Value('video/mp4'),
          sourceUrl: const Value('https://media.klipy.com/test.mp4'),
          previewUrl: const Value('https://media.klipy.com/test.gif'),
        ),
      );
      await db.mediaAttachmentsDao.insertAttachment(
        MediaAttachmentsCompanion.insert(
          id: 'chat-voice',
          messageId: const Value('message-1'),
          mediaId: const Value('media-voice'),
          mediaType: const Value('voice'),
          mimeType: const Value('audio/ogg'),
        ),
      );

      final rows = await db.mediaAttachmentsDao.watchAllChatMedia().first;

      expect(rows.map((row) => row.id), ['chat-image']);
    });
  });
}
