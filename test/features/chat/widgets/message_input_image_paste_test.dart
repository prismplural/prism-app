import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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

  Widget buildSubject({AppClipboardReader? clipboardReader}) {
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
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: MessageInput(conversationId: 'conv-1')),
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
