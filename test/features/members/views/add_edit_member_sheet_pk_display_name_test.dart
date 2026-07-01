import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this.member);

  Member member;

  @override
  Future<void> createMember(Member member) async {
    this.member = member;
  }

  @override
  Future<void> updateMember(Member member) async {
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

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  _FakePluralKitSyncNotifier(this._state);

  final PluralKitSyncState _state;

  @override
  PluralKitSyncState build() => _state;
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _StaticPkSyncDirectionNotifier(this._direction);

  final PkSyncDirection _direction;

  @override
  PkSyncDirection build() => _direction;
}

Widget _harness({
  required Member member,
  required PluralKitSyncState pkState,
  required PkSyncDirection direction,
}) {
  final repo = _FakeMemberRepository(member);
  return ProviderScope(
    overrides: [
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
      pluralKitSyncProvider.overrideWith(
        () => _FakePluralKitSyncNotifier(pkState),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _StaticPkSyncDirectionNotifier(direction),
      ),
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

// An unlinked Prism-only member — same gate path as a new (null) member, but
// without the dispose-time `ref.read` that the new-member branch exercises.
// The fallback gate is the same.
Member _unlinkedMember() =>
    Member(id: 'm-1', name: 'Alice', createdAt: DateTime(2026, 1, 1));

void main() {
  testWidgets('hides PK display name on unlinked member when PK is disconnected', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _harness(
        member: _unlinkedMember(),
        pkState: const PluralKitSyncState(isConnected: false),
        direction: PkSyncDirection.bidirectional,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PluralKit Display Name'), findsNothing);
  });

  testWidgets(
    'hides PK display name on unlinked member when sync is pull-only',
    (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _harness(
          member: _unlinkedMember(),
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.pullOnly,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PluralKit Display Name'), findsNothing);
    },
  );

  testWidgets(
    'shows PK display name on unlinked member when sync is push-only',
    (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _harness(
          member: _unlinkedMember(),
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.pushOnly,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PluralKit Display Name'), findsOneWidget);
    },
  );

  testWidgets(
    'shows PK display name on unlinked member when sync is bidirectional',
    (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _harness(
          member: _unlinkedMember(),
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.bidirectional,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PluralKit Display Name'), findsOneWidget);
    },
  );

  testWidgets(
    'shows PK display name on a PK-linked member regardless of direction',
    (tester) async {
      _useTallViewport(tester);
      final member = Member(
        id: 'm-1',
        name: 'Alice',
        pluralkitId: 'abcde',
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        _harness(
          member: member,
          pkState: const PluralKitSyncState(isConnected: false),
          direction: PkSyncDirection.pullOnly,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PluralKit Display Name'), findsOneWidget);
    },
  );
}
