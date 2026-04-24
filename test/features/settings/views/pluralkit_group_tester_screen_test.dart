import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/views/debug_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _ScriptedSyncService extends Fake implements PluralKitSyncService {
  _ScriptedSyncService(this._scripted);

  final List<PkRepairReferenceData> _scripted;
  final List<String?> tokensReceived = [];
  int _callIndex = 0;

  @override
  Future<PkRepairReferenceData> fetchRepairReferenceData({
    String? token,
  }) async {
    tokensReceived.add(token);
    if (_callIndex >= _scripted.length) {
      throw StateError('No more scripted PkRepairReferenceData responses');
    }
    return _scripted[_callIndex++];
  }
}

Widget _harness({
  required PluralKitSyncService service,
  Widget child = const PluralKitGroupTesterScreen(),
}) {
  return ProviderScope(
    overrides: [pluralKitSyncServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PkRepairReferenceData fixture({
    List<PKGroup>? groups,
    List<PKMember>? members,
  }) {
    return PkRepairReferenceData(
      system: const PKSystem(id: 'sys-1', name: 'Test System'),
      members:
          members ??
          const [PKMember(id: 'm1', uuid: 'pk-member-a', name: 'Alice')],
      groups:
          groups ??
          const [
            PKGroup(
              id: 'g1',
              uuid: 'pk-group-1',
              name: 'Cluster',
              memberIds: ['pk-member-a'],
            ),
          ],
    );
  }

  testWidgets('fetch with empty token shows inline error', (tester) async {
    final service = _ScriptedSyncService([fixture()]);
    await tester.pumpWidget(_harness(service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fetch groups'));
    await tester.pumpAndSettle();

    expect(find.text('Paste a PluralKit token first.'), findsOneWidget);
    expect(service.tokensReceived, isEmpty);
  });

  testWidgets('seed fails cleanly when no group has visible members', (
    tester,
  ) async {
    // All groups have memberIds == null (privacy-hidden); fetch still
    // succeeds, but seed should surface the inline error and not mutate
    // the sandbox.
    final service = _ScriptedSyncService([
      fixture(
        members: const [],
        groups: const [PKGroup(id: 'g1', uuid: 'pk-group-1', name: 'Hidden')],
      ),
    ]);
    await tester.pumpWidget(_harness(service: service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'pk-token-abc');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fetch groups'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 group(s)'), findsOneWidget);

    await tester.tap(find.text('Seed sandbox review from first group'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No PluralKit group with visible members'),
      findsOneWidget,
    );
  });

  testWidgets(
    'fetch caches reference data so the sandbox repair run does not refetch',
    (tester) async {
      // Only one scripted response; a second call would throw. If the
      // sandbox repair service hits the cache, we stay at one call.
      final service = _ScriptedSyncService([fixture()]);
      await tester.pumpWidget(_harness(service: service));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'token-1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fetch groups'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Run sandbox repair'));
      await tester.pumpAndSettle();

      // The scripted service only has one response queued. Hitting it again
      // would throw, so reaching this point with a single recorded call is
      // the proof that the sandbox repair cycle used the cached reference.
      expect(service.tokensReceived.length, 1);
      expect(service.tokensReceived.first, 'token-1');

      // The success toast starts a 3s auto-dismiss timer; wait it out so the
      // test tear-down doesn't trip the "pending timer after dispose" assert.
      PrismToast.dismiss();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('disposing the screen restores dontWarnAboutMultipleDatabases', (
    tester,
  ) async {
    final previous = drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    addTearDown(() {
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
    });

    final service = _ScriptedSyncService([fixture()]);
    await tester.pumpWidget(_harness(service: service));
    await tester.pumpAndSettle();
    expect(drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases, isTrue);

    // Swap in an empty widget to force the tester screen to dispose.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pumpAndSettle();

    expect(drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases, previous);
  });
}
