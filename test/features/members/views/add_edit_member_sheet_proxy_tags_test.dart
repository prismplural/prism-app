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
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

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

Finder _prismField(String label) => find.byWidgetPredicate(
  (widget) => widget is PrismTextField && widget.labelText == label,
);

void main() {
  testWidgets('saves locally added proxy tags on a member', (tester) async {
    final member = Member(
      id: 'm-1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);

    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Proxy Tags'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(PrismButton, 'Add proxy tag'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: _prismField('Prefix'),
        matching: find.byType(EditableText),
      ),
      'A:',
    );

    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    expect(repo.updated?.proxyTagsJson, '[{"prefix":"A:","suffix":null}]');
  });

  testWidgets('saves an explicit empty list when existing tags are removed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = _FakeMemberRepository(member);

    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Proxy Tags'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byTooltip('Remove proxy tag'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -40));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove proxy tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    expect(repo.updated?.proxyTagsJson, '[]');
  });
}
