import 'package:flutter/material.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_fronter_choice_card.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

// ---------------------------------------------------------------------------
// Public kinds (accessible from tests via @visibleForTesting surface)
// ---------------------------------------------------------------------------

/// Discriminator for each fronter-choice option.
///
/// Exposed as a public type so [computeOptions] tests can assert the correct
/// kind without importing private symbols.
enum FronterChoiceKind {
  usePrism,
  usePk,
  cofront,
  setMembers,
  keepMembers,
  leaveNoneFronting,
  matchPkNone,
}

// ---------------------------------------------------------------------------
// Option value class (public so the @visibleForTesting computeOptions return
// type is accessible from tests without importing private symbols)
// ---------------------------------------------------------------------------

/// Represents a single fronter-choice option computed by [computeOptions].
///
/// Intentionally lightweight — presentation strings are resolved at render
/// time from l10n keys, not stored here.
class FronterChoiceOption {
  const FronterChoiceOption({
    required this.kind,
    required this.resolvedLocalIds,
    required this.recommended,
  });

  final FronterChoiceKind kind;

  /// The set of local member IDs that would become fronting if chosen.
  final Set<String> resolvedLocalIds;

  final bool recommended;
}

// ---------------------------------------------------------------------------
// Pure computation (exported for tests)
// ---------------------------------------------------------------------------

/// Computes the ordered list of fronter-choice options for the given inputs.
///
/// Contract:
/// - Returns an empty list when the caller should skip the sheet entirely
///   (sets identical, both empty, or direction == disabled).
/// - Never returns two options with the same [FronterChoiceOption.resolvedLocalIds]
///   (collapse rule).
/// - Exactly one option is marked [FronterChoiceOption.recommended].
///
/// This function is `@visibleForTesting` — callers outside of tests should
/// rely on [PkWhoIsFrontingSheet.build] which drives this internally.
@visibleForTesting
List<FronterChoiceOption> computeOptions({
  required Set<String> localIds,
  required Set<String> pkIds,
  required PkSyncDirection direction,
}) {
  // Rule 6: disabled → skip.
  if (direction == PkSyncDirection.disabled) return const [];

  // Rule 2: both empty → skip.
  if (localIds.isEmpty && pkIds.isEmpty) return const [];

  // Rule 1: sets identical → skip.
  if (localIds.length == pkIds.length && localIds.containsAll(pkIds)) {
    return const [];
  }

  // Rule 3: Prism empty, PK non-empty.
  if (localIds.isEmpty && pkIds.isNotEmpty) {
    return [
      FronterChoiceOption(
        kind: FronterChoiceKind.setMembers,
        resolvedLocalIds: Set.unmodifiable(pkIds),
        recommended: true,
      ),
      const FronterChoiceOption(
        kind: FronterChoiceKind.leaveNoneFronting,
        resolvedLocalIds: {},
        recommended: false,
      ),
    ];
  }

  // Rule 4: PK empty, Prism non-empty.
  if (pkIds.isEmpty && localIds.isNotEmpty) {
    return [
      FronterChoiceOption(
        kind: FronterChoiceKind.keepMembers,
        resolvedLocalIds: Set.unmodifiable(localIds),
        recommended: true,
      ),
      const FronterChoiceOption(
        kind: FronterChoiceKind.matchPkNone,
        resolvedLocalIds: {},
        recommended: false,
      ),
    ];
  }

  // Rule 5: Symmetric case — both sides have ≥1 fronter.
  // Build raw options in priority order.
  final cofrontIds = Set.unmodifiable({...localIds, ...pkIds});

  final rawOptions = <FronterChoiceOption>[
    if (direction != PkSyncDirection.pullOnly)
      FronterChoiceOption(
        kind: FronterChoiceKind.usePrism,
        resolvedLocalIds: Set.unmodifiable(localIds),
        recommended: false,
      ),
    FronterChoiceOption(
      kind: FronterChoiceKind.cofront,
      resolvedLocalIds: cofrontIds,
      recommended: false,
    ),
    FronterChoiceOption(
      kind: FronterChoiceKind.usePk,
      resolvedLocalIds: Set.unmodifiable(pkIds),
      recommended: false,
    ),
  ];

  // Collapse rule: dedupe by resolvedLocalIds set equality, preserving order.
  // First occurrence wins (highest priority).
  final seen = <String>{}; // canonical key = sorted IDs joined
  final deduped = <FronterChoiceOption>[];
  for (final opt in rawOptions) {
    final key = (opt.resolvedLocalIds.toList()..sort()).join(',');
    if (seen.add(key)) {
      deduped.add(opt);
    }
  }

  // Determine recommended kind.
  final preferredKind = switch (direction) {
    PkSyncDirection.bidirectional => FronterChoiceKind.cofront,
    PkSyncDirection.pushOnly => FronterChoiceKind.usePrism,
    PkSyncDirection.pullOnly => FronterChoiceKind.usePk,
    PkSyncDirection.disabled => FronterChoiceKind.cofront, // unreachable
  };

  // Find the option matching the preferred kind; fall back to first.
  final recommendedIndex = deduped.indexWhere((o) => o.kind == preferredKind);
  final effectiveRecommendedIdx = recommendedIndex >= 0 ? recommendedIndex : 0;

  return List.unmodifiable([
    for (int i = 0; i < deduped.length; i++)
      FronterChoiceOption(
        kind: deduped[i].kind,
        resolvedLocalIds: deduped[i].resolvedLocalIds,
        recommended: i == effectiveRecommendedIdx,
      ),
  ]);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// A stateless sheet that presents the "Who's fronting?" resolution UI.
///
/// Takes [localFronters] and [pkFronters] as pre-resolved (id, name) pairs
/// plus the active [direction], computes the appropriate options, and renders
/// them as [PkFronterChoiceCard]s.
///
/// [onResult] receives:
/// - A [Set<String>] of chosen local member IDs when a card is tapped.
/// - `null` when the user taps "Decide later".
///
/// This widget is stateless and performs no I/O. Use [PkWhoIsFrontingSheet.show]
/// to present it in a non-dismissible bottom sheet.
class PkWhoIsFrontingSheet extends StatelessWidget {
  const PkWhoIsFrontingSheet({
    super.key,
    required this.localFronters,
    required this.pkFronters,
    required this.direction,
    required this.onResult,
  });

  /// Local fronters: each entry is a `(id, name)` record.
  final List<({String id, String name})> localFronters;

  /// PK fronters projected to local member ids: each entry is a `(id, name)` record.
  final List<({String id, String name})> pkFronters;

  final PkSyncDirection direction;

  /// Called with the chosen set of local member IDs, or null for "Decide later".
  final void Function(Set<String>? result) onResult;

  /// Convenience: shows the sheet via [PrismSheet.show] with `isDismissible: false`.
  ///
  /// Returns the chosen [Set<String>] or null (Decide later). Returns null if
  /// the sheet was somehow dismissed without a result (should not occur since
  /// `isDismissible: false`).
  static Future<Set<String>?> show({
    required BuildContext context,
    required List<({String id, String name})> localFronters,
    required List<({String id, String name})> pkFronters,
    required PkSyncDirection direction,
  }) async {
    return PrismSheet.show<Set<String>?>(
      context: context,
      isDismissible: false,
      builder: (sheetContext) => PkWhoIsFrontingSheet(
        localFronters: localFronters,
        pkFronters: pkFronters,
        direction: direction,
        onResult: (result) => Navigator.of(sheetContext).pop(result),
      ),
    );
  }

  // Build a lookup from id → name for both sides.
  Map<String, String> _buildNameMap() {
    return {
      for (final e in localFronters) e.id: e.name,
      for (final e in pkFronters) e.id: e.name,
    };
  }

  /// Resolves the card title for a given option.
  ///
  /// For symmetric kinds (usePrism / usePk / cofront) the title is the kind
  /// label and the subtitle carries the member names.  For asymmetric kinds
  /// (setMembers / keepMembers / leaveNoneFronting / matchPkNone) the title IS
  /// the action label — the subtitle is empty because the label is
  /// self-explanatory.
  String _title(
    BuildContext context,
    FronterChoiceOption option,
    Map<String, String> nameMap,
  ) {
    final l10n = context.l10n;
    final names =
        option.resolvedLocalIds.map((id) => nameMap[id] ?? id).toList()..sort();
    final joined = names.join(', ');

    return switch (option.kind) {
      FronterChoiceKind.usePrism => l10n.pluralkitWhosFrontingUsePrism,
      FronterChoiceKind.usePk => l10n.pluralkitWhosFrontingUsePk,
      FronterChoiceKind.cofront => l10n.pluralkitWhosFrontingCofront,
      FronterChoiceKind.setMembers => l10n.pluralkitWhosFrontingSetMembers(
        joined,
      ),
      FronterChoiceKind.keepMembers => l10n.pluralkitWhosFrontingKeepMembers(
        joined,
      ),
      FronterChoiceKind.leaveNoneFronting =>
        l10n.pluralkitWhosFrontingNoneFronting,
      FronterChoiceKind.matchPkNone => l10n.pluralkitWhosFrontingMatchPkNone,
    };
  }

  /// Resolves the card subtitle for a given option.
  ///
  /// Symmetric kinds show the comma-joined member names.  Asymmetric kinds
  /// return an empty string — the title already carries the action label.
  String _subtitle(
    BuildContext context,
    FronterChoiceOption option,
    Map<String, String> nameMap,
  ) {
    final names =
        option.resolvedLocalIds.map((id) => nameMap[id] ?? id).toList()..sort();
    final joined = names.join(', ');

    return switch (option.kind) {
      FronterChoiceKind.usePrism => joined,
      FronterChoiceKind.usePk => joined,
      FronterChoiceKind.cofront => joined,
      FronterChoiceKind.setMembers => '',
      FronterChoiceKind.keepMembers => '',
      FronterChoiceKind.leaveNoneFronting => '',
      FronterChoiceKind.matchPkNone => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final bottomInset = modalBottomInsetOf(context);

    final localIds = {for (final e in localFronters) e.id};
    final pkIds = {for (final e in pkFronters) e.id};
    final options = computeOptions(
      localIds: localIds,
      pkIds: pkIds,
      direction: direction,
    );
    final nameMap = _buildNameMap();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            l10n.pluralkitWhosFrontingTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Subtitle
          Text(
            l10n.pluralkitWhosFrontingSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // Option cards
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            PkFronterChoiceCard(
              title: _title(context, options[i], nameMap),
              subtitle: _subtitle(context, options[i], nameMap),
              recommended: options[i].recommended,
              onTap: () =>
                  onResult(Set.unmodifiable(options[i].resolvedLocalIds)),
            ),
          ],
          const SizedBox(height: 16),
          // Decide later
          PrismButton(
            label: l10n.pluralkitWhosFrontingDecideLater,
            onPressed: () => onResult(null),
            tone: PrismButtonTone.subtle,
            expanded: true,
          ),
        ],
      ),
    );
  }
}
