import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/settings/utils/tag_usage_scan.dart';
import 'package:prism_plurality/features/settings/views/media_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/l10n/app_localizations_en.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';

void main() {
  group('TagUsageScreen', () {
    testWidgets(
      'on narrow display tapping a bio usage pushes the settings member route',
      (tester) async {
        // Route presentation (no onNavigate): the row navigates directly.
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const memberRoute = '/settings/members/member-1';
        final usages = [
          const TagUsageRef(
            kind: TagUsageKind.bio,
            label: "Alex's bio",
            route: memberRoute,
          ),
        ];

        final router = GoRouter(
          initialLocation: AppRoutePaths.settingsMediaUsage,
          routes: [
            GoRoute(
              path: AppRoutePaths.settingsMediaUsage,
              builder: (_, state) => TagUsageScreen(usages: usages),
            ),
            GoRoute(
              path: '/settings/members/:id',
              builder: (_, _) => const Scaffold(body: Text('member-route')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("Alex's bio"), findsOneWidget);

        await tester.tap(find.text("Alex's bio"));
        await tester.pumpAndSettle();

        expect(find.text('member-route'), findsOneWidget);
      },
    );

    testWidgets(
      'in a side sheet, tapping a settings usage stacks a detail sheet over it',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final usages = [
          const TagUsageRef(
            kind: TagUsageKind.bio,
            label: "Alex's bio",
            route: '/settings/members/member-1',
          ),
        ];

        // Mirrors _showUsage: a settings-area target (non-null detail) stacks
        // as a second sheet over the usage list rather than dismissing it.
        void openUsage(BuildContext context) {
          showDetailSideSheet(
            context,
            builder: (_) => TagUsageScreen(
              usages: usages,
              onNavigate: (sheetContext, usage) {
                showDetailSideSheet(
                  sheetContext,
                  builder: (_) => const Scaffold(body: Text('detail-sheet')),
                );
              },
            ),
          );
        }

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => openUsage(context),
                      child: const Text('open-usage'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('open-usage'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);

        await tester.tap(find.text("Alex's bio"));
        await tester.pumpAndSettle();

        // The usage list stays open with the detail stacked on top.
        expect(find.byKey(const Key('detailSideSheetPanel')), findsNWidgets(2));
        expect(find.byType(TagUsageScreen), findsOneWidget);
        expect(find.text('detail-sheet'), findsOneWidget);
      },
    );

    testWidgets(
      'in a side sheet, tapping a chat usage dismisses the sheet and switches tab',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final usages = [
          const TagUsageRef(
            kind: TagUsageKind.chat,
            label: 'A chat message',
            route: '/chat/c1?messageId=m1',
          ),
        ];

        // Mirrors _showUsage's OpenChatPane branch: dismiss the usage sheet and
        // `go` to the chat tab (which then loads the conversation in its pane).
        void openUsage(BuildContext context) {
          final router = GoRouter.of(context);
          final rootNavigator = Navigator.of(context, rootNavigator: true);
          showDetailSideSheet(
            context,
            builder: (_) => TagUsageScreen(
              usages: usages,
              onNavigate: (sheetContext, usage) {
                if (rootNavigator.canPop()) rootNavigator.pop();
                router.go('/chat');
              },
            ),
          );
        }

        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => openUsage(context),
                      child: const Text('open-usage'),
                    ),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/chat',
              builder: (_, _) => const Scaffold(body: Text('chat-tab')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('open-usage'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);

        await tester.tap(find.text('A chat message'));
        await tester.pumpAndSettle();

        // Usage sheet dismissed, chat tab shown.
        expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
        expect(find.text('chat-tab'), findsOneWidget);
      },
    );
  });

  group('usageTapAction', () {
    TagUsageRef ref(TagUsageKind kind, String route) =>
        TagUsageRef(kind: kind, label: '', route: route);

    UsageTapAction action(
      TagUsageRef usage, {
      bool chatEnabled = true,
      bool notesEnabled = true,
    }) => usageTapAction(
      usage,
      chatEnabled: chatEnabled,
      notesEnabled: notesEnabled,
    );

    test('bio and custom-field stack a MemberDetailScreen', () {
      expect(
        action(ref(TagUsageKind.bio, '/settings/members/m1')),
        isA<StackDetailSheet>().having(
          (a) => a.screen,
          'screen',
          isA<MemberDetailScreen>().having((s) => s.memberId, 'memberId', 'm1'),
        ),
      );
      expect(
        action(ref(TagUsageKind.customField, '/settings/members/m2')),
        isA<StackDetailSheet>().having(
          (a) => a.screen,
          'screen',
          isA<MemberDetailScreen>().having((s) => s.memberId, 'memberId', 'm2'),
        ),
      );
    });

    test('group stacks a GroupDetailScreen', () {
      expect(
        action(ref(TagUsageKind.group, '/settings/members/groups/g1')),
        isA<StackDetailSheet>().having(
          (a) => a.screen,
          'screen',
          isA<GroupDetailScreen>().having((s) => s.groupId, 'groupId', 'g1'),
        ),
      );
    });

    test('note opens the notes pane when the notes tab is enabled', () {
      expect(
        action(ref(TagUsageKind.note, '/settings/notes/n1')),
        isA<OpenNotesPane>().having((a) => a.noteId, 'noteId', 'n1'),
      );
    });

    test('note falls back to full-screen when the notes tab is disabled', () {
      expect(
        action(ref(TagUsageKind.note, '/settings/notes/n1'), notesEnabled: false),
        isA<NavigateFullScreen>().having(
          (a) => a.route,
          'route',
          '/settings/notes/n1',
        ),
      );
    });

    test('chat opens the chat pane when the chat tab is enabled', () {
      expect(
        action(ref(TagUsageKind.chat, '/chat/c1?messageId=m1')),
        isA<OpenChatPane>().having(
          (a) => a.conversationId,
          'conversationId',
          'c1',
        ),
      );
    });

    test('chat falls back to full-screen when the chat tab is disabled', () {
      expect(
        action(ref(TagUsageKind.chat, '/chat/c1?messageId=m1'), chatEnabled: false),
        isA<NavigateFullScreen>().having(
          (a) => a.route,
          'route',
          '/chat/c1?messageId=m1',
        ),
      );
    });

    test('board posts navigate full-screen', () {
      expect(
        action(ref(TagUsageKind.boardPost, '/boards/posts/p1')),
        isA<NavigateFullScreen>().having(
          (a) => a.route,
          'route',
          '/boards/posts/p1',
        ),
      );
    });
  });

  group('tagUsageProvider', () {
    test(
      'does not read Ref after auto-dispose during async usage scan',
      () async {
        final customFieldsRepository = _BlockingCustomFieldsRepository();
        final debugMessages = <String>[];
        final oldDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) debugMessages.add(message);
        };
        addTearDown(() => debugPrint = oldDebugPrint);

        final container = ProviderContainer(
          overrides: [
            imageLibraryProvider.overrideWithValue(
              AsyncValue.data([_libraryAttachment()]),
            ),
            allMembersProvider.overrideWithValue(const AsyncValue.data([])),
            allNotesProvider.overrideWithValue(const AsyncValue.data([])),
            allGroupsProvider.overrideWithValue(const AsyncValue.data([])),
            customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
            customFieldsRepositoryProvider.overrideWithValue(
              customFieldsRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final subscription = container.listen(
          tagUsageProvider(AppLocalizationsEn()),
          (_, _) {},
          fireImmediately: true,
        );

        await Future<void>.delayed(Duration.zero);
        subscription.close();
        await Future<void>.delayed(Duration.zero);

        customFieldsRepository.completeValues(const []);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          debugMessages,
          isNot(contains(contains('Cannot use the Ref of FutureProvider'))),
        );
      },
    );
  });
}

MediaAttachment _libraryAttachment() => MediaAttachment(
  id: 'att-flag',
  messageId: '',
  tag: 'flag',
  mediaId: 'media-flag',
  mediaType: 'image',
  encryptionKeyB64: base64Encode(List<int>.filled(32, 0)),
  contentHash: 'chash',
  plaintextHash: 'phash',
  mimeType: 'image/png',
  sizeBytes: 1,
  width: 1,
  height: 1,
  durationMs: 0,
  blurhash: '',
  waveformB64: '',
  thumbnailMediaId: '',
  sourceUrl: '',
  previewUrl: '',
);

class _BlockingCustomFieldsRepository implements CustomFieldsRepository {
  final _valuesCompleter = Completer<List<CustomFieldValue>>();

  void completeValues(List<CustomFieldValue> values) {
    _valuesCompleter.complete(values);
  }

  @override
  Future<List<CustomFieldValue>> getAllValues() => _valuesCompleter.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
