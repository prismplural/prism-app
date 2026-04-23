import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_group_repair_card.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  Widget buildTestApp({required Widget child}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  testWidgets(
    'shows local-only guidance, pending review count, and blocked cutover',
    (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: PkGroupRepairCard(
            state: const PkGroupRepairState(
              pendingReviewCount: 2,
              pendingReviewItems: [
                PkGroupReviewItem(
                  groupId: 'group-1',
                  name: 'Cluster',
                  suspectedPkGroupUuid: 'pk-group-1',
                  syncSuppressed: true,
                ),
                PkGroupReviewItem(
                  groupId: 'group-2',
                  name: 'Cluster Copy',
                  suspectedPkGroupUuid: 'pk-group-1',
                  syncSuppressed: true,
                ),
              ],
              lastReport: PkGroupRepairReport(
                referenceMode: PkGroupRepairReferenceMode.none,
                backfilledEntries: 2,
                canonicalizedEntryIds: 0,
                revivedTombstonesDuringCanonicalization: 0,
                legacyEntriesSoftDeletedDuringCanonicalization: 0,
                duplicateSetsMerged: 1,
                duplicateGroupsSoftDeleted: 1,
                parentReferencesRehomed: 3,
                entriesRehomed: 4,
                entryConflictsSoftDeleted: 2,
                aliasesRecorded: 1,
                ambiguousGroupsSuppressed: 1,
                pendingReviewCount: 2,
              ),
            ),
            isConnected: false,
            hasStoredToken: false,
            pkGroupSyncV2Enabled: false,
            onRunRepair: () {},
            onDismissReviewItem: (_) async {},
            onKeepReviewItemLocalOnly: (_) async {},
            onMergeReviewItemIntoCanonical: (_) async {},
            onEnablePkGroupSyncV2: () async {},
            onResetPkGroupsOnly: () async {},
            onExportDataFirst: () {},
            onUseTemporaryToken: () {},
          ),
        ),
      );

      expect(find.text('PluralKit group repair'), findsOneWidget);
      expect(find.text('2 pending review'), findsOneWidget);
      expect(find.text('Local-only until token'), findsOneWidget);
      expect(find.text('PK sync v2 off'), findsOneWidget);
      expect(find.text('Run local repair'), findsOneWidget);
      expect(find.text('Use temporary token'), findsOneWidget);
      expect(find.text('Merge into canonical'), findsNWidgets(2));
      expect(find.text('Keep local-only'), findsNWidgets(2));
      expect(find.text('Dismiss false positive'), findsNWidgets(2));
      expect(find.text('What changed'), findsOneWidget);
      expect(
        find.text(
          'Local run updated 3 child-group parent links, moved 4 group '
          'memberships, removed 1 duplicate local group, removed 2 '
          'conflicting group memberships, and suppressed 1 ambiguous group '
          'for review.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Updated 3 child-group parent links to point at the surviving group.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Moved 4 group memberships onto the surviving group.'),
        findsOneWidget,
      );
      expect(find.text('Removed 1 duplicate local group.'), findsOneWidget);
      expect(
        find.text(
          'Removed 2 conflicting group memberships while merging duplicates.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Suppressed 1 ambiguous group for review before sync can continue.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Restored 2 missing PK membership links.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Recorded 1 legacy group alias so older group IDs still resolve.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Unavailable until pending review items are resolved or kept '
          'local-only.',
        ),
        findsOneWidget,
      );
      expect(find.text('Enable PK group sync'), findsNothing);
    },
  );

  testWidgets(
    'blocks cutover until a repair run has completed in current state',
    (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: PkGroupRepairCard(
            state: const PkGroupRepairState(),
            isConnected: true,
            hasStoredToken: true,
            pkGroupSyncV2Enabled: false,
            onRunRepair: () {},
            onDismissReviewItem: (_) async {},
            onKeepReviewItemLocalOnly: (_) async {},
            onMergeReviewItemIntoCanonical: (_) async {},
            onEnablePkGroupSyncV2: () async {},
            onResetPkGroupsOnly: () async {},
            onExportDataFirst: () {},
          ),
        ),
      );

      expect(find.text('Token-backed ready'), findsOneWidget);
      expect(find.text('PK sync v2 off'), findsOneWidget);
      expect(
        find.text(
          'Unavailable until a repair run completes in this app session.',
        ),
        findsOneWidget,
      );
      expect(find.text('Enable PK group sync'), findsNothing);
      expect(find.text('Use temporary token'), findsNothing);
    },
  );

  testWidgets(
    'shows reconnect guidance for import-only repair runs instead of generic local-only copy',
    (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: PkGroupRepairCard(
            state: const PkGroupRepairState(
              lastReport: PkGroupRepairReport(
                referenceMode: PkGroupRepairReferenceMode.none,
                backfilledEntries: 1,
                canonicalizedEntryIds: 0,
                revivedTombstonesDuringCanonicalization: 0,
                legacyEntriesSoftDeletedDuringCanonicalization: 0,
                duplicateSetsMerged: 0,
                duplicateGroupsSoftDeleted: 0,
                parentReferencesRehomed: 0,
                entriesRehomed: 0,
                entryConflictsSoftDeleted: 0,
                aliasesRecorded: 0,
                ambiguousGroupsSuppressed: 0,
                pendingReviewCount: 0,
                requiresReconnectForMissingPkGroupIdentity: true,
              ),
            ),
            isConnected: false,
            hasStoredToken: false,
            pkGroupSyncV2Enabled: false,
            onRunRepair: () {},
            onDismissReviewItem: (_) async {},
            onKeepReviewItemLocalOnly: (_) async {},
            onMergeReviewItemIntoCanonical: (_) async {},
            onEnablePkGroupSyncV2: () async {},
            onResetPkGroupsOnly: () async {},
            onExportDataFirst: () {},
            onUseTemporaryToken: () {},
          ),
        ),
      );

      expect(
        find.text(
          'Local repair can still restore directly provable PK links, but '
          'reconnecting PluralKit is still required to reconstruct missing PK '
          'group identity automatically.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The last run finished the safe local repair pass, but missing PK '
          'group identity still needs a live PluralKit reference source to be '
          'reconstructed automatically.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'This looks like import-only PK data with no local PK-linked '
          'groups left to use as repair references. Prism can still repair '
          'directly linked rows locally, but reconnecting PluralKit or using '
          'a temporary token is the only way to reconstruct missing PK group '
          'identity automatically.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Restored 1 missing PK membership link.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Reconnect PluralKit above or use a temporary token for a fuller '
          'repair pass. Local repair still handles the obvious duplicates.',
        ),
        findsNothing,
      );
      expect(
        find.text(
          'The last run did not find any new PK group repairs to apply.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'requires explicit confirmation before enabling PK group sync v2',
    (tester) async {
      var enableCount = 0;

      await tester.pumpWidget(
        buildTestApp(
          child: PkGroupRepairCard(
            state: const PkGroupRepairState(
              lastReport: PkGroupRepairReport(
                referenceMode: PkGroupRepairReferenceMode.storedToken,
                backfilledEntries: 1,
                canonicalizedEntryIds: 0,
                revivedTombstonesDuringCanonicalization: 0,
                legacyEntriesSoftDeletedDuringCanonicalization: 0,
                duplicateSetsMerged: 1,
                duplicateGroupsSoftDeleted: 0,
                parentReferencesRehomed: 0,
                entriesRehomed: 0,
                entryConflictsSoftDeleted: 0,
                aliasesRecorded: 0,
                ambiguousGroupsSuppressed: 0,
                pendingReviewCount: 0,
              ),
            ),
            isConnected: true,
            hasStoredToken: true,
            pkGroupSyncV2Enabled: false,
            onRunRepair: () {},
            onDismissReviewItem: (_) async {},
            onKeepReviewItemLocalOnly: (_) async {},
            onMergeReviewItemIntoCanonical: (_) async {},
            onEnablePkGroupSyncV2: () async {
              enableCount += 1;
            },
            onResetPkGroupsOnly: () async {},
            onExportDataFirst: () {},
          ),
        ),
      );

      expect(find.text('Enable PK group sync'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Enable PK group sync'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Enable PK group sync'));
      await tester.pumpAndSettle();

      expect(find.text('Enable PK sync v2?'), findsOneWidget);
      expect(
        find.textContaining('If any device is unaccounted for, keep this off.'),
        findsOneWidget,
      );
      expect(enableCount, 0);

      await tester.tap(find.text('Enable PK sync v2'));
      await tester.pumpAndSettle();

      expect(enableCount, 1);
    },
  );

  testWidgets('shows enabled cutover state without the enable action', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestApp(
        child: PkGroupRepairCard(
          state: const PkGroupRepairState(
            lastReport: PkGroupRepairReport(
              referenceMode: PkGroupRepairReferenceMode.storedToken,
              backfilledEntries: 0,
              canonicalizedEntryIds: 0,
              revivedTombstonesDuringCanonicalization: 0,
              legacyEntriesSoftDeletedDuringCanonicalization: 0,
              duplicateSetsMerged: 0,
              duplicateGroupsSoftDeleted: 0,
              parentReferencesRehomed: 0,
              entriesRehomed: 0,
              entryConflictsSoftDeleted: 0,
              aliasesRecorded: 0,
              ambiguousGroupsSuppressed: 0,
              pendingReviewCount: 0,
            ),
          ),
          isConnected: true,
          hasStoredToken: true,
          pkGroupSyncV2Enabled: true,
          onRunRepair: () {},
          onDismissReviewItem: (_) async {},
          onKeepReviewItemLocalOnly: (_) async {},
          onMergeReviewItemIntoCanonical: (_) async {},
          onEnablePkGroupSyncV2: () async {},
          onResetPkGroupsOnly: () async {},
          onExportDataFirst: () {},
        ),
      ),
    );

    expect(find.text('PK sync v2 enabled'), findsOneWidget);
    expect(
      find.text('Enabled for this sync group after explicit confirmation.'),
      findsOneWidget,
    );
    expect(find.text('Enable PK group sync'), findsNothing);
  });

  testWidgets(
    'shows reset escape hatch for pending review items and can route to export',
    (tester) async {
      var exportCount = 0;
      var resetCount = 0;

      await tester.pumpWidget(
        buildTestApp(
          child: PkGroupRepairCard(
            state: const PkGroupRepairState(
              pendingReviewCount: 1,
              pendingReviewItems: [
                PkGroupReviewItem(
                  groupId: 'group-1',
                  name: 'Cluster Copy',
                  suspectedPkGroupUuid: 'pk-group-1',
                  syncSuppressed: true,
                ),
              ],
              lastReport: PkGroupRepairReport(
                referenceMode: PkGroupRepairReferenceMode.none,
                backfilledEntries: 0,
                canonicalizedEntryIds: 0,
                revivedTombstonesDuringCanonicalization: 0,
                legacyEntriesSoftDeletedDuringCanonicalization: 0,
                duplicateSetsMerged: 0,
                duplicateGroupsSoftDeleted: 0,
                parentReferencesRehomed: 0,
                entriesRehomed: 0,
                entryConflictsSoftDeleted: 0,
                aliasesRecorded: 0,
                ambiguousGroupsSuppressed: 1,
                pendingReviewCount: 1,
              ),
            ),
            isConnected: false,
            hasStoredToken: false,
            pkGroupSyncV2Enabled: false,
            onRunRepair: () {},
            onDismissReviewItem: (_) async {},
            onKeepReviewItemLocalOnly: (_) async {},
            onMergeReviewItemIntoCanonical: (_) async {},
            onEnablePkGroupSyncV2: () async {},
            onResetPkGroupsOnly: () async {
              resetCount += 1;
            },
            onExportDataFirst: () {
              exportCount += 1;
            },
            onUseTemporaryToken: () {},
          ),
        ),
      );

      expect(find.text('Reset PK groups only'), findsOneWidget);

      await tester.ensureVisible(find.text('Reset PK groups only'));
      await tester.tap(find.text('Reset PK groups only'));
      await tester.pumpAndSettle();

      expect(find.text('Reset PK groups only?'), findsOneWidget);
      expect(find.text('Export data first'), findsOneWidget);

      await tester.tap(find.text('Export data first'));
      await tester.pumpAndSettle();

      expect(exportCount, 1);
      expect(resetCount, 0);
    },
  );

  testWidgets(
    'connected reset escape hatch requires confirmation before reset',
    (tester) async {
      var resetCount = 0;

      await tester.pumpWidget(
        buildTestApp(
          child: PkGroupRepairCard(
            state: const PkGroupRepairState(
              lastReport: PkGroupRepairReport(
                referenceMode: PkGroupRepairReferenceMode.none,
                backfilledEntries: 0,
                canonicalizedEntryIds: 0,
                revivedTombstonesDuringCanonicalization: 0,
                legacyEntriesSoftDeletedDuringCanonicalization: 0,
                duplicateSetsMerged: 0,
                duplicateGroupsSoftDeleted: 0,
                parentReferencesRehomed: 0,
                entriesRehomed: 0,
                entryConflictsSoftDeleted: 0,
                aliasesRecorded: 0,
                ambiguousGroupsSuppressed: 0,
                pendingReviewCount: 0,
                requiresReconnectForMissingPkGroupIdentity: true,
              ),
            ),
            isConnected: true,
            hasStoredToken: false,
            pkGroupSyncV2Enabled: false,
            onRunRepair: () {},
            onDismissReviewItem: (_) async {},
            onKeepReviewItemLocalOnly: (_) async {},
            onMergeReviewItemIntoCanonical: (_) async {},
            onEnablePkGroupSyncV2: () async {},
            onResetPkGroupsOnly: () async {
              resetCount += 1;
            },
            onExportDataFirst: () {},
            onUseTemporaryToken: () {},
          ),
        ),
      );

      expect(find.text('Reset PK groups and re-import'), findsOneWidget);

      await tester.ensureVisible(find.text('Reset PK groups and re-import'));
      await tester.tap(find.text('Reset PK groups and re-import'));
      await tester.pumpAndSettle();

      expect(find.text('Reset PK groups only?'), findsOneWidget);
      expect(find.text('Reset and re-import'), findsOneWidget);
      expect(resetCount, 0);

      await tester.tap(find.text('Reset and re-import'));
      await tester.pumpAndSettle();

      expect(resetCount, 1);
    },
  );
}
