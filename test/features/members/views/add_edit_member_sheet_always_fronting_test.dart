import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

import '../../../helpers/fake_repositories.dart';

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this.member);

  Member member;
  Member? updated;

  @override
  Future<void> createMember(Member member) async {
    this.member = member;
  }

  @override
  Future<void> updateMember(Member member) async {
    updated = member;
    this.member = member;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> excludePluralKitSync(String id) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> resumePluralKitSync(String id) async => throw UnimplementedError();

  @override
  Future<List<Member>> getAllMembers() async => [member];

  @override
  Future<List<Member>> getAllMembersIncludingDeleted() async => [member];

  @override
  Stream<List<Member>> watchAllMembers() => Stream.value([member]);

  @override
  Stream<List<Member>> watchActiveMembers() => Stream.value([member]);

  @override
  Future<Member?> getMemberById(String id) async =>
      id == member.id ? member : null;

  @override
  Stream<Member?> watchMemberById(String id) =>
      Stream.value(id == member.id ? member : null);

  @override
  Future<void> deleteMember(String id) async {}

  @override
  Future<List<Member>> getMembersByIds(List<String> ids) async =>
      ids.contains(member.id) ? [member] : [];

  @override
  Stream<List<Member>> watchMembersByIds(List<String> ids) =>
      Stream.value(ids.contains(member.id) ? [member] : []);

  @override
  Future<int> getCount() async => 1;

  @override
  Future<List<Member>> getDeletedLinkedMembers() async => const [];

  @override
  Future<void> clearPluralKitLink(String id) async {}

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> stampCreatePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> clearCreatePushStartedAt(String id) async {}

  @override
  Future<({Member member, bool wasCreated})>
  ensureUnknownSentinelMember() async => (member: member, wasCreated: false);
}

Widget _harness({
  required Member member,
  required _FakeMemberRepository repo,
  FakeFrontingSessionRepository? frontingRepo,
}) {
  return ProviderScope(
    overrides: [
      // §4 verifiedStartupKeyProvider throws by default; widget tests don't
      // run the boot probe.
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      memberRepositoryProvider.overrideWithValue(repo),
      frontingSessionRepositoryProvider.overrideWithValue(
        frontingRepo ?? FakeFrontingSessionRepository(),
      ),
      customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.members,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
      memberNamePreferDisplayProvider.overrideWithValue(false),
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

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 50),
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (tester.binding.clock.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(step);
  }
  expect(condition(), isTrue);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) {
  return _pumpUntil(tester, () => finder.evaluate().isNotEmpty);
}

void main() {
  testWidgets('clearing emoji persists a blank member emoji on save', (
    tester,
  ) async {
    _useTallViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      emoji: '🌸',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);

    await tester.pumpWidget(_harness(member: member, repo: repo));
    await tester.pumpAndSettle();

    final clearEmoji = find.byTooltip('Clear emoji');
    expect(clearEmoji, findsOneWidget);

    await tester.tap(clearEmoji);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    expect(repo.updated?.emoji, isEmpty);
  });

  testWidgets('toggling off persists isAlwaysFronting=false on save', (
    tester,
  ) async {
    _useTallViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      isAlwaysFronting: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);

    await tester.pumpWidget(_harness(member: member, repo: repo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Always fronting'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    // Initial value reflects the seeded `isAlwaysFronting: true`.
    expect(
      tester
          .widget<PrismSwitchRow>(
            find.widgetWithText(PrismSwitchRow, 'Always fronting'),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    expect(repo.updated?.isAlwaysFronting, isFalse);
  });

  testWidgets(
    'asks before ending the active front when always fronting is turned off',
    (tester) async {
      _useTallViewport(tester);

      final member = Member(
        id: 'm-1',
        name: 'Alice',
        isAlwaysFronting: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = _FakeMemberRepository(member);
      final frontingRepo = FakeFrontingSessionRepository();
      await frontingRepo.createSession(
        FrontingSession(
          id: 'front-1',
          startTime: DateTime(2026, 1, 1, 12),
          memberId: 'm-1',
        ),
      );

      await tester.pumpWidget(
        _harness(member: member, repo: repo, frontingRepo: frontingRepo),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Always fronting'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save member'));
      await _pumpUntilFound(tester, find.text('End current front?'));

      expect(find.text('End current front?'), findsOneWidget);

      await tester.tap(find.text('Keep fronting'));
      await _pumpUntil(tester, () => repo.updated != null);
      // Drain the deferred bio-image orphan-reconcile timer that _save()
      // schedules via Future.delayed; otherwise it outlives the widget tree
      // and trips the pending-timer assertion at teardown.
      await tester.pumpAndSettle();

      expect(repo.updated?.isAlwaysFronting, isFalse);
      expect((await frontingRepo.getSessionById('front-1'))?.endTime, isNull);
    },
  );

  testWidgets(
    'canceling the always-fronting prompt leaves the front unchanged',
    (tester) async {
      _useTallViewport(tester);

      final member = Member(
        id: 'm-1',
        name: 'Alice',
        isAlwaysFronting: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = _FakeMemberRepository(member);
      final frontingRepo = FakeFrontingSessionRepository();
      await frontingRepo.createSession(
        FrontingSession(
          id: 'front-1',
          startTime: DateTime(2026, 1, 1, 12),
          memberId: 'm-1',
        ),
      );

      await tester.pumpWidget(
        _harness(member: member, repo: repo, frontingRepo: frontingRepo),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Always fronting'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save member'));
      await _pumpUntilFound(tester, find.text('End current front?'));

      await tester.tap(find.text('Cancel'));
      await _pumpUntil(
        tester,
        () => find.text('End current front?').evaluate().isEmpty,
      );

      expect(repo.updated, isNull);
      expect((await frontingRepo.getSessionById('front-1'))?.endTime, isNull);
    },
  );

  testWidgets('double-tapping save only opens one always-fronting prompt', (
    tester,
  ) async {
    _useTallViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      isAlwaysFronting: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);
    final frontingRepo = FakeFrontingSessionRepository();
    await frontingRepo.createSession(
      FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 1, 1, 12),
        memberId: 'm-1',
      ),
    );

    await tester.pumpWidget(
      _harness(member: member, repo: repo, frontingRepo: frontingRepo),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Always fronting'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save member'));
    await tester.tap(find.byTooltip('Save member'));
    await _pumpUntilFound(tester, find.text('End current front?'));

    expect(find.text('End current front?'), findsOneWidget);

    await tester.tap(find.text('Keep fronting'));
    await _pumpUntil(tester, () => repo.updated != null);
    // Drain the deferred bio-image orphan-reconcile timer that _save()
    // schedules via Future.delayed; otherwise it outlives the widget tree
    // and trips the pending-timer assertion at teardown.
    await tester.pumpAndSettle();

    expect(repo.updated?.isAlwaysFronting, isFalse);
    expect((await frontingRepo.getSessionById('front-1'))?.endTime, isNull);
  });

  testWidgets('can end the active front from the always-fronting prompt', (
    tester,
  ) async {
    _useTallViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      isAlwaysFronting: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);
    final frontingRepo = FakeFrontingSessionRepository();
    await frontingRepo.createSession(
      FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 1, 1, 12),
        memberId: 'm-1',
      ),
    );

    await tester.pumpWidget(
      _harness(member: member, repo: repo, frontingRepo: frontingRepo),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Always fronting'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save member'));
    await _pumpUntilFound(tester, find.text('End current front?'));

    await tester.tap(find.text('End front'));
    await _pumpUntil(tester, () => repo.updated != null);
    // Drain the deferred bio-image orphan-reconcile timer that _save()
    // schedules via Future.delayed; otherwise it outlives the widget tree
    // and trips the pending-timer assertion at teardown.
    await tester.pumpAndSettle();

    expect(repo.updated?.isAlwaysFronting, isFalse);
    expect((await frontingRepo.getSessionById('front-1'))?.endTime, isNotNull);
  });

  testWidgets('end prompt only ends the front that triggered the prompt', (
    tester,
  ) async {
    _useTallViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      isAlwaysFronting: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);
    final frontingRepo = FakeFrontingSessionRepository();
    await frontingRepo.createSession(
      FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 1, 1, 12),
        memberId: 'm-1',
      ),
    );

    await tester.pumpWidget(
      _harness(member: member, repo: repo, frontingRepo: frontingRepo),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Always fronting'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save member'));
    await _pumpUntilFound(tester, find.text('End current front?'));

    await frontingRepo.createSession(
      FrontingSession(
        id: 'front-2',
        startTime: DateTime(2026, 1, 1, 12, 30),
        memberId: 'm-1',
      ),
    );

    await tester.tap(find.text('End front'));
    await _pumpUntil(tester, () => repo.updated != null);
    // Drain the deferred bio-image orphan-reconcile timer that _save()
    // schedules via Future.delayed; otherwise it outlives the widget tree
    // and trips the pending-timer assertion at teardown.
    await tester.pumpAndSettle();

    expect(repo.updated?.isAlwaysFronting, isFalse);
    expect((await frontingRepo.getSessionById('front-1'))?.endTime, isNotNull);
    expect((await frontingRepo.getSessionById('front-2'))?.endTime, isNull);
  });

  testWidgets('toggling on persists isAlwaysFronting=true on save', (
    tester,
  ) async {
    _useTallViewport(tester);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);

    await tester.pumpWidget(_harness(member: member, repo: repo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Always fronting'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<PrismSwitchRow>(
            find.widgetWithText(PrismSwitchRow, 'Always fronting'),
          )
          .value,
      isFalse,
    );

    await tester.tap(find.widgetWithText(PrismSwitchRow, 'Always fronting'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    expect(repo.updated?.isAlwaysFronting, isTrue);
  });
}
