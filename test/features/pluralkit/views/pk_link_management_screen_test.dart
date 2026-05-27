import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_link_management_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

import '../../../helpers/fake_repositories.dart';

// ---------------------------------------------------------------------------
// Fake controller that lets tests stage state directly and intercept refresh().
// ---------------------------------------------------------------------------

class _FakePkLinkManagementController extends PkLinkManagementController {
  _FakePkLinkManagementController(this._initial);

  PkLinkManagementState _initial;
  int refreshCount = 0;

  @override
  Future<PkLinkManagementState> build() async => _initial;

  @override
  Future<void> refresh() async {
    refreshCount++;
    // Re-read the latest state from the repo so test asserts after exclude /
    // resume see the up-to-date sync_ignored flag without needing a real
    // network round trip.
    final repo = ref.read(memberRepositoryProvider);
    final members = await repo.getAllMembers();
    _initial = PkLinkManagementState(
      localMembers: members,
      pkMembers: _initial.pkMembers,
      isConnected: _initial.isConnected,
      fetchedPkUuids: _initial.fetchedPkUuids,
      fetchedPkIds: _initial.fetchedPkIds,
      pkMembersByUuid: _initial.pkMembersByUuid,
      pkMembersById: _initial.pkMembersById,
    );
    state = AsyncData(_initial);
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

domain.Member _local(
  String id,
  String name, {
  String? pkUuid,
  String? pkId,
  String? pkDisplayName,
  bool excluded = false,
}) =>
    domain.Member(
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

PkLinkManagementState _state({
  required List<domain.Member> locals,
  List<PKMember> pkMembers = const [],
  bool isConnected = true,
}) {
  final uuids = {for (final pk in pkMembers) pk.uuid};
  final ids = {for (final pk in pkMembers) pk.id};
  return PkLinkManagementState(
    localMembers: locals,
    pkMembers: pkMembers,
    isConnected: isConnected,
    fetchedPkUuids: isConnected ? uuids : const {},
    fetchedPkIds: isConnected ? ids : const {},
    pkMembersByUuid: isConnected
        ? {for (final pk in pkMembers) pk.uuid: pk}
        : const {},
    pkMembersById:
        isConnected ? {for (final pk in pkMembers) pk.id: pk} : const {},
  );
}

Widget _wrap({
  required _FakePkLinkManagementController controller,
  required FakeMemberRepository repo,
}) {
  return ProviderScope(
    overrides: [
      memberRepositoryProvider.overrideWithValue(repo),
      pkLinkManagementControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      // PrismToastHost is required for any test that asserts toast copy —
      // PrismToast.show is a no-op without the host overlay in the tree.
      builder: (context, child) =>
          PrismToastHost(child: child ?? const SizedBox.shrink()),
      home: const PkLinkManagementScreen(),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PkLinkManagementScreen — bucketing', () {
    testWidgets(
      'renders Synced / Excluded / Unresolved sections with the right rows',
      (tester) async {
        _useTallViewport(tester);
        // Alice — synced (PK fields resolve, not excluded).
        // Bob — excluded.
        // Carol — unresolved (PK fields set, don't resolve, not excluded).
        // Dana — unlinked Prism-only (should NOT appear in any section).
        final pkAlice = _pk('pk-alice', 'Alice');
        final locals = [
          _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid'),
          _local('l-bob', 'Bob', pkUuid: 'pk-bob', excluded: true),
          _local('l-carol', 'Carol', pkId: 'stale'),
          _local('l-dana', 'Dana'),
        ];

        final repo = FakeMemberRepository()..seed(locals);
        final controller = _FakePkLinkManagementController(
          _state(locals: locals, pkMembers: [pkAlice]),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        // Section headers.
        expect(find.text('Synced with PluralKit'), findsOneWidget);
        expect(find.text('Excluded from sync'), findsOneWidget);
        expect(find.text('Unresolved links'), findsOneWidget);

        // Alice in Synced.
        expect(
          find.byKey(const ValueKey('pkLinkManagementSyncedRow-l-alice')),
          findsOneWidget,
        );
        // Bob in Excluded.
        expect(
          find.byKey(const ValueKey('pkLinkManagementExcludedRow-l-bob')),
          findsOneWidget,
        );
        // Carol in Unresolved.
        expect(
          find.byKey(const ValueKey('pkLinkManagementUnresolvedRow-l-carol')),
          findsOneWidget,
        );
        // Dana — Prism-only — NOT in any of the three sections.
        expect(
          find.byKey(const ValueKey('pkLinkManagementSyncedRow-l-dana')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('pkLinkManagementExcludedRow-l-dana')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('pkLinkManagementUnresolvedRow-l-dana')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'empty state shows when no section has rows',
      (tester) async {
        _useTallViewport(tester);
        // Only a Prism-only member — none of the three sections render.
        final locals = [_local('l-dana', 'Dana')];

        final repo = FakeMemberRepository()..seed(locals);
        final controller = _FakePkLinkManagementController(
          _state(locals: locals, pkMembers: const []),
        );
        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        // pkMappingEmptyTitle is reused per plan's empty-state copy.
        expect(find.textContaining('Nothing to map'), findsOneWidget);
      },
    );
  });

  group('PkLinkManagementScreen — actions', () {
    testWidgets(
      'Exclude tap on a synced row calls excludePluralKitSync',
      (tester) async {
        _useTallViewport(tester);
        final pkAlice = _pk('pk-alice', 'Alice');
        final alice =
            _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
        final repo = FakeMemberRepository()..seed([alice]);
        final controller = _FakePkLinkManagementController(
          _state(locals: [alice], pkMembers: [pkAlice]),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('pkLinkManagementExcludeButton-l-alice')),
        );
        await tester.pumpAndSettle();

        // The fake repo flips sync_ignored true; verify via repo state.
        final after = await repo.getMemberById('l-alice');
        expect(after, isNotNull);
        expect(after!.pluralkitSyncIgnored, isTrue);
        expect(
          controller.refreshCount,
          greaterThanOrEqualTo(1),
          reason: 'screen refreshes after the exclude write',
        );
      },
    );

    testWidgets(
      'Resume tap on an excluded row calls resumePluralKitSync',
      (tester) async {
        _useTallViewport(tester);
        final bob = _local('l-bob', 'Bob', pkUuid: 'pk-bob', excluded: true);
        final repo = FakeMemberRepository()..seed([bob]);
        final controller = _FakePkLinkManagementController(
          _state(locals: [bob], pkMembers: const []),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('pkLinkManagementResumeButton-l-bob')),
        );
        await tester.pumpAndSettle();

        final after = await repo.getMemberById('l-bob');
        expect(after, isNotNull);
        expect(after!.pluralkitSyncIgnored, isFalse);
        expect(controller.refreshCount, greaterThanOrEqualTo(1));
      },
    );
  });

  group('PkLinkManagementScreen — offline edge case', () {
    testWidgets(
      'offline hides Unresolved section and disables Link/Refresh actions',
      (tester) async {
        _useTallViewport(tester);
        // Locals: one synced (would normally resolve), one excluded, one
        // unresolved-link. Offline means we cannot run the resolve check at
        // all — Unresolved is hidden and the Synced row falls back to the
        // "Linked (offline)" caption.
        final locals = [
          _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid'),
          _local('l-bob', 'Bob', pkUuid: 'pk-bob', excluded: true),
          _local('l-carol', 'Carol', pkId: 'stale'),
        ];

        final repo = FakeMemberRepository()..seed(locals);
        final controller = _FakePkLinkManagementController(
          _state(locals: locals, isConnected: false),
        );
        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        // Unresolved section header is gone.
        expect(find.text('Unresolved links'), findsNothing);
        // Synced row exists but with offline caption.
        expect(find.text('Linked (offline)'), findsAtLeastNWidgets(1));

        // Refresh / Add link buttons are disabled.
        final refreshButton = tester.widget<PrismButton>(
          find.widgetWithText(PrismButton, 'Refresh from PluralKit'),
        );
        expect(refreshButton.enabled, isFalse);

        final addLinkButton = tester.widget<PrismButton>(
          find.byKey(const ValueKey('pkLinkManagementAddLinkButton')),
        );
        expect(addLinkButton.enabled, isFalse);
      },
    );
  });

  group('PkLinkManagementScreen — search labels', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('search label for a Prism-only local is "Not linked"', () {
      final m = _local('m', 'Mira');
      final label = pkLinkManagementSearchLabelFor(l10n, m);
      expect(label, 'Not linked');
    });

    test(
      'search label for an excluded-linked local with PK fetch returns '
      '"Excluded — was linked to <pkName>"',
      () {
        final pkAlice = _pk('pk-alice', 'Alice');
        final state = _state(
          locals: const [],
          pkMembers: [pkAlice],
        );
        final m = _local(
          'm',
          'Excluded Alice',
          pkUuid: 'pk-alice',
          excluded: true,
        );
        final label = pkLinkManagementSearchLabelFor(l10n, m, state: state);
        expect(label, 'Excluded — was linked to Alice');
      },
    );

    test(
      'search label for an unresolved-link local returns the '
      '"Linked to <pkId> (not in current system)" form',
      () {
        final m = _local('m', 'Carol', pkId: 'stale');
        final label = pkLinkManagementSearchLabelFor(l10n, m);
        expect(label, 'Linked to stale (not in current system)');
      },
    );

    test(
      'search label for a resolved synced local returns "Linked to <pkName>"',
      () {
        final pkAlice = _pk('pk-alice', 'Alice');
        final state = _state(locals: const [], pkMembers: [pkAlice]);
        final m = _local('m', 'Alice', pkUuid: 'pk-alice');
        final label = pkLinkManagementSearchLabelFor(l10n, m, state: state);
        expect(label, 'Linked to Alice');
      },
    );
  });

  group('PkLinkManagementScreen — Change link on Synced rows', () {
    testWidgets(
      'Synced row renders both Change link and Exclude buttons',
      (tester) async {
        _useTallViewport(tester);
        final pkAlice = _pk('pk-alice', 'Alice');
        // Add an unmapped PK candidate so Change link is enabled.
        final pkSpare = _pk('pk-spare', 'Spare');
        final alice =
            _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
        final repo = FakeMemberRepository()..seed([alice]);
        final controller = _FakePkLinkManagementController(
          _state(locals: [alice], pkMembers: [pkAlice, pkSpare]),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        final changeLink = tester.widget<PrismButton>(
          find.byKey(
            const ValueKey('pkLinkManagementChangeLinkButton-l-alice'),
          ),
        );
        expect(changeLink.enabled, isTrue);
        expect(changeLink.label, 'Change link');

        // Exclude button remains under the same key as before.
        expect(
          find.byKey(const ValueKey('pkLinkManagementExcludeButton-l-alice')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Change link is disabled when offline (isConnected: false)',
      (tester) async {
        _useTallViewport(tester);
        final alice =
            _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
        final repo = FakeMemberRepository()..seed([alice]);
        final controller = _FakePkLinkManagementController(
          _state(locals: [alice], isConnected: false),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        final changeLink = tester.widget<PrismButton>(
          find.byKey(
            const ValueKey('pkLinkManagementChangeLinkButton-l-alice'),
          ),
        );
        expect(changeLink.enabled, isFalse);
      },
    );

    testWidgets(
      'Change link is disabled on fetch error (isConnected: true, fetchError set)',
      (tester) async {
        _useTallViewport(tester);
        final pkAlice = _pk('pk-alice', 'Alice');
        final alice =
            _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
        final repo = FakeMemberRepository()..seed([alice]);
        // Build state directly so we can set fetchError — the _state() helper
        // doesn't expose it. isConnected stays true so the Synced row still
        // renders (Synced bucketing falls back to hasPluralKitLink when
        // isConnected resolves to "offline" via fetchError). hasFreshFetch
        // returns false because fetchError != null, which is what gates
        // onChangeLink in the parent.
        final pkUuids = {pkAlice.uuid};
        final pkIds = {pkAlice.id};
        final controller = _FakePkLinkManagementController(
          PkLinkManagementState(
            localMembers: [alice],
            pkMembers: const [],
            isConnected: true,
            fetchedPkUuids: pkUuids,
            fetchedPkIds: pkIds,
            pkMembersByUuid: {pkAlice.uuid: pkAlice},
            pkMembersById: {pkAlice.id: pkAlice},
            fetchError: Exception('boom'),
          ),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        final changeLink = tester.widget<PrismButton>(
          find.byKey(
            const ValueKey('pkLinkManagementChangeLinkButton-l-alice'),
          ),
        );
        expect(changeLink.enabled, isFalse);
      },
    );

    testWidgets(
      'tap → empty unmapped roster shows the no-candidates toast',
      (tester) async {
        _useTallViewport(tester);
        addTearDown(PrismToast.resetForTest);
        // Synced local + the only PK member is the one it's already linked to,
        // so unmappedPkMembers is empty. Tap Change link must short-circuit
        // to a toast before the picker opens.
        final pkAlice = _pk('pk-alice', 'Alice');
        final alice =
            _local('l-alice', 'Alice', pkUuid: 'pk-alice', pkId: 'aliceid');
        final repo = FakeMemberRepository()..seed([alice]);
        final controller = _FakePkLinkManagementController(
          _state(locals: [alice], pkMembers: [pkAlice]),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey('pkLinkManagementChangeLinkButton-l-alice'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.textContaining('No unmapped PluralKit members'),
          findsOneWidget,
        );

        PrismToast.dismiss();
        await tester.pump();
      },
    );

    testWidgets(
      'tap → pick PK target → confirm dialog renders with both names; '
      'cancel keeps the link unchanged',
      (tester) async {
        _useTallViewport(tester);
        final pkAlice = _pk('pk-alice', 'Alice');
        final pkSpare = _pk('pk-spare', 'Spare', displayName: 'Spare Display');
        final alice = _local(
          'l-alice',
          'Alice',
          pkUuid: 'pk-alice',
          pkId: 'aliceid',
        );
        final repo = FakeMemberRepository()..seed([alice]);
        final controller = _FakePkLinkManagementController(
          _state(locals: [alice], pkMembers: [pkAlice, pkSpare]),
        );

        await tester.pumpWidget(_wrap(controller: controller, repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey('pkLinkManagementChangeLinkButton-l-alice'),
          ),
        );
        await tester.pumpAndSettle();

        // Picker shows the unmapped PK member (Spare). Can't usefully assert
        // that Alice (the currently-linked PK) is *absent* — the local's
        // own name is also 'Alice' and stays in the tree under the picker
        // scrim. The exclusion happens at the state level via
        // unmappedPkMembers; trust that and move on.
        expect(find.text('Spare Display'), findsAtLeastNWidgets(1));

        await tester.tap(find.text('Spare Display').first);
        await tester.pumpAndSettle();

        // Confirm dialog names both sides — title mentions the local, body
        // mentions the current PK member (Alice).
        expect(
          find.text('Change PluralKit link for Alice?'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Currently linked to Alice'),
          findsOneWidget,
        );

        // Cancel — repo state must not change.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final after = await repo.getMemberById('l-alice');
        expect(after?.pluralkitUuid, 'pk-alice');
        expect(after?.pluralkitId, 'aliceid');
      },
    );

    // The full picker → confirm → apply tap-through (verifying the repo
    // write lands) wedges this harness: pumpAndSettle never returns after
    // the apply emits PrismToast.success + PluralKitSyncService runs through
    // its post-link metadata pull. The applier path itself — including
    // applyPluralKitLink's overwrite semantics on a Synced local — is
    // already covered end-to-end by test/features/pluralkit/pk_e2e_mapping
    // _flow_test.dart, which drives the same PkLinkDecision through a
    // ProviderContainer directly (no widget tree). What the widget tests
    // above cover is everything up to and including the confirm-or-cancel
    // decision; the confirm → apply edge is exercised by the integration
    // suite.
  });
}
