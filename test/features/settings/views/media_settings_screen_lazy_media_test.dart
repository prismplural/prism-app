// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/media_attachment_repository.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/media_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  _FakeMediaAttachmentRepository({
    this.libraryImages = const [],
    this.chatAttachments = const [],
  });

  final List<MediaAttachment> libraryImages;
  final List<MediaAttachment> chatAttachments;

  @override
  Stream<List<MediaAttachment>> watchLibraryImages() =>
      Stream.value(libraryImages);

  @override
  Stream<List<MediaAttachment>> watchAllChatMedia() =>
      Stream.value(chatAttachments);

  @override
  Stream<List<MediaAttachment>> watchAllBioMedia() => const Stream.empty();

  @override
  Stream<List<MediaAttachment>> watchForMember(String memberId) =>
      const Stream.empty();

  @override
  Stream<List<MediaAttachment>> watchForMessage(String messageId) =>
      const Stream.empty();

  @override
  Future<List<MediaAttachment>> getForMember(String memberId) async => const [];

  @override
  Future<List<MediaAttachment>> getForMessage(String messageId) async =>
      const [];

  @override
  Future<void> create(MediaAttachment attachment) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> replaceMedia(String attachmentId, MediaAttachment data) async {}

  @override
  Future<void> softDeleteBioMedia(String attachmentId) async {}

  @override
  Future<void> updateTag(String attachmentId, String tag) async {}
}

void main() {
  testWidgets('add menu hides Camera on desktop platforms', (tester) async {
    await _pumpMediaSettingsScreen(
      tester,
      targetPlatform: TargetPlatform.macOS,
    );

    await tester.tap(find.byTooltip('Add image'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsNothing);
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('URL'), findsOneWidget);
  });

  testWidgets('add menu keeps Camera on mobile platforms', (tester) async {
    await _pumpMediaSettingsScreen(
      tester,
      targetPlatform: TargetPlatform.android,
    );

    await tester.tap(find.byTooltip('Add image'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('URL'), findsOneWidget);
  });

  testWidgets('image library thumbnails only request visible media', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final libraryImages = [for (var i = 0; i < 72; i++) _libraryImage(i)];
    final requestedMediaIds = <String>{};
    final repo = _FakeMediaAttachmentRepository(libraryImages: libraryImages);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaAttachmentRepositoryProvider.overrideWithValue(repo),
          imageLibraryProvider.overrideWith(
            (ref) => Stream.value(libraryImages),
          ),
          allMembersProvider.overrideWith(
            (ref) => Stream.value(const <Member>[]),
          ),
          tagUsageProvider.overrideWith((ref, l10n) async => const {}),
          mediaFileProvider.overrideWith((ref, params) async {
            requestedMediaIds.add(params.mediaId);
            return null;
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: MediaSettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedMediaIds.length, lessThan(libraryImages.length));
    final initiallyRequested = requestedMediaIds.length;

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(requestedMediaIds.length, greaterThan(initiallyRequested));
    expect(requestedMediaIds.length, lessThan(libraryImages.length));
  });

  testWidgets('chat thumbnails only request visible media', (tester) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chatAttachments = [for (var i = 0; i < 240; i++) _chatImage(i)];
    final requestedMediaIds = <String>{};
    final repo = _FakeMediaAttachmentRepository(
      chatAttachments: chatAttachments,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaAttachmentRepositoryProvider.overrideWithValue(repo),
          imageLibraryProvider.overrideWith((ref) => Stream.value(const [])),
          allMembersProvider.overrideWith(
            (ref) => Stream.value(const <Member>[]),
          ),
          tagUsageProvider.overrideWith((ref, l10n) async => const {}),
          mediaFileProvider.overrideWith((ref, params) async {
            requestedMediaIds.add(params.mediaId);
            return null;
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: MediaSettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedMediaIds.length, lessThan(chatAttachments.length));
    final initiallyRequested = requestedMediaIds.length;

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(requestedMediaIds.length, greaterThan(initiallyRequested));
    expect(requestedMediaIds.length, lessThan(chatAttachments.length));
  });
}

Future<void> _pumpMediaSettingsScreen(
  WidgetTester tester, {
  required TargetPlatform targetPlatform,
}) async {
  final repo = _FakeMediaAttachmentRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        targetPlatformProvider.overrideWithValue(targetPlatform),
        mediaAttachmentRepositoryProvider.overrideWithValue(repo),
        imageLibraryProvider.overrideWith((ref) => Stream.value(const [])),
        allMembersProvider.overrideWith(
          (ref) => Stream.value(const <Member>[]),
        ),
        tagUsageProvider.overrideWith((ref, l10n) async => const {}),
        mediaFileProvider.overrideWith((ref, params) async => null),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: MediaSettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MediaAttachment _libraryImage(int index) => MediaAttachment(
  id: 'attachment-$index',
  messageId: '',
  tag: 'img-$index',
  mediaId: 'media-$index',
  mediaType: 'image',
  encryptionKeyB64: base64Encode(Uint8List(32)),
  contentHash: 'cipher-$index',
  plaintextHash: 'plain-$index',
  mimeType: 'image/png',
  sizeBytes: 1024,
  width: 120,
  height: 80,
  durationMs: 0,
  blurhash: '',
  waveformB64: '',
  thumbnailMediaId: '',
  sourceUrl: '',
  previewUrl: '',
);

MediaAttachment _chatImage(int index) => MediaAttachment(
  id: 'chat-attachment-$index',
  messageId: 'message-$index',
  tag: '',
  mediaId: 'chat-media-$index',
  mediaType: 'image',
  encryptionKeyB64: base64Encode(Uint8List(32)),
  contentHash: 'chat-cipher-$index',
  plaintextHash: 'chat-plain-$index',
  mimeType: 'image/png',
  sizeBytes: 1024,
  width: 120,
  height: 80,
  durationMs: 0,
  blurhash: '',
  waveformB64: '',
  thumbnailMediaId: '',
  sourceUrl: '',
  previewUrl: '',
);
