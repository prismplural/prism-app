import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
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

    return PrismPageScaffold(
      // TODO(l10n): localize "Link members".
      topBar: const PrismTopBar(title: 'Link members', showBackButton: true),
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
                  // TODO(l10n)
                  'Failed to load PluralKit members:\n$e',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrismButton(
                  onPressed: () =>
                      ref.read(pkMappingControllerProvider.notifier).retry(),
                  icon: AppIcons.sync,
                  // TODO(l10n)
                  label: 'Retry',
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
    await ref.read(pkMappingControllerProvider.notifier).apply();
    final latest = ref.read(pkMappingControllerProvider).value;
    if (!context.mounted) return;
    if (latest != null &&
        latest.lastResults != null &&
        latest.lastResults!.every((r) => r.outcome != PkApplyOutcome.failed) &&
        latest.error == null) {
      Navigator.of(context).pop();
    }
  }

  void _dismiss(BuildContext context, WidgetRef ref) {
    ref.read(pkMappingControllerProvider.notifier).dismiss();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (state.pkMembers.isEmpty && state.localMembers.isEmpty) {
      return EmptyState(
        icon: Icon(AppIcons.people),
        // TODO(l10n)
        title: 'Nothing to map',
        subtitle:
            'Your PluralKit system has no members and there are no local members to push.',
      );
    }

    final unlinkedLocals = state.unlinkedLocals;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Intro copy.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            // TODO(l10n)
            'For each PluralKit member, link to an existing Prism member, '
            'import as new, or skip. Unlinked Prism members can be pushed '
            'to PluralKit below.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // -- Section 1: PK members --
        if (state.pkMembers.isNotEmpty) ...[
          const _SectionHeader(title: 'PluralKit members'), // TODO(l10n)
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
          const _SectionHeader(title: 'Local members to push'), // TODO(l10n)
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
          _ResultsSummary(results: state.lastResults!),
        ],

        if (state.error != null) ...[
          const SizedBox(height: 16),
          Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],

        // -- Apply progress --
        if (state.isApplying) ...[
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: state.applyProgress > 0 ? state.applyProgress : null,
          ),
          const SizedBox(height: 8),
          Text(
            // TODO(l10n)
            'Applying… ${(state.applyProgress * 100).toInt()}%',
            style: theme.textTheme.bodySmall,
          ),
        ],

        // -- Footer buttons --
        const SizedBox(height: 24),
        PrismButton(
          onPressed: () => _apply(context, ref),
          icon: AppIcons.checkCircle,
          label: 'Apply', // TODO(l10n)
          tone: PrismButtonTone.filled,
          expanded: true,
          enabled: !state.isApplying,
          isLoading: state.isApplying,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: () => _dismiss(context, ref),
          label: "I'll do this later", // TODO(l10n)
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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

    final items = <PrismSelectItem<String>>[
      PrismSelectItem(
        value: kPkRowImportSentinel,
        label: 'Import as new', // TODO(l10n)
        leading: Icon(AppIcons.cloudDownload),
      ),
      PrismSelectItem(
        value: kPkRowSkipSentinel,
        label: 'Skip', // TODO(l10n)
        leading: Icon(AppIcons.linkOff),
      ),
      for (final local in state.localMembers.where(
        (m) => m.pluralkitUuid == null,
      ))
        PrismSelectItem(
          value: local.id,
          label: 'Link → ${local.name}', // TODO(l10n)
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

    return Semantics(
      label: 'PluralKit member ${pkMember.name}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
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
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: PrismSelect<String>(
                  value: selectedValue,
                  items: items,
                  onChanged: (value) {
                    if (value == null) return;
                    final controller = ref.read(
                      pkMappingControllerProvider.notifier,
                    );
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
                        PkLinkDecision(
                          localMemberId: value,
                          pkMember: pkMember,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
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
    final decision = state.decisionsByLocalId[localMember.id];
    final isPush = decision is PkPushNewDecision;

    return Semantics(
      label: 'Local member ${localMember.name}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
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
                child: Text(localMember.name, style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: PrismSelect<String>(
                  value: isPush ? 'push' : 'skip',
                  items: const [
                    PrismSelectItem(
                      value: 'push',
                      label: 'Push to PK', // TODO(l10n)
                    ),
                    PrismSelectItem(
                      value: 'skip',
                      label: "Don't push", // TODO(l10n)
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final controller = ref.read(
                      pkMappingControllerProvider.notifier,
                    );
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({required this.results});
  final List<PkApplyResult> results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    int linked = 0;
    int imported = 0;
    int pushed = 0;
    int skipped = 0;
    int failed = 0;
    final failures = <PkApplyResult>[];

    for (final r in results) {
      if (r.outcome == PkApplyOutcome.failed) {
        failed++;
        failures.add(r);
        continue;
      }
      switch (r.decision) {
        case PkLinkDecision():
          linked++;
        case PkImportDecision():
          imported++;
        case PkPushNewDecision():
          pushed++;
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
            // TODO(l10n)
            '$linked linked, $imported imported, $pushed pushed, '
            '$skipped skipped, $failed failed',
            style: theme.textTheme.bodyMedium,
          ),
          if (failures.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Errors', // TODO(l10n)
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            for (final f in failures)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${_describeDecision(f.decision)}: ${f.error ?? 'unknown error'}',
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

  String _describeDecision(PkMappingDecision d) {
    switch (d) {
      case PkLinkDecision():
        return 'Link ${d.pkMember.name}';
      case PkImportDecision():
        return 'Import ${d.pkMember.name}';
      case PkPushNewDecision():
        return 'Push local ${d.localMemberId}';
      case PkSkipDecision():
        return 'Skip';
    }
  }
}
