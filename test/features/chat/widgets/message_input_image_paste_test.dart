import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drift/native.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/image_compression_service.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/core/services/media/upload_queue.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart'
    as media_model;
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/media_attachment_repository.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// A constructible upload queue for fakes that never exercise uploads. Built in
/// initializer lists, so it can't register an `addTearDown`; the in-memory DB is
/// freed when the test process exits.
UploadQueue _noopUploadQueue() => UploadQueue(
  dao: AppDatabase(NativeDatabase.memory()).uploadQueueDao,
  upload:
      ({
        required String mediaId,
        required String contentHash,
        required Uint8List data,
        BigInt? ttlSecs,
      }) async => UploadAttemptResult.unconfigured,
  resumeOnStart: false,
);

class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => 'alice-id';
}

class _FakeClipboardReader implements AppClipboardReader {
  const _FakeClipboardReader({this.image, this.uriImage});

  final ClipboardImageData? image;
  final ClipboardImageData? uriImage;

  @override
  Future<ClipboardImageData?> readImage({
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
  }) async => image;

  @override
  Future<ClipboardImageData?> readImageUri(String uri) async => uriImage;
}

void main() {
  tearDown(PrismToast.resetForTest);

  final alice = Member(
    id: 'alice-id',
    name: 'Alice',
    createdAt: DateTime(2025, 1, 1),
    isActive: true,
  );
  final conversation = Conversation(
    id: 'conv-1',
    participantIds: const ['alice-id'],
    createdAt: DateTime(2025, 1, 1),
    lastActivityAt: DateTime(2025, 1, 1),
    title: 'Image paste',
  );

  Widget buildSubject({
    AppClipboardReader? clipboardReader,
    ChatNotifier Function()? chatNotifierFactory,
    ChatImagePicker? chatImagePicker,
    MediaAttachmentRepository? mediaAttachmentRepository,
    MediaService? mediaService,
  }) {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        gifServiceConfigProvider.overrideWith(
          (ref) async => const GifServiceConfig.disabled(),
        ),
        speakingAsProvider.overrideWith(_FixedSpeakingAsNotifier.new),
        activeMembersProvider.overrideWith((ref) => Stream.value([alice])),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        conversationByIdProvider(
          'conv-1',
        ).overrideWith((ref) => Stream.value(conversation)),
        if (clipboardReader != null)
          appClipboardReaderProvider.overrideWithValue(clipboardReader),
        if (chatNotifierFactory != null)
          chatNotifierProvider.overrideWith(chatNotifierFactory),
        if (chatImagePicker != null)
          chatImagePickerProvider.overrideWithValue(chatImagePicker),
        if (mediaAttachmentRepository != null)
          mediaAttachmentRepositoryProvider.overrideWithValue(
            mediaAttachmentRepository,
          ),
        if (mediaService != null)
          mediaServiceProvider.overrideWithValue(mediaService),
      ],
      child: MaterialApp(
        builder: (context, child) =>
            PrismToastHost(child: child ?? const SizedBox.shrink()),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const Scaffold(body: MessageInput(conversationId: 'conv-1')),
      ),
    );
  }

  testWidgets('stages image content inserted into the message field', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    final config = textField.contentInsertionConfiguration;
    expect(config, isNotNull);
    expect(config!.allowedMimeTypes, contains('image/png'));

    config.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://prism.test/pasted.png',
        data: Uint8List.fromList(_transparentPng),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);
    expect(find.bySemanticsLabel('Send message'), findsOneWidget);
  });

  testWidgets('reads inserted image URI through app clipboard reader', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        clipboardReader: _FakeClipboardReader(
          uriImage: ClipboardImageData(
            bytes: Uint8List.fromList(_transparentPng),
            mimeType: 'image/png',
            sourceUri: 'content://prism.test/pasted.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    final config = textField.contentInsertionConfiguration;
    expect(config, isNotNull);

    config!.onContentInserted(
      const KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://prism.test/pasted.png',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);
  });

  testWidgets('PasteTextIntent tries app clipboard image before text paste', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        clipboardReader: _FakeClipboardReader(
          image: ClipboardImageData(
            bytes: Uint8List.fromList(_transparentPng),
            mimeType: 'image/png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final textFieldContext = tester.element(find.byType(TextField));
    Actions.invoke(
      textFieldContext,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);
  });

  testWidgets('photo library pick does not request picker recompression', (
    tester,
  ) async {
    final imagePicker = _RecordingChatImagePicker(
      Uint8List.fromList(_transparentPng),
    );

    await tester.pumpWidget(buildSubject(chatImagePicker: imagePicker));
    await tester.pumpAndSettle();

    expect(find.byType(AttachmentMenuButton), findsOneWidget);
    final button = tester.widget<AttachmentMenuButton>(
      find.byType(AttachmentMenuButton),
    );
    button.onPhotoLibrary();
    await tester.pumpAndSettle();

    expect(imagePicker.sources, [ImageSource.gallery]);
    expect(imagePicker.imageQualities, [isNull]);
    expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);
  });

  testWidgets('ignores non-image inserted content', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    final config = textField.contentInsertionConfiguration;
    expect(config, isNotNull);

    config!.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'text/plain',
        uri: 'content://prism.test/pasted.txt',
        data: Uint8List.fromList(const [104, 101, 108, 108, 111]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Attached image preview'), findsNothing);
  });

  testWidgets(
    'clears staged image after local message is accepted while upload continues',
    (tester) async {
      final uploadCompleter = Completer<void>();
      final uploadStarted = Completer<void>();
      addTearDown(() {
        if (!uploadCompleter.isCompleted) {
          uploadCompleter.complete();
        }
      });
      final mediaService = _BlockingUploadMediaService(
        uploadCompleter,
        uploadStarted: uploadStarted,
      );
      final mediaAttachmentRepository = _RecordingMediaAttachmentRepository();

      await tester.pumpWidget(
        buildSubject(
          chatNotifierFactory: _RecordingChatNotifier.new,
          mediaAttachmentRepository: mediaAttachmentRepository,
          mediaService: mediaService,
        ),
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      textField.contentInsertionConfiguration!.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://prism.test/pasted.png',
          data: Uint8List.fromList(_transparentPng),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.pump();
      expect(uploadStarted.isCompleted, isTrue);

      expect(mediaAttachmentRepository.created, hasLength(1));
      expect(find.bySemanticsLabel('Attached image preview'), findsNothing);

      uploadCompleter.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shows an error toast when upload fails after local send', (
    tester,
  ) async {
    final uploadCompleter = Completer<void>();
    final uploadStarted = Completer<void>();
    addTearDown(() {
      if (!uploadCompleter.isCompleted) {
        uploadCompleter.complete();
      }
    });
    final mediaService = _BlockingUploadMediaService(
      uploadCompleter,
      uploadStarted: uploadStarted,
      uploadError: StateError('upload failed'),
    );
    final mediaAttachmentRepository = _RecordingMediaAttachmentRepository();
    final chatNotifier = _RecordingChatNotifier();

    await tester.pumpWidget(
      buildSubject(
        chatNotifierFactory: () => chatNotifier,
        mediaAttachmentRepository: mediaAttachmentRepository,
        mediaService: mediaService,
      ),
    );
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    textField.contentInsertionConfiguration!.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://prism.test/pasted.png',
        data: Uint8List.fromList(_transparentPng),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(uploadStarted.isCompleted, isTrue);

    expect(chatNotifier.sentContents, ['']);
    expect(mediaAttachmentRepository.created, hasLength(1));
    expect(find.bySemanticsLabel('Attached image preview'), findsNothing);
    expect(find.text('Image failed to send'), findsOneWidget);
    PrismToast.resetForTest();
    await tester.pump();
  });

  testWidgets('sends text when staged image preparation fails', (tester) async {
    final chatNotifier = _RecordingChatNotifier();
    final mediaAttachmentRepository = _RecordingMediaAttachmentRepository();

    await tester.pumpWidget(
      buildSubject(
        chatNotifierFactory: () => chatNotifier,
        mediaAttachmentRepository: mediaAttachmentRepository,
        mediaService: _FailingPrepareImageMediaService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    textField.contentInsertionConfiguration!.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://prism.test/pasted.png',
        data: Uint8List.fromList(_transparentPng),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    await tester.pump();

    expect(chatNotifier.sentContents, ['hello']);
    expect(find.bySemanticsLabel('Attached image preview'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('does not send empty message when image-only preparation fails', (
    tester,
  ) async {
    final chatNotifier = _RecordingChatNotifier();
    final mediaAttachmentRepository = _RecordingMediaAttachmentRepository();

    await tester.pumpWidget(
      buildSubject(
        chatNotifierFactory: () => chatNotifier,
        mediaAttachmentRepository: mediaAttachmentRepository,
        mediaService: _FailingPrepareImageMediaService(),
      ),
    );
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    textField.contentInsertionConfiguration!.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://prism.test/pasted.png',
        data: Uint8List.fromList(_transparentPng),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    await tester.pump();

    expect(chatNotifier.sentContents, isEmpty);
    expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
  });
}

class _RecordingChatNotifier extends ChatNotifier {
  final sentContents = <String>[];

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String content,
    required String authorId,
    String? messageId,
    String? replyToId,
    String? replyToAuthorId,
    String? replyToContent,
  }) async {
    sentContents.add(content);
    return 'message-1';
  }
}

class _RecordingChatImagePicker extends ChatImagePicker {
  _RecordingChatImagePicker(this.bytes);

  final Uint8List bytes;
  final sources = <ImageSource>[];
  final imageQualities = <int?>[];

  @override
  Future<Uint8List?> pickImageBytes(
    ImageSource source, {
    int? imageQuality,
  }) async {
    sources.add(source);
    imageQualities.add(imageQuality);
    return bytes;
  }
}

class _RecordingMediaAttachmentRepository implements MediaAttachmentRepository {
  final created = <media_model.MediaAttachment>[];

  @override
  Future<void> create(media_model.MediaAttachment attachment) async {
    created.add(attachment);
  }

  @override
  Future<void> delete(String id) async {
    created.removeWhere((attachment) => attachment.id == id);
  }

  @override
  Future<List<media_model.MediaAttachment>> getForMessage(
    String messageId,
  ) async {
    return created
        .where((attachment) => attachment.messageId == messageId)
        .toList(growable: false);
  }

  @override
  Stream<List<media_model.MediaAttachment>> watchForMessage(String messageId) {
    return Stream.value(
      created
          .where((attachment) => attachment.messageId == messageId)
          .toList(growable: false),
    );
  }

  @override
  Stream<List<media_model.MediaAttachment>> watchForMember(String memberId) {
    return Stream.value(
      created
          .where((attachment) => attachment.memberId == memberId)
          .toList(growable: false),
    );
  }

  @override
  Future<List<media_model.MediaAttachment>> getForMember(
    String memberId,
  ) async {
    return created
        .where((attachment) => attachment.memberId == memberId)
        .toList(growable: false);
  }

  @override
  Future<void> softDeleteBioMedia(String attachmentId) async {
    created.removeWhere((attachment) => attachment.id == attachmentId);
  }

  @override
  Stream<List<media_model.MediaAttachment>> watchAllBioMedia() =>
      Stream.value([]);

  @override
  Stream<List<media_model.MediaAttachment>> watchAllChatMedia() =>
      Stream.value([]);

  @override
  Stream<List<media_model.MediaAttachment>> watchLibraryImages() =>
      Stream.value([]);

  @override
  Future<void> updateTag(String attachmentId, String tag) async {}

  @override
  Future<void> replaceMedia(
    String attachmentId,
    media_model.MediaAttachment data,
  ) async {
    final i = created.indexWhere((a) => a.id == attachmentId);
    if (i >= 0) created[i] = data;
  }
}

class _BlockingUploadMediaService extends MediaService {
  _BlockingUploadMediaService(
    this.uploadCompleter, {
    this.uploadStarted,
    this.uploadError,
  }) : super(
         compression: ImageCompressionService(),
         encryption: MediaEncryptionService(),
         uploadQueue: _noopUploadQueue(),
         downloadManager: DownloadManager(
           handle: null,
           encryption: MediaEncryptionService(),
         ),
       );

  final Completer<void> uploadCompleter;
  final Completer<void>? uploadStarted;
  final Object? uploadError;

  @override
  Future<MediaAttachmentData> prepareImage(Uint8List imageBytes) async {
    return MediaAttachmentData(
      mediaId: 'media-1',
      thumbnailMediaId: 'thumb-1',
      encryptedImage: Uint8List.fromList(const [1, 2, 3]),
      encryptedThumbnail: Uint8List.fromList(const [4, 5, 6]),
      encryptionKey: Uint8List.fromList(const [7, 8, 9]),
      contentHash: 'content-hash',
      plaintextHash: 'plaintext-hash',
      thumbnailContentHash: 'thumbnail-content-hash',
      thumbnailPlaintextHash: 'thumbnail-plaintext-hash',
      width: 1,
      height: 1,
      sizeBytes: imageBytes.length,
      blurhash: '',
      mimeType: 'image/webp',
    );
  }

  @override
  Future<void> uploadPreparedOrThrow(MediaAttachmentData data) async {
    final started = uploadStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final error = uploadError;
    if (error != null) {
      throw error;
    }
    await uploadCompleter.future;
  }
}

class _FailingPrepareImageMediaService extends MediaService {
  _FailingPrepareImageMediaService()
    : super(
        compression: ImageCompressionService(),
        encryption: MediaEncryptionService(),
        uploadQueue: _noopUploadQueue(),
        downloadManager: DownloadManager(
          handle: null,
          encryption: MediaEncryptionService(),
        ),
      );

  @override
  Future<MediaAttachmentData> prepareImage(Uint8List imageBytes) async {
    throw StateError('prepare failed');
  }
}

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
