import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
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

import '../../../helpers/fake_repositories.dart';

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState(isConnected: false);
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  @override
  PkSyncDirection build() => PkSyncDirection.pullOnly;
}

Widget _harness(Member member) {
  final repo = FakeMemberRepository()..seed([member]);
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);

  return ProviderScope(
    overrides: [
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
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
      pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
      pkSyncDirectionProvider.overrideWith(_StaticPkSyncDirectionNotifier.new),
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
  );
}

void _useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('changing an existing member birthday updates the field', (
    tester,
  ) async {
    _useMobileViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      birthday: '1993-07-15',
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(_harness(member));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Birthday'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Jul 15, 1993'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();

    expect(find.text('Jul 16, 1993'), findsOneWidget);
  });
}
