import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import '../../../helpers/fake_repositories.dart';

class _StubSyncStatusNotifier extends SyncStatusNotifier {
  _StubSyncStatusNotifier(this._status);

  final SyncStatus _status;

  @override
  SyncStatus build() => _status;
}

void main() {
  final members = [
    Member(id: 'm1', name: 'Alice', createdAt: DateTime.utc(2024)),
    Member(id: 'm2', name: 'Bob', createdAt: DateTime.utc(2024, 1, 2)),
  ];
  final overflowMembers = List.generate(
    9,
    (index) => Member(
      id: 'm$index',
      name: 'Member $index',
      createdAt: DateTime.utc(2024, 1, index + 1),
    ),
  );

  Widget buildSubject({
    List<Member>? subjectMembers,
    bool hideMemberCounts = false,
    SyncStatus syncStatus = const SyncStatus(),
  }) {
    final appPrefs = FakeAppPreferenceRepository();
    if (hideMemberCounts) {
      appPrefs.seed(hideMemberCountsPreference, true);
    }
    addTearDown(appPrefs.close);

    return ProviderScope(
      overrides: [
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        systemSettingsProvider.overrideWith(
          (ref) =>
              Stream.value(const SystemSettings(systemName: 'Test System')),
        ),
        activeMembersProvider.overrideWith(
          (ref) => Stream<List<Member>>.value(subjectMembers ?? members),
        ),
        syncStatusProvider.overrideWith(
          () => _StubSyncStatusNotifier(syncStatus),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen member count', () {
    testWidgets('shows member counts by default', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('2 headmates'), findsOneWidget);
    });

    testWidgets('shows avatar overflow count by default', (tester) async {
      await tester.pumpWidget(buildSubject(subjectMembers: overflowMembers));
      await tester.pumpAndSettle();

      expect(find.text('9 headmates'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('hides member counts when synced preference is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(subjectMembers: overflowMembers, hideMemberCounts: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('9 headmates'), findsNothing);
      expect(find.text('+1'), findsNothing);
    });

    testWidgets('shows sync warning for push-quarantined batches', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(syncStatus: const SyncStatus(quarantinedBatchCount: 1)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Prism Sync'), 300);
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.warningAmber), findsOneWidget);
    });
  });
}
