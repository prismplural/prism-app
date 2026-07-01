import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

import '../../../helpers/bio_image_test_utils.dart';
import '../../../helpers/fake_repositories.dart';

class _DisconnectedPkNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState();
}

class _PushDisabledNotifier extends PkSyncDirectionNotifier {
  @override
  PkSyncDirection build() => PkSyncDirection.disabled;
}

Widget _buildMemberEditor({
  required Member member,
  AddEditMemberSheetController? controller,
  List<CustomField> customFields = const [],
  TestBioImageInfra? imageInfra,
}) {
  final repo = FakeMemberRepository()..seed([member]);

  return ProviderScope(
    overrides: [
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      memberRepositoryProvider.overrideWithValue(repo),
      frontingSessionRepositoryProvider.overrideWithValue(
        FakeFrontingSessionRepository(),
      ),
      customFieldsProvider.overrideWithValue(AsyncValue.data(customFields)),
      memberCustomFieldValuesProvider.overrideWith(
        (ref, memberId) => Stream<List<CustomFieldValue>>.value(const []),
      ),
      memberAvatarImageDataProvider.overrideWith(
        (ref, memberId) => Stream.value(null),
      ),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.members,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
      memberNamePreferDisplayProvider.overrideWithValue(false),
      pluralKitSyncProvider.overrideWith(_DisconnectedPkNotifier.new),
      pkSyncDirectionProvider.overrideWith(_PushDisabledNotifier.new),
      if (imageInfra != null) ...[
        databaseProvider.overrideWithValue(imageInfra.database),
        prismSyncHandleProvider.overrideWithBuild((ref, notifier) => null),
        mediaServiceProvider.overrideWithValue(imageInfra.mediaService),
      ],
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AddEditMemberSheet(
          member: member,
          embedded: true,
          controller: controller,
        ),
      ),
    ),
  );
}

Widget _buildMemberEditorSheetHost({required Member member}) {
  final repo = FakeMemberRepository()..seed([member]);

  return ProviderScope(
    overrides: [
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      memberRepositoryProvider.overrideWithValue(repo),
      frontingSessionRepositoryProvider.overrideWithValue(
        FakeFrontingSessionRepository(),
      ),
      customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
      memberCustomFieldValuesProvider.overrideWith(
        (ref, memberId) => Stream<List<CustomFieldValue>>.value(const []),
      ),
      memberAvatarImageDataProvider.overrideWith(
        (ref, memberId) => Stream.value(null),
      ),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.members,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
      memberNamePreferDisplayProvider.overrideWithValue(false),
      pluralKitSyncProvider.overrideWith(_DisconnectedPkNotifier.new),
      pkSyncDirectionProvider.overrideWith(_PushDisabledNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              PrismSheet.showFullScreen<void>(
                context: context,
                builder: (context, scrollController) => AddEditMemberSheet(
                  member: member,
                  scrollController: scrollController,
                ),
              );
            },
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'member editor sheet prompts when swipe-dismissed after form scrolling',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final member = Member(
        id: 'member-1',
        name: 'Aster',
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(_buildMemberEditorSheetHost(member: member));
      await tester.pump();

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      expect(find.text('Name *'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'Edited Aster');
      await tester.pump();

      Future<void> dragScrolledSheetAway() async {
        await tester.dragFrom(const Offset(195, 280), const Offset(0, 140));
        await tester.pump(const Duration(milliseconds: 250));

        await tester.drag(
          find.byKey(const PageStorageKey<String>('member-edit-main')),
          const Offset(0, -520),
        );
        await tester.pump();

        await tester.dragFrom(const Offset(195, 720), const Offset(0, 760));
        await tester.pumpAndSettle();
      }

      await dragScrolledSheetAway();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Edited Aster'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Edited Aster'), findsOneWidget);

      await dragScrolledSheetAway();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Edited Aster'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Edited Aster'), findsNothing);
    },
  );

  testWidgets(
    'member editor defers custom field value stream until the custom field view opens',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final member = Member(
        id: 'member-1',
        name: 'Aster',
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = FakeMemberRepository()..seed([member]);
      final watchedMemberIds = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
            memberRepositoryProvider.overrideWithValue(repo),
            frontingSessionRepositoryProvider.overrideWithValue(
              FakeFrontingSessionRepository(),
            ),
            customFieldsProvider.overrideWithValue(
              AsyncValue.data([
                CustomField(
                  id: 'field-1',
                  name: 'Favorite tea',
                  fieldType: CustomFieldType.text,
                  fieldTypeId: 'text',
                  createdAt: DateTime(2026, 1, 1),
                ),
              ]),
            ),
            memberCustomFieldValuesProvider.overrideWith((ref, memberId) {
              watchedMemberIds.add(memberId);
              return Stream<List<CustomFieldValue>>.value(const []);
            }),
            terminologySettingProvider.overrideWithValue((
              term: SystemTerminology.members,
              customSingular: null,
              customPlural: null,
              useEnglish: false,
            )),
            memberNamePreferDisplayProvider.overrideWithValue(false),
            pluralKitSyncProvider.overrideWith(_DisconnectedPkNotifier.new),
            pkSyncDirectionProvider.overrideWith(_PushDisabledNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AddEditMemberSheet(
                member: member,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(watchedMemberIds, isEmpty);

      await tester.tap(find.text('Custom Fields'));
      await tester.pump();

      expect(watchedMemberIds, contains(member.id));
    },
  );

  testWidgets('embedded member editor opens bio detail in the pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final member = Member(
      id: 'member-1',
      name: 'Aster',
      bio: 'Existing bio',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeMemberRepository()..seed([member]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
          memberRepositoryProvider.overrideWithValue(repo),
          frontingSessionRepositoryProvider.overrideWithValue(
            FakeFrontingSessionRepository(),
          ),
          customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
          memberAvatarImageDataProvider.overrideWith(
            (ref, memberId) => Stream.value(null),
          ),
          terminologySettingProvider.overrideWithValue((
            term: SystemTerminology.members,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
          memberNamePreferDisplayProvider.overrideWithValue(false),
          pluralKitSyncProvider.overrideWith(_DisconnectedPkNotifier.new),
          pkSyncDirectionProvider.overrideWith(_PushDisabledNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AddEditMemberSheet(member: member, embedded: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FullScreenMarkdownEditorSheet), findsNothing);

    await tester.tap(find.byTooltip('Edit bio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FullScreenMarkdownEditorSheet), findsNothing);
    expect(
      find.byKey(const PageStorageKey<String>('member-edit-bio')),
      findsOneWidget,
    );
  });

  testWidgets('member editor discards image-only staged bio edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageInfra = TestBioImageInfra.create();
    addTearDown(imageInfra.close);
    final controller = AddEditMemberSheetController();
    final member = Member(
      id: 'member-1',
      name: 'Aster',
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      _buildMemberEditor(
        member: member,
        controller: controller,
        imageInfra: imageInfra,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Edit bio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final imageButton = tester.widget<MarkdownImageButton>(
      find.byType(MarkdownImageButton),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownImageButton)),
    );
    final processor = container.read(
      bioImageProcessorProvider(imageButton.sessionId),
    );
    processor.staged.add(testStagedBioImage());

    final bioField = find.byType(TextField).last;
    await tester.enterText(bioField, 'temporary text');
    await tester.pump();
    await tester.enterText(bioField, '');
    await tester.pump();

    var confirm = controller.confirmDiscardIfNeeded();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await confirm, isFalse);
    expect(processor.staged, isNotEmpty);

    confirm = controller.confirmDiscardIfNeeded();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(await confirm, isTrue);
    expect(processor.staged, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'member editor discards image-only staged custom long-text edits',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final imageInfra = TestBioImageInfra.create();
      addTearDown(imageInfra.close);
      final controller = AddEditMemberSheetController();
      final member = Member(
        id: 'member-1',
        name: 'Aster',
        createdAt: DateTime(2026, 1, 1),
      );
      final longText = CustomField(
        id: 'field-1',
        name: 'Second Bio',
        fieldType: CustomFieldType.longText,
        fieldTypeId: 'long_text',
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        _buildMemberEditor(
          member: member,
          controller: controller,
          customFields: [longText],
          imageInfra: imageInfra,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Custom Fields'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(AppIcons.edit).hitTestable().first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final imageButton = tester.widget<MarkdownImageButton>(
        find.byType(MarkdownImageButton),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MarkdownImageButton)),
      );
      final processor = container.read(
        bioImageProcessorProvider(imageButton.sessionId),
      );
      processor.staged.add(
        testStagedBioImage(mediaId: 'media-custom', tag: 'custom-image'),
      );

      final customField = find.byType(TextField).last;
      await tester.enterText(customField, 'temporary text');
      await tester.pump();
      await tester.enterText(customField, '');
      await tester.pump();

      var confirm = controller.confirmDiscardIfNeeded();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await confirm, isFalse);
      expect(processor.staged, isNotEmpty);

      confirm = controller.confirmDiscardIfNeeded();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(await confirm, isTrue);
      expect(processor.staged, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('compact member bio editor resolves existing mentions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const aliceId = '11111111-2222-3333-4444-555555555555';
    const bobId = '66666666-7777-8888-9999-000000000000';
    final alice = Member(
      id: aliceId,
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    final bob = Member(id: bobId, name: 'Bob', createdAt: DateTime(2026, 1, 1));
    final member = Member(
      id: 'member-1',
      name: 'Aster',
      bio: 'talked to @[$aliceId] and @[$bobId]',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeMemberRepository()..seed([member, alice, bob]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
          memberRepositoryProvider.overrideWithValue(repo),
          frontingSessionRepositoryProvider.overrideWithValue(
            FakeFrontingSessionRepository(),
          ),
          customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
          terminologySettingProvider.overrideWithValue((
            term: SystemTerminology.members,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
          memberNamePreferDisplayProvider.overrideWithValue(false),
          pluralKitSyncProvider.overrideWith(_DisconnectedPkNotifier.new),
          pkSyncDirectionProvider.overrideWith(_PushDisabledNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AddEditMemberSheet(member: member)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final bioField = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && widget.controller.text.contains('@['),
    );
    expect(bioField, findsOneWidget);
    final editable = tester.widget<EditableText>(bioField);
    final displayText = editable.controller
        .buildTextSpan(
          context: tester.element(bioField),
          style: editable.style,
          withComposing: false,
        )
        .toPlainText();

    expect(displayText, contains('@Alice'));
    expect(displayText, contains('@Bob'));
    expect(displayText, isNot(contains('@Unknown')));
  });

  testWidgets('compact member bio preview resolves existing mentions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const aliceId = '11111111-2222-3333-4444-555555555555';
    const bobId = '66666666-7777-8888-9999-000000000000';
    final alice = Member(
      id: aliceId,
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    final bob = Member(id: bobId, name: 'Bob', createdAt: DateTime(2026, 1, 1));
    final member = Member(
      id: 'member-1',
      name: 'Aster',
      bio: 'talked to @[$aliceId] and @[$bobId]',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeMemberRepository()..seed([member, alice, bob]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
          memberRepositoryProvider.overrideWithValue(repo),
          frontingSessionRepositoryProvider.overrideWithValue(
            FakeFrontingSessionRepository(),
          ),
          customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
          terminologySettingProvider.overrideWithValue((
            term: SystemTerminology.members,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
          memberNamePreferDisplayProvider.overrideWithValue(false),
          pluralKitSyncProvider.overrideWith(_DisconnectedPkNotifier.new),
          pkSyncDirectionProvider.overrideWith(_PushDisabledNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AddEditMemberSheet(member: member, embedded: true),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Edit bio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Preview'));
    await tester.pump();

    expect(
      find.byKey(const PageStorageKey<String>('member-edit-bio-preview')),
      findsOneWidget,
    );
    expect(find.textContaining('@Alice and @Bob'), findsOneWidget);
    expect(find.textContaining('@Unknown'), findsNothing);
  });
}
