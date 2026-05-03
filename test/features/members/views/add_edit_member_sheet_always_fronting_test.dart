import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

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
  Future<List<Member>> getAllMembers() async => [member];

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
  Future<({Member member, bool wasCreated})>
  ensureUnknownSentinelMember() async => (member: member, wasCreated: false);
}

Widget _harness({required Member member, required _FakeMemberRepository repo}) {
  return ProviderScope(
    overrides: [
      memberRepositoryProvider.overrideWithValue(repo),
      customFieldsProvider.overrideWithValue(const AsyncValue.data([])),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.members,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
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

void main() {
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
