import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/views/fronting_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

class _FakeSleepNotifier extends SleepNotifier {
  final List<String> endedIds = [];

  @override
  void build() {}

  @override
  Future<void> endSleep(String id) async => endedIds.add(id);
}

class _FakeFrontingNotifier extends FrontingNotifier {
  final List<List<String>> startedIds = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    startedIds.add(List<String>.from(memberIds));
  }
}

class _FakeShowFrontingViewToggleNotifier
    extends ShowFrontingViewToggleNotifier {
  @override
  Future<bool> build() async => false;
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState();
}

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime(2024, 1, 1, 22),
  sessionType: SessionType.sleep,
);

Widget _buildSubject({
  required _FakeSleepNotifier sleepNotifier,
  required _FakeFrontingNotifier frontingNotifier,
  required List<Member> members,
  FrontingSession? activeSleepSession,
  bool showQuickFront = false,
}) {
  final settings = SystemSettings(
    systemName: 'Test System',
    showQuickFront: showQuickFront,
    frontingListViewMode: FrontingListViewMode.combinedPeriods,
    wakeSuggestionEnabled: false,
  );

  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => sleepNotifier),
      frontingNotifierProvider.overrideWith(() => frontingNotifier),
      activeSleepSessionProvider.overrideWith(
        (ref) => Stream.value(activeSleepSession),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeSessionsProvider.overrideWith((ref) => Stream.value(const [])),
      memberFrontingCountsProvider.overrideWith((ref) async => const {}),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      unifiedHistoryProvider.overrideWith(
        (ref) => Stream.value(const <FrontingSession>[]),
      ),
      derivedPeriodsProvider.overrideWith(
        (ref) => const AsyncValue.data(<FrontingPeriod>[]),
      ),
      membersByIdsProvider.overrideWith((ref, _) => Stream.value(const {})),
      alwaysPresentMembersProvider.overrideWith(
        (ref) => const AsyncValue.data(<AlwaysPresentMember>[]),
      ),
      frontingMigrationModeProvider.overrideWith(
        (ref) => Stream.value('complete'),
      ),
      showQuickFrontProvider.overrideWith((ref) => showQuickFront),
      systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      showFrontingViewToggleProvider.overrideWith(
        _FakeShowFrontingViewToggleNotifier.new,
      ),
      pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: FrontingScreen(),
    ),
  );
}

Finder _addButton() => find.byTooltip('Add fronting entry');

void main() {
  group('FrontingScreen quick front header', () {
    testWidgets('labels Quick Front and its hold interaction on home', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice'), _member('m2', 'Bob')],
          showQuickFront: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick Front'), findsOneWidget);
      expect(find.text('Press and hold'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Quick Front')).dy,
        lessThan(tester.getTopLeft(find.text('Alice')).dy),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('FrontingScreen add menu', () {
    testWidgets('long-press menu opens historical sheet in past-session mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Past Session').first);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(
        find.byKey(const Key('addFrontModeSegmentedControl')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Wake Up As uses the real screen flow', (tester) async {
      final sleep = _FakeSleepNotifier();
      final fronting = _FakeFrontingNotifier();

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: sleep,
          frontingNotifier: fronting,
          members: [_member('m1', 'Alice'), _member('m2', 'Bob')],
          activeSleepSession: _sleepSession(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wake Up As...'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);

      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();

      expect(sleep.endedIds, ['sleep-1']);
      expect(fronting.startedIds, [
        ['m1'],
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('dismissing Wake Up As does not trigger sleep/front actions', (
      tester,
    ) async {
      final sleep = _FakeSleepNotifier();
      final fronting = _FakeFrontingNotifier();

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: sleep,
          frontingNotifier: fronting,
          members: [_member('m1', 'Alice')],
          activeSleepSession: _sleepSession(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wake Up As...'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      expect(sleep.endedIds, isEmpty);
      expect(fronting.startedIds, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
