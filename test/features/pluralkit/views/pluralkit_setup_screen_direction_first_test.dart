import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_current_fronters_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_first_sync_deferred_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/views/pluralkit_setup_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

import '../../../helpers/fake_repositories.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSyncNotifier extends PluralKitSyncNotifier {
  _FakeSyncNotifier(this._initial);

  final PluralKitSyncState _initial;
  int confirmDirectionCallCount = 0;

  @override
  PluralKitSyncState build() => _initial;

  @override
  Future<void> confirmDirection() async {
    confirmDirectionCallCount++;
    // Transition: confirmed direction → needsMapping
    state = state.copyWith(directionConfirmed: true);
  }

  @override
  Future<void> setToken(String token) async {
    state = state.copyWith(isConnected: true);
  }

  @override
  Future<void> performFullImport() async {}

  @override
  Future<PkDeleteRiskPreview> previewPendingDestructivePush() async =>
      const PkDeleteRiskPreview();

  @override
  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async =>
      null;

  @override
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
    PKSwitch? knownCurrentFronters,
  }) async =>
      null;

  @override
  Future<PKSystem?> fetchSystemProfile() async => null;

  @override
  Future<void> adoptSystemProfile({
    required PKSystem pk,
    required Set<PkProfileField> accepted,
  }) async {}
}

class _FakePkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _FakePkSyncDirectionNotifier(this._initial);
  final PkSyncDirection _initial;

  @override
  PkSyncDirection build() => _initial;

  @override
  Future<void> load() async {
    state = _initial;
  }
}

class _FakePkSyncModeNotifier extends PkSyncModeNotifier {
  _FakePkSyncModeNotifier(this._initial);
  final PkSyncMode _initial;

  @override
  PkSyncMode build() => _initial;

  @override
  Future<void> load() async {
    state = _initial;
  }

  @override
  Future<void> setMode(PkSyncMode mode) async {
    state = mode;
  }
}

class _FakePkFirstSyncDeferredNotifier extends PkFirstSyncDeferredNotifier {
  _FakePkFirstSyncDeferredNotifier(this._initial);
  final bool _initial;

  @override
  Future<bool> build() async => _initial;

  @override
  Future<void> clear() async {
    state = const AsyncValue.data(false);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Sentinel that instructs [_buildScreen] to override [pkCurrentFrontersProvider]
/// with `null` (no current fronters / fetch failed).
const _pkFrontersNull = Object();

Widget _buildScreen({
  required FakeSystemSettingsRepository settingsRepository,
  required Stream<SystemSettings> settingsStream,
  PluralKitSyncState syncState = const PluralKitSyncState(),
  _FakeSyncNotifier? syncNotifier,
  PkSyncMode syncMode = PkSyncMode.fullSync,
  PkSyncDirection syncDirection = PkSyncDirection.pullOnly,
  bool migrationBlocked = false,
  // When non-null, overrides pkFirstSyncDeferredProvider with this value
  // so tests can exercise the deferred-sync banner without needing a real DAO.
  bool? pkFirstSyncDeferredValue,
  // When provided (including the [_pkFrontersNull] sentinel), overrides
  // [pkCurrentFrontersProvider] so tests don't hit the real PK API.
  // Pass a [PKSwitch] to simulate a known fronter set; pass [_pkFrontersNull]
  // to simulate a null result (fetch failed or no fronters).
  Object? pkCurrentFrontersOverride = _pkFrontersNull,
}) {
  PKSwitch? frontersValue;
  if (pkCurrentFrontersOverride is PKSwitch) {
    frontersValue = pkCurrentFrontersOverride;
  }
  // Otherwise (sentinel or null literal) → frontersValue stays null.

  return ProviderScope(
    overrides: [
      systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      systemSettingsProvider.overrideWith((ref) => settingsStream),
      pluralKitSyncProvider.overrideWith(
        () => syncNotifier ?? _FakeSyncNotifier(syncState),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _FakePkSyncDirectionNotifier(syncDirection),
      ),
      pkSyncModeProvider.overrideWith(
        () => _FakePkSyncModeNotifier(syncMode),
      ),
      frontingMigrationWritesBlockedProvider.overrideWithValue(
        migrationBlocked,
      ),
      if (pkFirstSyncDeferredValue != null)
        pkFirstSyncDeferredProvider.overrideWith(
          () => _FakePkFirstSyncDeferredNotifier(pkFirstSyncDeferredValue),
        ),
      // Always override so tests never hit the real PK API.
      pkCurrentFrontersProvider.overrideWith(
        (ref) async => frontersValue,
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: PrismToastHost(child: PluralKitSetupScreen()),
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeSystemSettingsRepository settingsRepository,
  required Stream<SystemSettings> settingsStream,
  PluralKitSyncState syncState = const PluralKitSyncState(),
  _FakeSyncNotifier? syncNotifier,
  PkSyncMode syncMode = PkSyncMode.fullSync,
  PkSyncDirection syncDirection = PkSyncDirection.pullOnly,
  bool migrationBlocked = false,
  bool? pkFirstSyncDeferredValue,
  Object? pkCurrentFrontersOverride = _pkFrontersNull,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    _buildScreen(
      settingsRepository: settingsRepository,
      settingsStream: settingsStream,
      syncState: syncState,
      syncNotifier: syncNotifier,
      syncMode: syncMode,
      syncDirection: syncDirection,
      migrationBlocked: migrationBlocked,
      pkFirstSyncDeferredValue: pkFirstSyncDeferredValue,
      pkCurrentFrontersOverride: pkCurrentFrontersOverride,
    ),
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(markPkBusMainIsolate);
  tearDown(() {
    PrismToast.resetForTest();
    resetPkBusMainIsolateForTest();
  });

  group('PluralKitSetupScreen — direction-first wizard', () {
    // (a) State needsDirection: shows "How should this sync?" section,
    //     hides mapping banner + sync actions.
    testWidgets(
      '(a) needsDirection state shows direction step, hides mapping banner and sync actions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: false,
            mappingAcknowledged: false,
          ),
        );

        // Direction step heading must appear.
        expect(find.text('How should this sync?'), findsOneWidget);
        // Continue button must appear.
        expect(find.text('Continue'), findsOneWidget);

        // Mapping banner must NOT appear.
        // (Button text is "Link {termPluralLower}" → "Link headmates" with defaults.)
        expect(find.text('Link headmates'), findsNothing);

        // Sync actions must NOT appear.
        expect(find.text('Sync Recent Changes'), findsNothing);
        expect(find.text('Import from PluralKit'), findsNothing);
      },
    );

    // (b) Tap Continue → confirmDirection invoked → state becomes
    //     needsMapping → mapping banner appears.
    testWidgets(
      '(b) Tapping Continue calls confirmDirection and transitions to needsMapping state',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = FakeSystemSettingsRepository();
        final notifier = _FakeSyncNotifier(
          const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: false,
            mappingAcknowledged: false,
          ),
        );

        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncNotifier: notifier,
        );

        expect(find.text('How should this sync?'), findsOneWidget);
        expect(notifier.confirmDirectionCallCount, 0);

        await tester.tap(find.text('Continue'));
        await tester.pump();
        await tester.pump();

        expect(notifier.confirmDirectionCallCount, 1);

        // After confirmDirection, state has directionConfirmed=true,
        // mappingAcknowledged=false → needsMapping=true → mapping banner shows.
        // The button text is "Link {termPluralLower}" — default terminology is
        // headmates (from FakeSystemSettingsRepository default settings).
        expect(find.text('How should this sync?'), findsNothing);
        expect(find.text('Link headmates'), findsOneWidget);
      },
    );

    // (c) State canAutoSync after deferred sync: "First sync deferred" banner
    //     appears in Sync Actions section. Dismiss removes it.
    testWidgets(
      '(c) canAutoSync with deferred-sync prefs flag shows deferred banner; dismiss clears it',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Override pkFirstSyncDeferredProvider directly so the banner is
        // visible without needing a real DAO or a seeded systemId. The prefs
        // key is irrelevant here because the provider is fully replaced.
        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: true,
          ),
          pkFirstSyncDeferredValue: true,
        );

        // Extra pump so the async provider resolves.
        await tester.pump();

        // The "First sync deferred" banner must appear above sync actions.
        // The banner text contains the key phrase "First sync deferred".
        expect(
          find.textContaining('First sync deferred'),
          findsOneWidget,
        );

        // Tap the dismiss button (close icon) to clear the banner.
        final closeIcon = find.byIcon(Icons.close);
        expect(closeIcon, findsOneWidget);
        await tester.tap(closeIcon);
        await tester.pump();
        await tester.pump();

        // Banner should be gone.
        expect(find.textContaining('First sync deferred'), findsNothing);
      },
    );

    // (d) Direction == pullOnly + state.needsMapping + known PK fronter "Bob":
    //     pull-only heads-up banner appears with the localised string naming Bob.
    testWidgets(
      '(d) pullOnly direction + needsMapping + known PK fronter shows localised pull-only heads-up banner',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Build a PKSwitch whose memberDetails include "Bob".
        final bobSwitch = PKSwitch(
          id: 'sw-bob',
          timestamp: DateTime(2026),
          members: const ['bob01'],
          memberDetails: const [
            PKMemberSummary(id: 'bob01', name: 'Bob'),
          ],
        );

        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: false,
          ),
          syncDirection: PkSyncDirection.pullOnly,
          pkCurrentFrontersOverride: bobSwitch,
        );

        // Extra pump so the async provider resolves.
        await tester.pump();

        // Mapping banner must appear.
        expect(find.text('Link headmates'), findsOneWidget);

        // Pull-only heads-up must show the localised string naming Bob.
        expect(
          find.textContaining(
            'PluralKit currently has Bob fronting; this will become your active fronter when you sync.',
          ),
          findsOneWidget,
        );
      },
    );

    // (d2) Provider returns null → no pull-only heads-up banner rendered.
    testWidgets(
      '(d2) pullOnly direction + needsMapping + pkCurrentFronters=null → no heads-up banner',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: false,
          ),
          syncDirection: PkSyncDirection.pullOnly,
          // Default override is null (sentinel) → banner suppressed.
        );

        await tester.pump();

        // Mapping banner is still there.
        expect(find.text('Link headmates'), findsOneWidget);

        // Heads-up banner must NOT appear when fronters fetch returns null.
        expect(
          find.textContaining('PluralKit currently has'),
          findsNothing,
        );
      },
    );

    // (d3) Provider returns a switch with no members → no banner rendered.
    testWidgets(
      '(d3) pullOnly direction + needsMapping + empty PKSwitch → no heads-up banner',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final emptySwitch = PKSwitch(
          id: 'sw-empty',
          timestamp: DateTime(2026),
          members: const [],
        );

        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: false,
          ),
          syncDirection: PkSyncDirection.pullOnly,
          pkCurrentFrontersOverride: emptySwitch,
        );

        await tester.pump();

        expect(find.text('Link headmates'), findsOneWidget);

        // Heads-up banner must NOT appear when PK switch has no members.
        expect(
          find.textContaining('PluralKit currently has'),
          findsNothing,
        );
      },
    );

    // (e) Migration writes blocked: "Resolve the fronting migration..."
    //     notice appears in place of the wizard sections.
    testWidgets(
      '(e) migration writes blocked shows blocked notice in place of wizard sections',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: false,
            mappingAcknowledged: false,
          ),
          migrationBlocked: true,
        );

        // The migration-blocked notice must appear.
        expect(
          find.textContaining(
            'Resolve the fronting migration to finish setting up PluralKit sync.',
          ),
          findsOneWidget,
        );

        // The direction step must NOT appear.
        expect(find.text('How should this sync?'), findsNothing);
        // The mapping banner must NOT appear.
        expect(find.text('Link headmates'), findsNothing);
      },
    );

    // (e2) Migration blocked in needsMapping state also hides mapping banner.
    testWidgets(
      '(e2) migration writes blocked in needsMapping state shows blocked notice',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = FakeSystemSettingsRepository();
        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncState: const PluralKitSyncState(
            isConnected: true,
            directionConfirmed: true,
            mappingAcknowledged: false,
          ),
          migrationBlocked: true,
        );

        expect(
          find.textContaining(
            'Resolve the fronting migration to finish setting up PluralKit sync.',
          ),
          findsOneWidget,
        );
        expect(find.text('How should this sync?'), findsNothing);
        expect(find.text('Link headmates'), findsNothing);
      },
    );

    // (f) _connect() no longer auto-pops the profile disclosure sheet.
    testWidgets(
      '(f) _connect() does not trigger profile disclosure sheet',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = FakeSystemSettingsRepository();
        final notifier = _FakeSyncNotifier(
          const PluralKitSyncState(isConnected: false),
        );

        await _pumpScreen(
          tester,
          settingsRepository: repo,
          settingsStream: Stream.value(repo.settings),
          syncNotifier: notifier,
          syncMode: PkSyncMode.fullSync,
          syncDirection: PkSyncDirection.pullOnly,
        );

        // Type a token and connect.
        await tester.enterText(find.byType(TextField), 'pk-test-token');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        // After connect, state transitions to needsDirection
        // (directionConfirmed=false). The disclosure sheet is NOT shown.
        // fetchSystemProfile should NOT be called from _connect().
        expect(notifier.confirmDirectionCallCount, 0);
        // We can't easily verify fetchSystemProfile wasn't called on this
        // fake since it's overridden to return null, but we verify no sheet
        // appeared — the direction step should be visible, not a bottom sheet.
        expect(find.text('How should this sync?'), findsOneWidget);
        // No disclosure sheet overlay.
        expect(
          find.textContaining('Import profile data'),
          findsNothing,
        );
      },
    );
  });
}
