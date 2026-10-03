import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/media_attachment_repository.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/widgets/message_input.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/media_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';

import '../../helpers/prism_golden.dart';

class _Files implements PrismFileDialogService {
  int calls = 0;
  PickedFileHandle? result;

  @override
  Future<PickedFileHandle?> pickImageFile({String? dialogTitle}) async {
    calls++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaRepository implements MediaAttachmentRepository {
  @override
  Stream<List<MediaAttachment>> watchAllChatMedia() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpeakingAs extends SpeakingAsNotifier {
  @override
  String? build() => 'synthetic-member';
}

void main() {
  setUpAll(loadPrismGoldenFonts);
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  final pickerCalls = <MethodCall>[];
  final screenshotKey = GlobalKey();

  setUp(() {
    pickerCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          pickerCalls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpSurface(
    WidgetTester tester,
    String surface,
    _Files files, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prismFileDialogServiceProvider.overrideWithValue(files),
          targetPlatformProvider.overrideWithValue(platform),
          mediaAttachmentRepositoryProvider.overrideWithValue(
            _MediaRepository(),
          ),
          imageLibraryProvider.overrideWith((ref) => Stream.value([])),
          allMembersProvider.overrideWith((ref) => Stream.value([])),
          tagUsageProvider.overrideWith((ref, l10n) async => {}),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          gifServiceConfigProvider.overrideWith(
            (ref) async => const GifServiceConfig.disabled(),
          ),
          speakingAsProvider.overrideWith(_SpeakingAs.new),
          activeMembersProvider.overrideWith(
            (ref) => Stream.value([
              Member(
                id: 'synthetic-member',
                name: 'Example',
                createdAt: DateTime(2026),
              ),
            ]),
          ),
          allGroupsProvider.overrideWith((ref) => Stream.value([])),
          allGroupEntriesProvider.overrideWith((ref) => Stream.value([])),
          conversationByIdProvider('synthetic-chat').overrideWith(
            (ref) => Stream.value(
              Conversation(
                id: 'synthetic-chat',
                participantIds: const ['synthetic-member'],
                createdAt: DateTime(2026),
                lastActivityAt: DateTime(2026),
              ),
            ),
          ),
        ],
        child: RepaintBoundary(
          key: screenshotKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.withAppFontFamily(
              AppTheme.light(),
              'Lexend',
              preserveDisplayFont: true,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: switch (surface) {
                'settings' => const MediaSettingsScreen(),
                'markdown' => Center(
                  child: MarkdownImageButton(
                    controller: controller,
                    sessionId: 'synthetic-session',
                  ),
                ),
                _ => const Align(
                  alignment: Alignment.bottomCenter,
                  child: MessageInput(conversationId: 'synthetic-chat'),
                ),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String surface) async {
    await tester.tap(
      surface == 'chat'
          ? find.byType(AttachmentMenuButton)
          : find.byTooltip('Add image'),
    );
    await tester.pumpAndSettle();
  }

  for (final surface in ['settings', 'markdown', 'chat']) {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      testWidgets(
        '$surface $platform File opens files and cancellation leaves editor unchanged',
        (tester) async {
          final files = _Files();
          await pumpSurface(tester, surface, files, platform: platform);
          await openMenu(tester, surface);
          await tester.tap(find.text('File'));
          await tester.pumpAndSettle();

          expect(files.calls, 1);
          expect(pickerCalls, isEmpty);
          expect(find.byType(PrismDialog), findsNothing);
          expect(find.bySemanticsLabel('Attached image preview'), findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }

    for (final source in [ImageSource.gallery, ImageSource.camera]) {
      testWidgets('$surface $source retains native image picker routing', (
        tester,
      ) async {
        final files = _Files();
        await pumpSurface(tester, surface, files);
        await openMenu(tester, surface);
        final label = source == ImageSource.camera
            ? 'Camera'
            : surface == 'chat'
            ? 'Photo Library'
            : 'Photo library';
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(files.calls, 0);
        expect(pickerCalls, hasLength(1));
        expect(pickerCalls.single.method, 'pickImage');
        expect(pickerCalls.single.arguments['source'], source.index);
        expect(pickerCalls.single.arguments['imageQuality'], isNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$surface File bytes reach the existing image flow', (
      tester,
    ) async {
      final bytes = Uint8List.fromList(_png);
      var reads = 0;
      final files = _Files()
        ..result = PickedFileHandle(
          name: 'synthetic.png',
          readAsBytes: () async {
            reads++;
            return bytes;
          },
          openRead: null,
        );
      await pumpSurface(tester, surface, files);
      await openMenu(tester, surface);
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();

      expect(reads, 1);
      expect(pickerCalls, isEmpty);
      if (surface == 'chat') {
        expect(find.bySemanticsLabel('Attached image preview'), findsWidgets);
      } else {
        expect(find.byType(PrismDialog), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'desktop chat keeps its gallery file-dialog fallback',
    (tester) async {
      final files = _Files();
      await pumpSurface(tester, 'chat', files, platform: TargetPlatform.macOS);
      await openMenu(tester, 'chat');
      expect(find.text('Camera'), findsNothing);
      await tester.tap(find.text('Photo Library'));
      await tester.pumpAndSettle();
      expect(files.calls, 1);
      expect(pickerCalls, isEmpty);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('chat source menu screenshot uses synthetic data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSurface(tester, 'chat', _Files());
    await openMenu(tester, 'chat');
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Photo Library'), findsOneWidget);
    const output = String.fromEnvironment('PRISM_MEDIA_MENU_SCREENSHOT');
    if (output.isNotEmpty) {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}

const _png = <int>[
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
