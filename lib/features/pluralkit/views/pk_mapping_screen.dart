import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_profile_disclosure_helper.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_who_is_fronting_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Sentinel values for the PK-row select.
///
/// Exported so widget tests can reference the same constants rather than
/// duplicating bare strings.
const kPkRowImportSentinel = '__import__';
const kPkRowSkipSentinel = '__skip__';

class PkMappingScreen extends ConsumerWidget {
  const PkMappingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pkMappingControllerProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return PrismPageScaffold(
      topBar: PrismTopBar(title: l10n.pkMappingTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: async.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.pkMappingLoadError(e.toString()),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrismButton(
                  onPressed: () =>
                      ref.read(pkMappingControllerProvider.notifier).retry(),
                  icon: AppIcons.sync,
                  label: l10n.pkMappingRetry,
                  tone: PrismButtonTone.filled,
                ),
              ],
            ),
          ),
        ),
        data: (state) => _MappingBody(state: state),
      ),
    );
  }
}

class _MappingBody extends ConsumerWidget {
  const _MappingBody({required this.state});
  final PkMappingState state;

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // Pre-resolve the localized phase status strings here so the controller
    // (which has no BuildContext) can use them when transitioning into the
    // importing / pushing phases.
    final outcome = await ref.read(pkMappingControllerProvider.notifier).apply(
          importingHistoryStatus: l10n.pkMappingImportingHistory,
          pushingHistoryStatus: l10n.pkMappingPushingHistory,
          offlineErrorMessage: l10n.pkMappingNetworkErrorOffline,
        );
    if (!context.mounted) return;

    switch (outcome) {
      case PkMappingApplyOutcomeApplied():
        final syncState = ref.read(pluralKitSyncProvider);
        final mode = ref.read(pkSyncModeProvider);
        final direction = ref.read(pkSyncDirectionProvider);
        await maybeShowPkProfileDisclosure(
          context: context,
          ref: ref,
          syncState: syncState,
          mode: mode,
          direction: direction,
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();

      case PkMappingApplyOutcomeNeedsFronterResolution(
          :final localFronterMemberIds,
          :final pkFronterMemberIds,
          :final direction,
          :final mode,
          :final pkCurrentSwitch,
        ):
        // Resolve local member IDs to (id, name) pairs for the sheet.
        final memberRepo = ref.read(memberRepositoryProvider);

        Future<List<({String id, String name})>> resolveNames(
          Set<String> ids,
        ) async {
          if (ids.isEmpty) return const <({String id, String name})>[];
          // Batch lookup — one query instead of N sequential
          // getMemberById calls. The fronter resolution sheet rarely lists
          // more than a handful of IDs, but batching keeps this O(1) round
          // trips regardless of system size.
          final members = await memberRepo.getMembersByIds(ids.toList());
          return [
            for (final m in members)
              (id: m.id, name: m.displayName ?? m.name),
          ];
        }

        final localFronters = await resolveNames(localFronterMemberIds);
        final pkFronters = await resolveNames(pkFronterMemberIds);
        if (!context.mounted) return;

        final chosen = await PkWhoIsFrontingSheet.show(
          context: context,
          localFronters: localFronters,
          pkFronters: pkFronters,
          direction: direction,
        );
        if (!context.mounted) return;

        if (chosen == null) {
          // "Decide later" — defer bootstrap.
          await ref.read(pkMappingControllerProvider.notifier).deferBootstrap();
          if (!context.mounted) return;
          Navigator.of(context).pop();
          return;
        }

        // User chose a set — apply fronter resolution then pop.
        await ref
            .read(pkMappingControllerProvider.notifier)
            .applyFronterResolution(
              chosenLocalMemberIds: chosen,
              direction: direction,
              mode: mode,
              pkCurrentSwitch: pkCurrentSwitch,
              importingHistoryStatus: l10n.pkMappingImportingHistory,
              pushingHistoryStatus: l10n.pkMappingPushingHistory,
            );
        if (!context.mounted) return;

        final syncState = ref.read(pluralKitSyncProvider);
        await maybeShowPkProfileDisclosure(
          context: context,
          ref: ref,
          syncState: syncState,
          mode: mode,
          direction: direction,
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();

      case PkMappingApplyOutcomeFailed():
        // Failure UI is driven by state.lastResults (rendered by
        // _ResultsSummary) and state.error. No navigation — stay on screen.
        break;

      case null:
        // Null outcome means an early exit (not connected, ref unmounted,
        // unhandled exception). State.error is already set; stay on screen.
        break;
    }
  }

  void _dismiss(BuildContext context, WidgetRef ref) {
    ref.read(pkMappingControllerProvider.notifier).dismiss();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final unlinkedLocals = state.unlinkedLocals;

    // Nothing for the user to act on — every PK member is already linked
    // and every local already carries a PK link. Most commonly hit after a
    // Prism data restore on an account that was previously PluralKit-paired:
    // the imported local rows still carry their old pluralkitUuid/pluralkitId,
    // so the controller filters every fetched PK member out as "already
    // mapped." Without this branch we'd render the intro + footer buttons
    // with no rows between them, which reads as a broken screen.
    if (state.pkMembers.isEmpty && unlinkedLocals.isEmpty) {
      return EmptyState(
        icon: Icon(AppIcons.people),
        title: l10n.pkMappingEmptyTitle,
        subtitle: state.localMembers.isEmpty
            ? l10n.pkMappingEmptySubtitle
            : l10n.pkMappingAllLinkedSubtitle,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Intro copy.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.pkMappingIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // -- Section 1: PK members --
        if (state.pkMembers.isNotEmpty) ...[
          _SectionHeader(title: l10n.pkMappingSectionPkMembers),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                for (final pk in state.pkMembers) ...[
                  _PkMemberRow(pkMember: pk, state: state),
                ],
              ],
            ),
          ),
        ],

        // -- Section 2: Locals to push --
        if (unlinkedLocals.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.pkMappingSectionLocalToPush),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                for (final local in unlinkedLocals)
                  _LocalMemberRow(localMember: local, state: state),
              ],
            ),
          ),
        ],

        // -- Results summary --
        if (state.lastResults != null) ...[
          const SizedBox(height: 24),
          _ResultsSummary(results: state.lastResults!, state: state),
        ],

        if (state.error != null) ...[
          const SizedBox(height: 16),
          Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],

        // -- Apply progress --
        if (state.isApplying) ...[
          const SizedBox(height: 24),
          if (state.statusText != null) ...[
            Text(state.statusText!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
          LinearProgressIndicator(
            value: state.applyProgress > 0 ? state.applyProgress : null,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pkMappingApplyProgress((state.applyProgress * 100).toInt()),
            style: theme.textTheme.bodySmall,
          ),
        ],

        // -- Footer buttons --
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => _apply(context, ref),
          icon: AppIcons.checkCircle,
          label: l10n.pkMappingApply,
          tone: PrismButtonTone.filled,
          expanded: true,
          enabled: !state.isApplying,
          isLoading: state.isApplying,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () => _dismiss(context, ref),
          label: l10n.pkMappingDoLater,
          tone: PrismButtonTone.subtle,
          expanded: true,
          enabled: !state.isApplying,
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PkMemberRow extends ConsumerWidget {
  const _PkMemberRow({required this.pkMember, required this.state});

  final PKMember pkMember;
  final PkMappingState state;

  Future<void> _showLinkSearch(
    BuildContext context,
    WidgetRef ref,
    List<domain.Member> members,
  ) async {
    final l10n = context.l10n;
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: l10n.settingsTerminologyOptionMembers,
      title: l10n.pkMappingOptionLink(pkMember.name),
    );

    if (!context.mounted) return;
    if (result case MemberSearchResultSelected(:final memberId)) {
      ref
          .read(pkMappingControllerProvider.notifier)
          .setPkDecision(
            pkMember.uuid,
            PkLinkDecision(localMemberId: memberId, pkMember: pkMember),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final decision = state.decisionsByPkUuid[pkMember.uuid];

    // Build the current selection value for PrismSelect.
    String selectedValue;
    if (decision is PkLinkDecision) {
      selectedValue = decision.localMemberId;
    } else if (decision is PkSkipDecision) {
      selectedValue = kPkRowSkipSentinel;
    } else {
      selectedValue = kPkRowImportSentinel;
    }

    // Local IDs already linked to a DIFFERENT PK member are not available.
    final consumedElsewhere = <String>{};
    for (final entry in state.decisionsByPkUuid.entries) {
      if (entry.key == pkMember.uuid) continue;
      final d = entry.value;
      if (d is PkLinkDecision) consumedElsewhere.add(d.localMemberId);
    }

    bool isLinkCandidate(domain.Member m) => !hasResolvablePluralKitLink(
          m,
          fetchedPkUuids: state.fetchedPkUuids,
          fetchedPkIds: state.fetchedPkIds,
        );

    final linkableMembers = state.localMembers
        .where((m) => isLinkCandidate(m) && !consumedElsewhere.contains(m.id))
        .toList(growable: false);

    final items = <PrismSelectItem<String>>[
      PrismSelectItem(
        value: kPkRowImportSentinel,
        label: l10n.pkMappingOptionImportNew,
        leading: Icon(AppIcons.cloudDownload),
      ),
      PrismSelectItem(
        value: kPkRowSkipSentinel,
        label: l10n.pkMappingOptionSkip,
        leading: Icon(AppIcons.linkOff),
      ),
      for (final local in state.localMembers.where(isLinkCandidate))
        PrismSelectItem(
          value: local.id,
          label: l10n.pkMappingOptionLink(local.name),
          // Surface stale PK fields inline so the user understands that a
          // Link here will overwrite the unresolved fields on this local.
          subtitle: hasPluralKitLink(local)
              ? l10n.pkMappingRowUnresolvedCandidateCaption
              : null,
          leading: MemberAvatar(
            memberName: local.name,
            emoji: local.emoji,
            customColorEnabled: local.customColorEnabled,
            customColorHex: local.customColorHex,
            avatarImageData: local.avatarImageData,
            size: 28,
          ),
          enabled: !consumedElsewhere.contains(local.id),
        ),
    ];

    final nameColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pkMember.displayName ?? pkMember.name,
          style: theme.textTheme.bodyLarge,
        ),
        Text(
          pkMember.id,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        // No locals available to link this PK member to — surface the
        // recovery hint so users understand "Import as new" or the manage
        // screen are their options.
        if (linkableMembers.isEmpty) ...[
          const SizedBox(height: 2),
          Text(
            l10n.pkMappingRowNoCandidatesCaption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );

    final select = PrismSelect<String>(
      value: selectedValue,
      items: items,
      onChanged: (value) {
        if (value == null) return;
        final controller = ref.read(pkMappingControllerProvider.notifier);
        if (value == kPkRowImportSentinel) {
          controller.setPkDecision(
            pkMember.uuid,
            PkImportDecision(pkMember: pkMember),
          );
        } else if (value == kPkRowSkipSentinel) {
          controller.setPkDecision(
            pkMember.uuid,
            PkSkipDecision(pkMemberUuid: pkMember.uuid),
          );
        } else {
          controller.setPkDecision(
            pkMember.uuid,
            PkLinkDecision(localMemberId: value, pkMember: pkMember),
          );
        }
      },
    );

    final searchButton = PrismGlassIconButton(
      key: ValueKey('pkMappingLinkSearch-${pkMember.uuid}'),
      icon: AppIcons.search,
      tooltip: l10n.search,
      size: 40,
      onPressed: linkableMembers.isEmpty
          ? null
          : () => _showLinkSearch(context, ref, linkableMembers),
    );

    return Semantics(
      label: l10n.pkMappingPkMemberSemantics(pkMember.name),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _ResponsiveMappingRow(
            name: nameColumn,
            select: select,
            trailing: searchButton,
          ),
        ),
      ),
    );
  }
}

class _LocalMemberRow extends ConsumerWidget {
  const _LocalMemberRow({required this.localMember, required this.state});

  final domain.Member localMember;
  final PkMappingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final decision = state.decisionsByLocalId[localMember.id];
    final isPush = decision is PkPushNewDecision;
    final isSkip = decision is PkSkipDecision;
    // Unresolved-link locals carry PK fields that don't match any fetched PK
    // member. Build() defaults these to Skip; surface a caption explaining
    // the asymmetric default and the Push override path. Truly-unlinked
    // locals the user manually switched to Skip don't get this caption.
    final isUnresolvedLink = hasPluralKitLink(localMember) &&
        !hasResolvablePluralKitLink(
          localMember,
          fetchedPkUuids: state.fetchedPkUuids,
          fetchedPkIds: state.fetchedPkIds,
        );
    final showUnresolvedSkipCaption = isUnresolvedLink && isSkip;

    final nameRow = Row(
      children: [
        MemberAvatar(
          memberName: localMember.name,
          emoji: localMember.emoji,
          customColorEnabled: localMember.customColorEnabled,
          customColorHex: localMember.customColorHex,
          avatarImageData: localMember.avatarImageData,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localMember.name, style: theme.textTheme.bodyLarge),
              if (showUnresolvedSkipCaption) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.pkMappingSectionToPushUnresolvedCaption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final select = PrismSelect<String>(
      value: isPush ? 'push' : 'skip',
      items: [
        PrismSelectItem(value: 'push', label: l10n.pkMappingOptionPush),
        PrismSelectItem(value: 'skip', label: l10n.pkMappingOptionDontPush),
      ],
      onChanged: (value) {
        if (value == null) return;
        final controller = ref.read(pkMappingControllerProvider.notifier);
        if (value == 'push') {
          controller.setLocalDecision(
            localMember.id,
            PkPushNewDecision(localMemberId: localMember.id),
          );
        } else {
          controller.setLocalDecision(
            localMember.id,
            PkSkipDecision(localMemberId: localMember.id),
          );
        }
      },
    );

    return Semantics(
      label: l10n.pkMappingLocalMemberSemantics(localMember.name),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _ResponsiveMappingRow(name: nameRow, select: select),
        ),
      ),
    );
  }
}

/// Lays out a mapping row as `[name | select | trailing]` at normal text
/// scale and stacks vertically once text is scaled up enough that the fixed
/// 180px select would crush the name column. Threshold is 1.3x — picked so
/// "Larger Text" stays single-line but Dynamic Type Accessibility sizes get
/// the stacked layout.
class _ResponsiveMappingRow extends StatelessWidget {
  const _ResponsiveMappingRow({
    required this.name,
    required this.select,
    this.trailing,
  });

  final Widget name;
  final Widget select;
  final Widget? trailing;

  static const double _stackThreshold = 1.3;
  static const double _selectWidth = 180;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final stack = textScale >= _stackThreshold;

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          name,
          const SizedBox(height: 8),
          if (trailing != null)
            Row(
              children: [
                Expanded(child: select),
                const SizedBox(width: 8),
                trailing!,
              ],
            )
          else
            select,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: name),
        const SizedBox(width: 12),
        SizedBox(width: _selectWidth, child: select),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({required this.results, required this.state});
  final List<PkApplyResult> results;
  final PkMappingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    int linked = 0;
    int imported = 0;
    int pushed = 0;
    int skipped = 0;
    int failed = 0;
    int unresolvedCleared = 0;
    final failures = <PkApplyResult>[];

    // Pre-apply snapshot of locals whose PK fields didn't resolve against
    // the fetched PK system. Successful Link / PushNew decisions on these
    // locals overwrite the stale fields — count them so the summary can
    // surface "cleared N unresolved links".
    final unresolvedLocalIds = <String>{
      for (final m in state.localMembers)
        if (hasPluralKitLink(m) &&
            !hasResolvablePluralKitLink(
              m,
              fetchedPkUuids: state.fetchedPkUuids,
              fetchedPkIds: state.fetchedPkIds,
            ))
          m.id,
    };

    for (final r in results) {
      if (r.outcome == PkApplyOutcome.failed) {
        failed++;
        failures.add(r);
        continue;
      }
      switch (r.decision) {
        case PkLinkDecision(:final localMemberId):
          linked++;
          if (unresolvedLocalIds.contains(localMemberId)) unresolvedCleared++;
        case PkImportDecision():
          imported++;
        case PkPushNewDecision(:final localMemberId):
          pushed++;
          if (unresolvedLocalIds.contains(localMemberId)) unresolvedCleared++;
        case PkSkipDecision():
          skipped++;
      }
    }

    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pkMappingResultsSummary(
              linked,
              imported,
              pushed,
              skipped,
              failed,
              unresolvedCleared,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (failures.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.pkMappingErrorsHeader,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            for (final f in failures)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${_describeDecision(l10n, f.decision)}: ${f.error ?? l10n.pkMappingUnknownError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _describeDecision(AppLocalizations l10n, PkMappingDecision d) {
    switch (d) {
      case PkLinkDecision():
        return l10n.pkMappingDescribeLink(d.pkMember.name);
      case PkImportDecision():
        return l10n.pkMappingDescribeImport(d.pkMember.name);
      case PkPushNewDecision():
        return l10n.pkMappingDescribePush(d.localMemberId);
      case PkSkipDecision():
        return l10n.pkMappingDescribeSkip;
    }
  }
}
