import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_list_view_settings_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fronting_term_fixtures.dart';

void main() {
  testWidgets('behavior labels stay generic with custom fronting terms', (
    tester,
  ) async {
    final customTerms = FrontingTermBundle.tryDecode({
      ...testFrontingTermBundle.toJson(),
      'addAction': 'Add: Gayest',
      'replaceCurrentAction': 'Replace: Gayest',
      'directButtonLabel': 'Gayest buttons',
    })!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allGroupsProvider.overrideWithValue(const AsyncValue.data([])),
          membersShowGroupsProvider.overrideWithValue(false),
          membersListViewModeProvider.overrideWithValue(
            MembersListViewMode.groupedSections,
          ),
          membersGroupedDefaultStateProvider.overrideWithValue(
            MembersGroupedDefaultState.open,
          ),
          membersFolderMemberVisibilityProvider.overrideWithValue(
            MembersFolderMemberVisibility.allMembers,
          ),
          membersShowPronounsProvider.overrideWithValue(true),
          membersShowFrontButtonsProvider.overrideWithValue(true),
          membersFrontButtonBehaviorProvider.overrideWithValue(
            FrontStartBehavior.additive,
          ),
          frontingTermsSettingProvider.overrideWithValue(
            FrontingTerms.custom(customTerms),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: MemberListViewSettingsSheet(
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Add: Gayest'), findsNothing);
    expect(find.text('Replace: Gayest'), findsNothing);
    expect(find.text('Gayest buttons'), findsOneWidget);
  });
}
