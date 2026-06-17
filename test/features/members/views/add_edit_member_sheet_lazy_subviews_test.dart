import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';

import '../../../helpers/fake_repositories.dart';

class _DisconnectedPkNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState();
}

class _PushDisabledNotifier extends PkSyncDirectionNotifier {
  @override
  PkSyncDirection build() => PkSyncDirection.disabled;
}

void main() {
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
