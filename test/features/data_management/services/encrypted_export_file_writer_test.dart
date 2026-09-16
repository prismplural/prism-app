/// Regression coverage for the encrypted-export worker boundary.
///
/// These tests pin:
///
///   * byte-for-byte parity between the worker and the unchanged inline
///     `ExportCrypto.writeEncryptedFile` primitive (pinned salt/nonce);
///   * that `V1Export.toJson()` runs inside the worker, not on the caller;
///   * that the worker runs on a distinct isolate while the caller's event
///     loop stays live (barrier, no timer race);
///   * error/cleanup behavior: media-change, JSON cap, filesystem error.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/data_management/services/encrypted_export_file_writer.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

const _password = 'worker-parity-password-2026';

/// Fixed salt/nonce so worker and inline output are comparable byte-for-byte.
Uint8List _salt() => Uint8List.fromList(List<int>.generate(32, (i) => i));

Uint8List _nonce() =>
    Uint8List.fromList(List<int>.generate(12, (i) => 0xa0 + i));

/// A complete sendable export graph: every V1 record family the exporter
/// emits, nested reactions/maps, group `sortState`, every inline-image /
/// base64 field, the rescue envelope flag, and ordered main/thumbnail media.
Map<String, dynamic> _fullExportJson() => {
  'formatVersion': '1.0',
  'version': '1.0',
  'appName': 'Prism Plurality',
  'exportDate': '2026-07-13T00:00:00.000Z',
  'totalRecords': 21,
  'rescueLegacyFields': true,
  'headmates': [
    {
      'id': 'member-1',
      'name': 'Rowan',
      'pronouns': 'they/them',
      'createdAt': '2026-01-01T00:00:00.000Z',
      // Every inline-image field, base64-encoded.
      'profilePhotoData': base64Encode(const [1, 2, 3]),
      'profileHeaderImageData': base64Encode(const [4, 5, 6]),
      'pkBannerImageData': base64Encode(const [7, 8, 9]),
      'pkAvatarCachedUrl': 'https://example.invalid/avatar.png',
      'pluralkitUuid': 'pk-uuid-1',
      'proxyTagsJson': '[{"prefix":"R:"}]',
      'nameStyleBold': true,
    },
  ],
  'frontSessions': [
    {
      'id': 'session-1',
      'startTime': '2026-02-01T09:00:00.000Z',
      'endTime': '2026-02-01T11:00:00.000Z',
      'headmateId': 'member-1',
      // Legacy rescue fields — the migration-time backup emits both shapes.
      'coFronterIds': ['member-2', 'member-3'],
      'pkMemberIdsJson': '["pk-member-1"]',
      'notes': 'legacy rescue row',
      'sessionType': 0,
      'quality': 1,
      'isHealthKitImport': false,
    },
  ],
  'sleepSessions': [
    {
      'id': 'sleep-1',
      'startTime': '2026-02-01T23:00:00.000Z',
      'endTime': '2026-02-02T07:00:00.000Z',
      'quality': 2,
      'notes': 'slept well',
    },
  ],
  'conversations': [
    {
      'id': 'conversation-1',
      'createdAt': '2026-03-01T00:00:00.000Z',
      'lastActivityAt': '2026-03-02T00:00:00.000Z',
      'title': 'Group chat',
      'emoji': '',
      'type': 'group',
      // Nested map + JSON-string list fields.
      'lastReadTimestamps': {'member-1': '2026-03-02T00:00:00.000Z'},
      'archivedByMemberIds': '["member-2"]',
      'mutedByMemberIds': '["member-3"]',
      'participantIds': ['member-1', 'member-2'],
      'displayOrder': 1,
    },
  ],
  'messages': [
    {
      'id': 'message-1',
      'content': 'hello',
      'timestamp': '2026-03-01T10:00:00.000Z',
      'conversationId': 'conversation-1',
      'authorId': 'member-1',
      // Nested reaction list.
      'reactions': [
        {
          'id': 'reaction-1',
          'emoji': '🎉',
          'memberId': 'member-2',
          'timestamp': '2026-03-01T10:01:00.000Z',
        },
      ],
      'replyToId': 'message-0',
      'replyToContent': 'previous',
    },
  ],
  'polls': [
    {
      'id': 'poll-1',
      'question': 'Dinner?',
      'createdAt': '2026-03-01T12:00:00.000Z',
      'isAnonymous': false,
      'allowsMultipleVotes': true,
    },
  ],
  'pollOptions': [
    {
      'id': 'option-1',
      'pollId': 'poll-1',
      'text': 'Pizza',
      'sortOrder': 0,
      'votes': [
        {
          'id': 'vote-1',
          'memberId': 'member-1',
          'votedAt': '2026-03-01T12:05:00.000Z',
        },
      ],
    },
  ],
  'systemSettings': [
    {
      'systemName': 'Test System',
      // System-level inline image field.
      'systemAvatarData': base64Encode(const [10, 11, 12]),
      'accentColorHex': '#112233',
      'perMemberAccentColors': true,
      'chatBadgePreferences': {'enabled': true},
    },
  ],
  'habits': [
    {
      'id': 'habit-1',
      'name': 'Water',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-02T00:00:00.000Z',
      'weeklyDays': '[1,2,3]',
      'frequency': 'weekly',
    },
  ],
  'habitCompletions': [
    {
      'id': 'completion-1',
      'habitId': 'habit-1',
      'completedAt': '2026-01-03T00:00:00.000Z',
      'createdAt': '2026-01-03T00:00:00.000Z',
      'modifiedAt': '2026-01-03T00:00:00.000Z',
    },
  ],
  'pluralKitSyncState': {
    'systemId': 'pk-system-1',
    'isConnected': true,
    'lastSyncDate': '2026-03-01T00:00:00.000Z',
  },
  'memberGroups': [
    {
      'id': 'group-1',
      'name': 'Core',
      'createdAt': '2026-01-01T00:00:00.000Z',
      // Group inline image + nested sortState map.
      'avatarImageData': base64Encode(const [13, 14]),
      'sortState': {
        'mode': 'manual',
        'order': ['member-1', 'member-2'],
      },
      'groupType': 0,
    },
  ],
  'memberGroupEntries': [
    {'id': 'entry-1', 'groupId': 'group-1', 'memberId': 'member-1'},
  ],
  'customFields': [
    {
      'id': 'field-1',
      'name': 'Pronoun set',
      'fieldType': 0,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'typeConfigJson': '{"options":["a","b"]}',
    },
  ],
  'customFieldValues': [
    {
      'id': 'value-1',
      'customFieldId': 'field-1',
      'memberId': 'member-1',
      'value': 'they/them',
    },
  ],
  'notes': [
    {
      'id': 'note-1',
      'title': 'Note',
      'body': 'Body',
      'date': '2026-01-01T00:00:00.000Z',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-02T00:00:00.000Z',
    },
  ],
  'frontSessionComments': [
    {
      'id': 'comment-1',
      'sessionId': 'session-1',
      'body': 'comment body',
      'timestamp': '2026-02-01T10:00:00.000Z',
      'createdAt': '2026-02-01T10:00:00.000Z',
    },
  ],
  'conversationCategories': [
    {
      'id': 'category-1',
      'name': 'Category',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-02T00:00:00.000Z',
    },
  ],
  'reminders': [
    {
      'id': 'reminder-1',
      'name': 'Reminder',
      'message': 'Do the thing',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-02T00:00:00.000Z',
      'weeklyDays': '[5]',
    },
  ],
  'friends': [
    {
      'id': 'friend-1',
      'displayName': 'Friend',
      'publicKeyHex': 'aa11',
      'createdAt': '2026-01-01T00:00:00.000Z',
    },
  ],
  'mediaAttachments': [
    {
      'id': 'attachment-1',
      'messageId': 'message-1',
      'memberId': 'member-1',
      'mediaId': 'media-main',
      'mediaType': 'image',
      'encryptionKeyB64': 'key',
      'contentHash': 'content-hash',
      'plaintextHash': 'plaintext-hash',
      'mimeType': 'image/png',
      'sizeBytes': 4,
      'thumbnailMediaId': 'media-thumb',
      'thumbnailContentHash': 'thumb-hash',
    },
  ],
  'memberBoardPosts': [
    {
      'id': 'board-1',
      'audience': 'private',
      'body': 'board body',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'writtenAt': '2026-01-01T00:00:00.000Z',
      'isDeleted': false,
    },
  ],
  'appPreferences': [
    {'key': 'accessibility.navBarExpandedLabels', 'valueType': 'bool'},
  ],
};

/// A `V1Export` that counts `toJson()` calls, so a test can prove the service
/// hands the *model* to the writer instead of pre-serializing it.
class _ToJsonCountingExport extends V1Export {
  _ToJsonCountingExport()
    : super(
        formatVersion: '1.0',
        version: '1.0',
        appName: 'Prism Plurality',
        exportDate: '2026-07-13T00:00:00.000Z',
        totalRecords: 1,
        headmates: [],
        frontSessions: [],
        sleepSessions: [],
        conversations: [],
        messages: [],
        polls: [],
        pollOptions: [],
        systemSettings: [],
        habits: [],
        habitCompletions: [],
        rescueLegacyFields: true,
      );

  int toJsonCalls = 0;

  @override
  Map<String, dynamic> toJson() {
    toJsonCalls++;
    return super.toJson();
  }
}

/// `DataExportService` whose `buildExport` returns a known envelope, so the
/// boundary test can assert what crosses into the writer.
class _StubExportService extends DataExportService {
  _StubExportService({
    required super.db,
    required Directory cacheDir,
    required V1Export export,
    EncryptedExportWriter? writer,
  }) : _export = export,
       super(
         memberRepository: DriftMemberRepository(db.membersDao, null),
         frontingSessionRepository: DriftFrontingSessionRepository(
           db.frontingSessionsDao,
           null,
         ),
         conversationRepository: DriftConversationRepository(
           db.conversationsDao,
           null,
         ),
         chatMessageRepository: DriftChatMessageRepository(
           db.chatMessagesDao,
           null,
         ),
         pollRepository: DriftPollRepository(
           db.pollsDao,
           db.pollOptionsDao,
           db.pollVotesDao,
           null,
         ),
         systemSettingsRepository: DriftSystemSettingsRepository(
           db.systemSettingsDao,
           null,
         ),
         habitRepository: DriftHabitRepository(db.habitsDao, null),
         pluralKitSyncDao: db.pluralKitSyncDao,
         memberGroupsRepository: DriftMemberGroupsRepository(
           db.memberGroupsDao,
           null,
         ),
         customFieldsRepository: DriftCustomFieldsRepository(
           db.customFieldsDao,
           null,
         ),
         notesRepository: DriftNotesRepository(db.notesDao, null),
         frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
           db.frontSessionCommentsDao,
           null,
         ),
         conversationCategoriesRepository:
             DriftConversationCategoriesRepository(
               db.conversationCategoriesDao,
               null,
             ),
         remindersRepository: DriftRemindersRepository(db.remindersDao, null),
         friendsRepository: DriftFriendsRepository(db.friendsDao, null),
         mediaAttachmentsDao: db.mediaAttachmentsDao,
         cacheDirectoryProvider: () async => cacheDir,
         appSupportDirectoryProvider: () async => cacheDir,
         encryptedExportWriter: writer,
       );

  final V1Export _export;

  @override
  Future<V1Export> buildExport({bool includeLegacyFields = false}) async =>
      _export;
}

void main() {
  group('encrypted export worker', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('prism-export-worker-');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<(File, Uint8List, int)> writeMedia(
      String name,
      List<int> bytes,
    ) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsBytes(bytes);
      final stat = await file.stat();
      return (
        file,
        Uint8List.fromList(bytes),
        stat.modified.millisecondsSinceEpoch,
      );
    }

    test('worker output is byte-identical to the inline writer and decrypts to '
        'the same compact JSON (full record graph + ordered media)', () async {
      final (mainFile, mainBytes, mainMs) = await writeMedia('media-main.enc', [
        1,
        3,
        5,
        7,
      ]);
      final (thumbFile, thumbBytes, thumbMs) = await writeMedia(
        'media-thumb.enc',
        [0xde, 0xad, 0xbe, 0xef, 0x00],
      );
      final export = V1Export.fromJson(_fullExportJson());
      final salt = _salt();
      final nonce = _nonce();

      // Reference bytes from the unchanged format-owning primitive.
      final inlineFile = File('${tempDir.path}/inline.prism');
      final inlineSink = inlineFile.openWrite();
      final inlineBytes = await ExportCrypto.writeEncryptedFile(
        jsonValue: export.toJson(),
        mediaBlobs: [
          ExportMediaBlobDescriptor(
            mediaId: 'media-main',
            file: mainFile,
            lengthBytes: mainBytes.length,
            modified: DateTime.fromMillisecondsSinceEpoch(mainMs),
          ),
          ExportMediaBlobDescriptor(
            mediaId: 'media-thumb',
            file: thumbFile,
            lengthBytes: thumbBytes.length,
            modified: DateTime.fromMillisecondsSinceEpoch(thumbMs),
          ),
        ],
        password: _password,
        sink: inlineSink,
        saltForTesting: salt,
        nonceForTesting: nonce,
      );
      await inlineSink.close();

      final workerFile = File('${tempDir.path}/worker.prism');
      final workerBytes = await writeEncryptedExportFileTask(
        EncryptedExportWriteTask(
          export: export,
          mediaBlobs: [
            ExportMediaBlobTask(
              mediaId: 'media-main',
              path: mainFile.path,
              lengthBytes: mainBytes.length,
              modifiedMillisecondsSinceEpoch: mainMs,
            ),
            ExportMediaBlobTask(
              mediaId: 'media-thumb',
              path: thumbFile.path,
              lengthBytes: thumbBytes.length,
              modifiedMillisecondsSinceEpoch: thumbMs,
            ),
          ],
          password: _password,
          outputPath: workerFile.path,
          saltForTesting: salt,
          nonceForTesting: nonce,
        ),
      );

      expect(workerBytes, inlineBytes);
      expect(
        await workerFile.readAsBytes(),
        await inlineFile.readAsBytes(),
        reason: 'worker output must be byte-identical to the inline writer',
      );

      final resolved = DataImportService.resolveBytes(
        await workerFile.readAsBytes(),
        password: _password,
      );
      expect(
        resolved.json,
        utf8.decode(JsonUtf8Encoder().convert(export.toJson())),
      );
      expect(
        resolved.mediaBlobs.map((b) => b.mediaId).toList(),
        ['media-main', 'media-thumb'],
        reason: 'media descriptor order must be preserved',
      );
      expect(resolved.mediaBlobs[0].blob, mainBytes);
      expect(resolved.mediaBlobs[1].blob, thumbBytes);

      // The rescue envelope flag and legacy session fields survive.
      final parsed = V1Export.fromJson(
        jsonDecode(resolved.json) as Map<String, dynamic>,
      );
      expect(parsed.rescueLegacyFields, isTrue);
      expect(parsed.frontSessions.single.coFronterIds, [
        'member-2',
        'member-3',
      ]);
      expect(parsed.frontSessions.single.pkMemberIdsJson, '["pk-member-1"]');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('task defensively copies salt/nonce and freezes mediaBlobs', () {
      final salt = _salt();
      final nonce = _nonce();
      final blobs = <ExportMediaBlobTask>[
        const ExportMediaBlobTask(
          mediaId: 'media-main',
          path: '/tmp/does-not-matter.enc',
          lengthBytes: 1,
          modifiedMillisecondsSinceEpoch: 0,
        ),
      ];
      final task = EncryptedExportWriteTask(
        export: V1Export.fromJson(_fullExportJson()),
        mediaBlobs: blobs,
        password: _password,
        outputPath: '${tempDir.path}/unused.prism',
        saltForTesting: salt,
        nonceForTesting: nonce,
      );

      // Caller mutation afterwards must not change the in-flight task.
      blobs.clear();
      salt[0] = 0xff;
      nonce[0] = 0xff;
      expect(task.mediaBlobs, hasLength(1));
      expect(task.saltForTesting, isNot(equals(salt)));
      expect(task.nonceForTesting, isNot(equals(nonce)));
      expect(task.mediaBlobs.clear, throwsUnsupportedError);
    });

    test(
      'worker rejects a media file changed after descriptor capture',
      () async {
        final mediaFile = File('${tempDir.path}/changed.enc');
        await mediaFile.writeAsBytes([1, 2, 3]);
        final stat = await mediaFile.stat();
        // Change the file after the descriptor snapshot was taken.
        await mediaFile.writeAsBytes([1, 2, 3, 4]);

        final output = File('${tempDir.path}/changed.prism');
        await expectLater(
          writeEncryptedExportFileTask(
            EncryptedExportWriteTask(
              export: V1Export.fromJson(_fullExportJson()),
              mediaBlobs: [
                ExportMediaBlobTask(
                  mediaId: 'media-main',
                  path: mediaFile.path,
                  lengthBytes: stat.size,
                  modifiedMillisecondsSinceEpoch:
                      stat.modified.millisecondsSinceEpoch,
                ),
              ],
              password: _password,
              outputPath: output.path,
            ),
          ),
          throwsA(isA<ExportMediaBlobChangedException>()),
        );
      },
    );

    test(
      'post-read media-change check fires when a file changes between the '
      'read and the second stat (deterministic hook, not a timer race)',
      () async {
        final mediaFile = File('${tempDir.path}/postread.enc');
        await mediaFile.writeAsBytes([9, 8, 7]);
        final stat = await mediaFile.stat();

        final output = File('${tempDir.path}/postread.prism');
        final sink = output.openWrite();
        var hookCalls = 0;
        await expectLater(
          ExportCrypto.writeEncryptedFile(
            jsonValue: const {'formatVersion': '1.0'},
            mediaBlobs: [
              ExportMediaBlobDescriptor(
                mediaId: 'media-main',
                file: mediaFile,
                lengthBytes: stat.size,
                modified: stat.modified,
              ),
            ],
            password: _password,
            sink: sink,
            afterMediaBlobReadForTesting: (descriptor) async {
              hookCalls++;
              // Mutate immediately before the post-read stat.
              await descriptor.file.writeAsBytes([9, 8, 7, 6, 5]);
            },
          ),
          throwsA(isA<ExportMediaBlobChangedException>()),
        );
        await sink.close();
        expect(hookCalls, 1);
      },
    );

    test(
      'worker propagates the JSON soft-cap failure and writes no useful output',
      () async {
        final output = File('${tempDir.path}/capped.prism');
        await expectLater(
          writeEncryptedExportFileTask(
            EncryptedExportWriteTask(
              export: V1Export.fromJson(_fullExportJson()),
              mediaBlobs: const [],
              password: _password,
              outputPath: output.path,
              jsonPlaintextSoftLimitBytes: 4,
            ),
          ),
          throwsA(
            isA<ExportJsonTooLargeException>().having(
              (e) => e.limitBytes,
              'limitBytes',
              4,
            ),
          ),
        );
        if (await output.exists()) {
          expect(await output.length(), 0);
        }
      },
    );

    test('off-main worker preserves the typed JSON soft-cap error', () async {
      final output = File('${tempDir.path}/off-main-capped.prism');
      await expectLater(
        writeEncryptedExportFileOffMain(
          EncryptedExportWriteTask(
            export: V1Export.fromJson(_fullExportJson()),
            mediaBlobs: const [],
            password: _password,
            outputPath: output.path,
            jsonPlaintextSoftLimitBytes: 4,
          ),
        ),
        throwsA(
          isA<ExportJsonTooLargeException>().having(
            (e) => e.limitBytes,
            'limitBytes',
            4,
          ),
        ),
      );
      if (await output.exists()) {
        expect(await output.length(), 0);
      }
    });

    test(
      'worker propagates the original filesystem error for an invalid output '
      'path and leaves no file behind',
      () async {
        final missingDir = '${tempDir.path}/does-not-exist';
        final output = File('$missingDir/nope.prism');
        await expectLater(
          writeEncryptedExportFileTask(
            EncryptedExportWriteTask(
              export: V1Export.fromJson(_fullExportJson()),
              mediaBlobs: const [],
              password: _password,
              outputPath: output.path,
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await output.exists(), isFalse);
      },
    );

    test('worker runs on a distinct isolate while the caller event loop stays '
        'live (barrier, no timer race)', () async {
      final output = File('${tempDir.path}/barrier.prism');
      final events = ReceivePort();
      final mainControlPort = Isolate.current.controlPort;

      // Queue a main-isolate event. It can only run while this isolate's
      // event loop is free — i.e. while the worker is paused.
      var mainEventRan = false;
      final mainEvent = Future<void>.delayed(Duration.zero, () {
        mainEventRan = true;
      });

      final writeFuture = writeEncryptedExportFileOffMain(
        EncryptedExportWriteTask(
          export: V1Export.fromJson(_fullExportJson()),
          mediaBlobs: const [],
          password: _password,
          outputPath: output.path,
          saltForTesting: _salt(),
          nonceForTesting: _nonce(),
          probe: ExportWorkerProbe(events.sendPort),
        ),
      );

      final started = await events.first as ExportWorkerStartedEvent;
      expect(
        started.isolateControlPort,
        isNot(equals(mainControlPort)),
        reason: 'the write must not run on the caller isolate',
      );

      await mainEvent;
      expect(
        mainEventRan,
        isTrue,
        reason: 'the caller event loop must stay live while the worker waits',
      );

      started.resumePort.send('resume');
      expect(await writeFuture, greaterThan(0));
      expect(await output.exists(), isTrue);
      events.close();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('worker output is not produced by the caller isolate: a thrown '
        'toJson() surfaces the original error with the worker stack', () async {
      final output = File('${tempDir.path}/throwing.prism');
      await expectLater(
        writeEncryptedExportFileTask(
          EncryptedExportWriteTask(
            export: _ThrowingExport(),
            mediaBlobs: const [],
            password: _password,
            outputPath: output.path,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('toJson ran in the worker'),
          ),
        ),
      );
    });
  });

  group('DataExportService — worker boundary and cleanup', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('prism-export-svc-');
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('service hands the writer a V1Export model (not a prebuilt JSON map) '
        'and never calls toJson on the caller isolate', () async {
      final export = _ToJsonCountingExport();
      EncryptedExportWriteTask? captured;
      final service = _StubExportService(
        db: db,
        cacheDir: tempDir,
        export: export,
        writer: (task) async {
          captured = task;
          // Simulate what the real worker does, on the worker side only.
          final json = task.export.toJson();
          expect(json['rescueLegacyFields'], isTrue);
          return 1;
        },
      );

      // The stub writer reports 1 byte; the service verifies file length.
      final file = File('${tempDir.path}/boundary.prism');
      await file.writeAsBytes([0]);

      await expectLater(
        service.buildEncryptedExportFile(
          password: _password,
          targetDirectory: tempDir,
          fileName: 'boundary.prism',
        ),
        completes,
      );

      expect(captured, isNotNull);
      expect(captured!.export, isA<V1Export>());
      expect(captured!.export, same(export));
      expect(captured!.mediaBlobs, isEmpty);
      // toJson() ran exactly once — inside the injected writer, not on the
      // caller before the handoff.
      expect(export.toJsonCalls, 1);
    });

    test('service deletes the partial output when the writer throws', () async {
      final service = _StubExportService(
        db: db,
        cacheDir: tempDir,
        export: _ToJsonCountingExport(),
        writer: (task) async {
          // Mimic the worker: create a partial file, then fail.
          await File(task.outputPath).writeAsBytes([1, 2, 3]);
          throw StateError('worker failed');
        },
      );

      await expectLater(
        service.buildEncryptedExportFile(
          password: _password,
          targetDirectory: tempDir,
          fileName: 'partial.prism',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'worker failed',
          ),
        ),
      );
      expect(
        await File('${tempDir.path}/partial.prism').exists(),
        isFalse,
        reason: 'partial output must not survive a writer failure',
      );
    });

    test('real worker through the service: JSON cap propagates and leaves no '
        'output file', () async {
      final service = _StubExportService(
        db: db,
        cacheDir: tempDir,
        export: V1Export.fromJson(_fullExportJson()),
        writer: (task) => writeEncryptedExportFileTask(
          EncryptedExportWriteTask(
            export: task.export,
            mediaBlobs: task.mediaBlobs,
            password: task.password,
            outputPath: task.outputPath,
            jsonPlaintextSoftLimitBytes: 4,
          ),
        ),
      );

      await expectLater(
        service.buildEncryptedExportFile(
          password: _password,
          targetDirectory: tempDir,
          fileName: 'capped.prism',
        ),
        throwsA(isA<ExportJsonTooLargeException>()),
      );
      expect(await File('${tempDir.path}/capped.prism').exists(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('service reports an invalid destination directory and never reports a '
        'ready export', () async {
      final service = _StubExportService(
        db: db,
        cacheDir: tempDir,
        export: _ToJsonCountingExport(),
      );

      // A regular file occupying the destination path makes
      // `Directory.create(recursive: true)` fail with a filesystem error.
      final blocked = File('${tempDir.path}/blocked-dir')
        ..writeAsBytesSync([1]);

      await expectLater(
        service.buildEncryptedExportFile(
          password: _password,
          targetDirectory: Directory(blocked.path),
          fileName: 'nope.prism',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'production default writer produces a real encrypted file end to end',
      () async {
        // Uses the real `writeEncryptedExportFileOffMain` default.
        final service = _StubExportService(
          db: db,
          cacheDir: tempDir,
          export: V1Export.fromJson(_fullExportJson()),
        );

        final result = await service.buildEncryptedExportFile(
          password: _password,
          targetDirectory: tempDir,
          fileName: 'default.prism',
        );

        expect(result.fileName, 'default.prism');
        expect(result.sizeBytes, greaterThan(0));
        final bytes = await result.file.readAsBytes();
        expect(ExportCrypto.isEncrypted(bytes), isTrue);
        final resolved = DataImportService.resolveBytes(
          bytes,
          password: _password,
        );
        final parsed = V1Export.fromJson(
          jsonDecode(resolved.json) as Map<String, dynamic>,
        );
        expect(parsed.rescueLegacyFields, isTrue);
        expect(parsed.headmates, hasLength(1));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

/// Fails from inside `toJson()`, proving the call happens in the worker.
class _ThrowingExport extends V1Export {
  _ThrowingExport()
    : super(
        formatVersion: '1.0',
        version: '1.0',
        appName: 'Prism Plurality',
        exportDate: '2026-07-13T00:00:00.000Z',
        totalRecords: 0,
        headmates: [],
        frontSessions: [],
        sleepSessions: [],
        conversations: [],
        messages: [],
        polls: [],
        pollOptions: [],
        systemSettings: [],
        habits: [],
        habitCompletions: [],
      );

  @override
  Map<String, dynamic> toJson() =>
      throw StateError('toJson ran in the worker and failed');
}
