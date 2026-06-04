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
      'in a modal side sheet tapping a usage dismisses the sheet then navigates',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
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

        // Mirrors MediaSettingsScreen._showUsage's side-sheet branch: capture
        // the router + root navigator outside the sheet, dismiss before
        // navigating. Routes sit in a StatefulShellRoute, matching the app.
        void openUsage(BuildContext context) {
          final router = GoRouter.of(context);
          final rootNavigator = Navigator.of(context, rootNavigator: true);
          showDetailSideSheet(
            context,
            builder: (_) => TagUsageScreen(
              usages: usages,
              onNavigate: (usage) {
                if (rootNavigator.canPop()) rootNavigator.pop();
                unawaited(router.push(usage.route));
              },
            ),
          );
        }

        final router = GoRouter(
          navigatorKey: GlobalKey<NavigatorState>(),
          initialLocation: AppRoutePaths.settings,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (_, _, shell) => shell,
              branches: [
                StatefulShellBranch(
                  navigatorKey: GlobalKey<NavigatorState>(),
                  routes: [
                    GoRoute(
                      path: AppRoutePaths.settings,
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
                      routes: [
                        GoRoute(
                          path: 'members/:id',
                          builder: (_, _) =>
                              const Scaffold(body: Text('member-route')),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
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

        await tester.tap(find.text("Alex's bio"));
        await tester.pumpAndSettle();

        // Destination renders unobstructed: sheet dismissed, route shown.
        expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
        expect(find.text('member-route'), findsOneWidget);
      },
    );
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
