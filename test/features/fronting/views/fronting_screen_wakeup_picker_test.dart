import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/quick_front_hint_provider.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/fronting_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_repositories.dart';

class _FakeSleepNotifier extends SleepNotifier {
  final List<String> endedIds = [];

  @override
  void build() {}

  @override
  Future<void> endSleep(String id) async => endedIds.add(id);
}

class _FakeFrontingNotifier extends FrontingNotifier {
  final List<List<String>> startedIds = [];
  final wakeUps =
      <
        ({String sleepSessionId, SleepQuality? quality, List<String> memberIds})
      >[];

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

  @override
  Future<void> wakeUp(
    String sleepSessionId, {
    SleepQuality? quality,
    List<String> frontingMemberIds = const [],
  }) async {
    wakeUps.add((
      sleepSessionId: sleepSessionId,
      quality: quality,
      memberIds: List<String>.from(frontingMemberIds),
    ));
  }
}

class _FakeShowFrontingViewToggleNotifier
    extends ShowFrontingViewToggleNotifier {
  @override
  Future<bool> build() async => false;
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  _FakePluralKitSyncNotifier(
    this._state, {
    this.deleteRiskPreview = const PkDeleteRiskPreview(),
  });

  final PluralKitSyncState _state;
  final PkDeleteRiskPreview deleteRiskPreview;
  int previewPendingDestructivePushCallCount = 0;
  int syncRecentDataCallCount = 0;
  int syncLiveFrontersOnlyCallCount = 0;
  PkSyncDirection? lastSyncDirection;

  @override
  PluralKitSyncState build() => _state;

  @override
  Future<PkDeleteRiskPreview> previewPendingDestructivePush() async {
    previewPendingDestructivePushCallCount += 1;
    return deleteRiskPreview;
  }

  @override
  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async {
    syncRecentDataCallCount += 1;
    lastSyncDirection = direction;
    return null;
  }

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
    PKSwitch? knownCurrentFronters,
  }) async {
    syncLiveFrontersOnlyCallCount += 1;
    lastSyncDirection = direction;
    return null;
  }
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _StaticPkSyncDirectionNotifier(this._initial);

  final PkSyncDirection _initial;

  @override
  PkSyncDirection build() => _initial;

  @override
  Future<void> load() async {
    state = _initial;
  }
}

class _StaticPkSyncModeNotifier extends PkSyncModeNotifier {
  _StaticPkSyncModeNotifier(this._initial);

  final PkSyncMode _initial;

  @override
  PkSyncMode build() => _initial;

  @override
  Future<void> load() async {
    state = _initial;
  }
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
  _FakePluralKitSyncNotifier? pluralKitSyncNotifier,
  PkSyncMode syncMode = PkSyncMode.fullSync,
  PkSyncDirection syncDirection = PkSyncDirection.pullOnly,
  FrontingListViewMode frontingListViewMode =
      FrontingListViewMode.combinedPeriods,
  List<FrontingSession> timelineSessions = const [],
  List<FrontingPeriod> derivedPeriods = const [],
}) {
  final memberRepo = FakeMemberRepository()..seed(members);
  final timelineRepo = FakeFrontingSessionRepository();
  timelineRepo.sessions.addAll(timelineSessions);
  final settings = SystemSettings(
    systemName: 'Test System',
    showQuickFront: showQuickFront,
    frontingListViewMode: frontingListViewMode,
    wakeSuggestionEnabled: false,
  );

  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => sleepNotifier),
      frontingNotifierProvider.overrideWith(() => frontingNotifier),
      activeSleepSessionProvider.overrideWith(
        (ref) => Stream.value(activeSleepSession),
      ),
      recentSleepSessionsPaginatedProvider.overrideWith(
        (ref, limit) => Stream.value(
          activeSleepSession == null
              ? const <FrontingSession>[]
              : [activeSleepSession],
        ),
      ),
      frontingSessionRepositoryProvider.overrideWithValue(timelineRepo),
      memberRepositoryProvider.overrideWithValue(memberRepo),
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
        (ref) => AsyncValue.data(derivedPeriods),
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
      pluralKitSyncProvider.overrideWith(
        () =>
            pluralKitSyncNotifier ??
            _FakePluralKitSyncNotifier(const PluralKitSyncState()),
      ),
      pkSyncModeProvider.overrideWith(
        () => _StaticPkSyncModeNotifier(syncMode),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _StaticPkSyncDirectionNotifier(syncDirection),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: PrismToastHost(child: FrontingScreen()),
    ),
  );
}

Finder _addButton() => find.byTooltip('Add fronting entry');

Finder _confirmSelectionButton() => find.byWidgetPredicate(
  (widget) => widget is PrismGlassIconButton && widget.icon == AppIcons.check,
);

Future<void> _tapWakeUpAs(WidgetTester tester) async {
  await tester.tap(find.text('Wake Up As...'));
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(PrismToast.resetForTest);

  group('FrontingScreen quick front header', () {
    testWidgets('timeline mode clamps the home app bar on wide layouts', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice')],
          frontingListViewMode: FrontingListViewMode.timeline,
          timelineSessions: [
            FrontingSession(
              id: 'session-1',
              memberId: 'm1',
              startTime: DateTime.now().subtract(const Duration(hours: 2)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final topBarRect = tester.getRect(find.byType(PrismTopBar).first);

      expect(topBarRect.width, lessThanOrEqualTo(PrismTokens.contentMaxWidth));
      expect(
        topBarRect.left,
        closeTo((1400 - PrismTokens.contentMaxWidth) / 2, 1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

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
      final quickFrontText = tester.widget<Text>(find.text('Quick Front'));
      final holdText = tester.widget<Text>(find.text('Press and hold'));
      final bodySmall = Theme.of(
        tester.element(find.text('Quick Front')),
      ).textTheme.bodySmall;
      expect(quickFrontText.style?.fontSize, bodySmall?.fontSize);
      expect(quickFrontText.style?.fontWeight, FontWeight.w400);
      expect(holdText.style?.fontSize, bodySmall?.fontSize);
      expect(holdText.style?.fontWeight, FontWeight.w400);
      final quickFrontSection = find.byType(QuickFrontSection);
      final sectionLeft = tester.getTopLeft(quickFrontSection).dx;
      final sectionWidth = tester.getSize(quickFrontSection).width;
      final slotWidth = sectionWidth / 4;
      final ringSize = slotWidth < quickFrontRingSize
          ? slotWidth
          : quickFrontRingSize;
      final circleInset = (slotWidth - ringSize) / 2;
      expect(
        tester.getTopLeft(find.text('Quick Front')).dx,
        closeTo(sectionLeft + circleInset, 0.1),
      );
      expect(
        tester.getTopRight(find.text('Press and hold')).dx,
        closeTo(sectionLeft + sectionWidth - circleInset, 0.1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('hides labels after quick-front hint was seen on this device', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        quickFrontHoldInstructionSeenPrefsKey: true,
      });

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice'), _member('m2', 'Bob')],
          showQuickFront: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick Front'), findsNothing);
      expect(find.text('Press and hold'), findsNothing);
      expect(find.byType(QuickFrontSection), findsOneWidget);

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

    testWidgets('PluralKit sync warning cancel prevents recent sync', (
      tester,
    ) async {
      final pkSync = _FakePluralKitSyncNotifier(
        PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
          lastSyncDate: DateTime(2024, 1, 1),
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(membersToDelete: 1),
      );

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice')],
          pluralKitSyncNotifier: pkSync,
          syncDirection: PkSyncDirection.bidirectional,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync with PluralKit'));
      await tester.pumpAndSettle();

      expect(pkSync.previewPendingDestructivePushCallCount, 1);
      expect(find.text('Sync may delete PluralKit data'), findsOneWidget);

      await tester.tap(find.text('Cancel Sync'));
      await tester.pumpAndSettle();

      expect(pkSync.syncRecentDataCallCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('PluralKit sync warning confirm runs recent sync', (
      tester,
    ) async {
      final pkSync = _FakePluralKitSyncNotifier(
        PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
          lastSyncDate: DateTime(2024, 1, 1),
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(switchesToDelete: 10),
      );

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice')],
          pluralKitSyncNotifier: pkSync,
          syncDirection: PkSyncDirection.bidirectional,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync with PluralKit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync Anyway'));
      await tester.pumpAndSettle();

      expect(pkSync.previewPendingDestructivePushCallCount, 1);
      expect(pkSync.syncRecentDataCallCount, 1);
      expect(pkSync.lastSyncDirection, PkSyncDirection.bidirectional);
      PrismToast.resetForTest();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('PluralKit menu sync uses live-fronts-only mode', (
      tester,
    ) async {
      final pkSync = _FakePluralKitSyncNotifier(
        const PluralKitSyncState(
          isConnected: true,
          directionConfirmed: true,
          mappingAcknowledged: true,
        ),
        deleteRiskPreview: const PkDeleteRiskPreview(membersToDelete: 1),
      );

      await tester.pumpWidget(
        _buildSubject(
          sleepNotifier: _FakeSleepNotifier(),
          frontingNotifier: _FakeFrontingNotifier(),
          members: [_member('m1', 'Alice')],
          pluralKitSyncNotifier: pkSync,
          syncMode: PkSyncMode.liveFrontsOnly,
          syncDirection: PkSyncDirection.pushOnly,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync with PluralKit'));
      await tester.pumpAndSettle();

      expect(pkSync.previewPendingDestructivePushCallCount, 0);
      expect(pkSync.syncRecentDataCallCount, 0);
      expect(pkSync.syncLiveFrontersOnlyCallCount, 1);
      expect(pkSync.lastSyncDirection, PkSyncDirection.pushOnly);
      PrismToast.resetForTest();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Wake Up As can start fronting as multiple members', (
      tester,
    ) async {
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
      await _tapWakeUpAs(tester);

      expect(find.byType(MemberSearchSheet), findsOneWidget);

      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
      await tester.tap(_confirmSelectionButton());
      await tester.pumpAndSettle();

      expect(sleep.endedIds, isEmpty);
      expect(fronting.startedIds, isEmpty);
      expect(fronting.wakeUps, hasLength(1));
      expect(fronting.wakeUps.single.sleepSessionId, 'sleep-1');
      expect(fronting.wakeUps.single.memberIds, ['m1', 'm2']);

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
      await _tapWakeUpAs(tester);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      expect(sleep.endedIds, isEmpty);
      expect(fronting.startedIds, isEmpty);
      expect(fronting.wakeUps, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Wake Up As can start fronting as Unknown', (tester) async {
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
      await _tapWakeUpAs(tester);

      await tester.tap(find.text('Unknown'));
      await tester.pumpAndSettle();
      await tester.tap(_confirmSelectionButton());
      await tester.pumpAndSettle();

      expect(sleep.endedIds, isEmpty);
      expect(fronting.startedIds, isEmpty);
      expect(fronting.wakeUps, hasLength(1));
      expect(fronting.wakeUps.single.sleepSessionId, 'sleep-1');
      expect(fronting.wakeUps.single.memberIds, [unknownSentinelMemberId]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
