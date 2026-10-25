import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

import '../../../helpers/bio_image_test_utils.dart';
import '../../../helpers/fake_repositories.dart';

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState(isConnected: false);
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  @override
  PkSyncDirection build() => PkSyncDirection.pullOnly;
}

class _EditorFixture {
  final repository = FakeMemberRepository();
  final appPrefs = FakeAppPreferenceRepository();
  final imageInfra = TestBioImageInfra.create();
  final scrollController = ScrollController();

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    scrollController.dispose();
    await tester.runAsync(() async {
      try {
        await appPrefs.close().timeout(const Duration(seconds: 5));
      } finally {
        await imageInfra.close().timeout(const Duration(seconds: 5));
      }
    });
  }

  Widget build(Member member) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(imageInfra.database),
      prismSyncHandleProvider.overrideWithBuild((ref, notifier) => null),
      mediaServiceProvider.overrideWithValue(imageInfra.mediaService),
      uploadQueueProvider.overrideWithValue(imageInfra.uploadQueue),
      downloadManagerProvider.overrideWithValue(imageInfra.downloadManager),
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      memberRepositoryProvider.overrideWithValue(repository),
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
      pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
      pkSyncDirectionProvider.overrideWith(_StaticPkSyncDirectionNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AddEditMemberSheet(
          member: member,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

Future<_EditorFixture> _createFixture(
  WidgetTester tester,
  Member member,
) async {
  final fixture = _EditorFixture();
  addTearDown(() => fixture.close(tester));
  fixture.repository.seed([member]);
  // Open SQLite on the real async clock before the widget starts subscriptions.
  await tester.runAsync(() async {
    await fixture.imageInfra.database
        .customSelect('SELECT 1')
        .get()
        .timeout(const Duration(seconds: 5));
  });
  return fixture;
}

void _useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('pronoun editor retains entered French and English lines', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final member = Member(
      id: 'm-1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    final fixture = await _createFixture(tester, member);
    await tester.pumpWidget(fixture.build(member));
    await tester.pumpAndSettle();

    final pronouns = find.byWidgetPredicate(
      (widget) => widget is PrismTextField && widget.labelText == 'Pronouns',
    );
    await tester.scrollUntilVisible(
      pronouns,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final input = find.descendant(
      of: pronouns,
      matching: find.byType(TextFormField),
    );
    const lines = 'elle / accord féminin\nshe / her';
    await tester.enterText(input, lines);
    await tester.pump();

    final field = tester.widget<PrismTextField>(pronouns);
    expect(field.controller!.text, lines);
    final editable = tester.widget<EditableText>(
      find.descendant(of: pronouns, matching: find.byType(EditableText)),
    );
    expect(editable.keyboardType, TextInputType.multiline);
    expect(editable.textInputAction, TextInputAction.newline);
    expect(editable.maxLines, greaterThan(1));
  });
  testWidgets('pronoun lines survive save and reopening the editor', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final member = Member(
      id: 'm-1',
      name: 'Alice',
      pronouns: 'old',
      createdAt: DateTime(2026, 1, 1),
    );
    final fixture = await _createFixture(tester, member);
    await tester.pumpWidget(fixture.build(member));
    await tester.pumpAndSettle();

    final pronouns = find.byWidgetPredicate(
      (widget) => widget is PrismTextField && widget.labelText == 'Pronouns',
    );
    await tester.scrollUntilVisible(
      pronouns,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    const lines = 'elle / accord féminin\nshe / her\nthey / them';
    await tester.enterText(
      find.descendant(of: pronouns, matching: find.byType(TextFormField)),
      lines,
    );
    tester.testTextInput.hide();
    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();
    final saved = await fixture.repository.getMemberById(member.id);
    expect(saved!.pronouns, lines);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.build(saved));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      pronouns,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<PrismTextField>(pronouns).controller!.text, lines);
  });
}
