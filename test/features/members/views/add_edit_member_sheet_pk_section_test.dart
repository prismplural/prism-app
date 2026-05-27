import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_link_management_screen.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

// ---------------------------------------------------------------------------
// Test plumbing
// ---------------------------------------------------------------------------

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

/// Fake [PkLinkManagementController] that lets tests stage the link-management
/// screen's PK fetch snapshot — the editor sheet's PluralKit section watches
/// this provider to render the right summary copy.
class _FakePkLinkManagementController extends PkLinkManagementController {
  _FakePkLinkManagementController(this._state);
  final PkLinkManagementState _state;
  @override
  Future<PkLinkManagementState> build() async => _state;
  @override
  Future<void> refresh() async {
    state = AsyncData(_state);
  }
}

PkLinkManagementState _state({
  required List<Member> locals,
  List<PKMember> pkMembers = const [],
  bool isConnected = true,
}) =>
    PkLinkManagementState(
      localMembers: locals,
      pkMembers: pkMembers,
      isConnected: isConnected,
      fetchedPkUuids:
          isConnected ? {for (final pk in pkMembers) pk.uuid} : const {},
      fetchedPkIds: isConnected ? {for (final pk in pkMembers) pk.id} : const {},
      pkMembersByUuid: isConnected
          ? {for (final pk in pkMembers) pk.uuid: pk}
          : const {},
      pkMembersById:
          isConnected ? {for (final pk in pkMembers) pk.id: pk} : const {},
    );

Widget _harness({
  required Member member,
  required PluralKitSyncState pkState,
  required PkSyncDirection direction,
  required MemberRepository repo,
  PkLinkManagementState? managementState,
}) {
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
      if (managementState != null)
        pkLinkManagementControllerProvider.overrideWith(
          () => _FakePkLinkManagementController(managementState),
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
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Member _seed(
  String id,
  String name, {
  String? pkUuid,
  String? pkId,
  String? pkDisplayName,
  bool excluded = false,
}) =>
    Member(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      pluralkitUuid: pkUuid,
      pluralkitId: pkId,
      pluralkitDisplayName: pkDisplayName,
      pluralkitSyncIgnored: excluded,
    );

PKMember _pk(String uuid, String name, {String? id, String? displayName}) =>
    PKMember(
      id: id ?? uuid.substring(0, 5),
      uuid: uuid,
      name: name,
      displayName: displayName,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('add_edit_member_sheet PluralKit section — visibility', () {
    testWidgets(
      'hidden when member has no PK fields, not excluded, and PK is offline',
      (tester) async {
        _useTallViewport(tester);
        final m = _seed('m-1', 'Alice');
        final repo = FakeMemberRepository()..seed([m]);
        await tester.pumpWidget(_harness(
          member: m,
          pkState: const PluralKitSyncState(isConnected: false),
          direction: PkSyncDirection.bidirectional,
          repo: repo,
        ));
        await tester.pumpAndSettle();

        expect(find.text('PluralKit'), findsNothing);
        expect(find.text('Not linked'), findsNothing);
      },
    );

    testWidgets(
      'visible when member is excluded even if no PK fields are present',
      (tester) async {
        _useTallViewport(tester);
        final m = _seed('m-1', 'Alice', excluded: true);
        final repo = FakeMemberRepository()..seed([m]);
        await tester.pumpWidget(_harness(
          member: m,
          pkState: const PluralKitSyncState(isConnected: false),
          direction: PkSyncDirection.bidirectional,
          repo: repo,
          managementState: _state(locals: [m], isConnected: false),
        ));
        await tester.pumpAndSettle();

        expect(find.text('PluralKit'), findsOneWidget);
        expect(find.text('Excluded from sync — not linked'), findsOneWidget);
      },
    );

    testWidgets(
      'visible when PK is connected and push is enabled (even on a new member)',
      (tester) async {
        _useTallViewport(tester);
        final m = _seed('m-1', 'Alice');
        final repo = FakeMemberRepository()..seed([m]);
        await tester.pumpWidget(_harness(
          member: m,
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.bidirectional,
          repo: repo,
          managementState: _state(locals: [m]),
        ));
        await tester.pumpAndSettle();

        expect(find.text('PluralKit'), findsOneWidget);
        expect(find.text('Not linked'), findsOneWidget);
      },
    );
  });

  group('add_edit_member_sheet PluralKit section — summary states', () {
    testWidgets('Linked as <pkName> (resolved)', (tester) async {
      _useTallViewport(tester);
      final pk = _pk('pk-alice', 'Alice', displayName: 'PK Alice');
      final m = _seed('m-1', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
      final repo = FakeMemberRepository()..seed([m]);
      await tester.pumpWidget(_harness(
        member: m,
        pkState: const PluralKitSyncState(isConnected: true),
        direction: PkSyncDirection.bidirectional,
        repo: repo,
        managementState: _state(locals: [m], pkMembers: [pk]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Linked as PK Alice'), findsOneWidget);
      expect(find.text('Exclude from PluralKit sync'), findsOneWidget);
    });

    testWidgets('Linked to <pkId> (unresolved, not excluded)', (tester) async {
      _useTallViewport(tester);
      final m = _seed('m-1', 'Carol', pkId: 'stale');
      final repo = FakeMemberRepository()..seed([m]);
      await tester.pumpWidget(_harness(
        member: m,
        pkState: const PluralKitSyncState(isConnected: true),
        direction: PkSyncDirection.bidirectional,
        repo: repo,
        managementState: _state(locals: [m]),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Linked to stale (not in your current PluralKit system)',
        ),
        findsOneWidget,
      );
      expect(find.text('Exclude from PluralKit sync'), findsOneWidget);
    });

    testWidgets('Excluded — was linked as <pkName>', (tester) async {
      _useTallViewport(tester);
      final pk = _pk('pk-bob', 'Bob');
      final m = _seed(
        'm-1',
        'Bob',
        pkUuid: 'pk-bob',
        pkId: 'bobid',
        excluded: true,
      );
      final repo = FakeMemberRepository()..seed([m]);
      await tester.pumpWidget(_harness(
        member: m,
        pkState: const PluralKitSyncState(isConnected: true),
        direction: PkSyncDirection.bidirectional,
        repo: repo,
        managementState: _state(locals: [m], pkMembers: [pk]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Excluded from sync — was linked as Bob'), findsOneWidget);
      expect(find.text('Resume PluralKit sync'), findsOneWidget);
    });

    testWidgets('Excluded — was linked to <pkId> (unresolved)', (tester) async {
      _useTallViewport(tester);
      final m = _seed(
        'm-1',
        'Stale Bob',
        pkId: 'oldid',
        excluded: true,
      );
      final repo = FakeMemberRepository()..seed([m]);
      await tester.pumpWidget(_harness(
        member: m,
        pkState: const PluralKitSyncState(isConnected: true),
        direction: PkSyncDirection.bidirectional,
        repo: repo,
        managementState: _state(locals: [m]),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Excluded from sync — was linked to oldid (not in current system)'),
        findsOneWidget,
      );
      expect(find.text('Resume PluralKit sync'), findsOneWidget);
    });

    testWidgets('Excluded — not linked', (tester) async {
      _useTallViewport(tester);
      final m = _seed('m-1', 'Lonely', excluded: true);
      final repo = FakeMemberRepository()..seed([m]);
      await tester.pumpWidget(_harness(
        member: m,
        pkState: const PluralKitSyncState(isConnected: true),
        direction: PkSyncDirection.bidirectional,
        repo: repo,
        managementState: _state(locals: [m]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Excluded from sync — not linked'), findsOneWidget);
      expect(find.text('Resume PluralKit sync'), findsOneWidget);
    });

    testWidgets(
      'Not linked — connected + push: shows Link button',
      (tester) async {
        _useTallViewport(tester);
        final m = _seed('m-1', 'Mira');
        final repo = FakeMemberRepository()..seed([m]);
        await tester.pumpWidget(_harness(
          member: m,
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.bidirectional,
          repo: repo,
          managementState: _state(locals: [m]),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Not linked'), findsOneWidget);
        expect(find.text('Link to PluralKit member…'), findsOneWidget);
      },
    );
  });

  group('add_edit_member_sheet PluralKit section — actions', () {
    testWidgets(
      'Exclude tap calls excludePluralKitSync via the repo',
      (tester) async {
        _useTallViewport(tester);
        final pk = _pk('pk-alice', 'Alice');
        final m = _seed('m-1', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
        final repo = FakeMemberRepository()..seed([m]);
        await tester.pumpWidget(_harness(
          member: m,
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.bidirectional,
          repo: repo,
          managementState: _state(locals: [m], pkMembers: [pk]),
        ));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('memberEditorPluralKitExcludeButton')),
        );
        await tester.pumpAndSettle();

        final after = await repo.getMemberById('m-1');
        expect(after, isNotNull);
        expect(after!.pluralkitSyncIgnored, isTrue);
      },
    );

    testWidgets(
      'Resume tap calls resumePluralKitSync via the repo',
      (tester) async {
        _useTallViewport(tester);
        final m = _seed('m-1', 'Bob', pkUuid: 'pk-bob', excluded: true);
        final repo = FakeMemberRepository()..seed([m]);
        await tester.pumpWidget(_harness(
          member: m,
          pkState: const PluralKitSyncState(isConnected: true),
          direction: PkSyncDirection.bidirectional,
          repo: repo,
          managementState: _state(locals: [m]),
        ));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('memberEditorPluralKitResumeButton')),
        );
        await tester.pumpAndSettle();

        final after = await repo.getMemberById('m-1');
        expect(after, isNotNull);
        expect(after!.pluralkitSyncIgnored, isFalse);
      },
    );
  });

  group(
    'add_edit_member_sheet PluralKit display name field on excluded members',
    () {
      testWidgets(
        'is rendered and accepts edits even when the member is excluded '
        '(Rule A does not strip pluralkit_display_name)',
        (tester) async {
          _useTallViewport(tester);
          // The field is gated by the existing _showPluralKitDisplayNameField
          // which is true when the member already carries any PK field —
          // including pluralkitDisplayName. Render with an excluded member
          // that carries a PK display name and verify the editor field is
          // visible. The save path uses the existing generic updateMember
          // which Part 1.6 Rule A intentionally leaves alone for this field.
          final m = _seed(
            'm-1',
            'Excluded Bob',
            pkUuid: 'pk-bob',
            pkDisplayName: 'Bobby',
            excluded: true,
          );
          final repo = FakeMemberRepository()..seed([m]);
          await tester.pumpWidget(_harness(
            member: m,
            pkState: const PluralKitSyncState(isConnected: true),
            direction: PkSyncDirection.bidirectional,
            repo: repo,
            managementState: _state(locals: [m]),
          ));
          await tester.pumpAndSettle();

          // The field is the existing labeled "PluralKit Display Name" — same
          // as the rest of the pk_display_name_test.
          expect(find.text('PluralKit Display Name'), findsOneWidget);
          // Editor field should be populated with the existing PK display
          // name (rendered as a text field's text rather than a label).
          expect(find.text('Bobby'), findsOneWidget);
        },
      );
    },
  );
}
