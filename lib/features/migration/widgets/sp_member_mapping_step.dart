import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/providers/sp_member_mapping_provider.dart';
import 'package:prism_plurality/features/migration/services/sp_member_mapping.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';

const kSpMemberImportSentinel = '__import__';
const _kStackedRowBreakpoint = 520.0;

class SpMemberMappingStep extends ConsumerWidget {
  const SpMemberMappingStep({super.key, required this.data});

  final SpExportData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final state = ref.watch(spMemberMappingProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(
                l10n.spMemberMappingIntro,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: PrismButton(
                  icon: AppIcons.refresh,
                  label: l10n.spMemberMappingResetDefaults,
                  onPressed: () => ref
                      .read(spMemberMappingControllerProvider)
                      .resetToDefaults(data),
                  tone: PrismButtonTone.subtle,
                  density: PrismControlDensity.compact,
                ),
              ),
              const SizedBox(height: 8),
              PrismSectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  children: [
                    for (final member in data.members)
                      _SpMemberRow(member: member, state: state),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BottomBar(
          onBack: () => ref.read(importerProvider.notifier).backToPreview(),
          onContinue: () =>
              ref.read(importerProvider.notifier).continueFromMemberMapping(),
        ),
      ],
    );
  }
}

class _SpMemberRow extends ConsumerWidget {
  const _SpMemberRow({required this.member, required this.state});

  final SpMember member;
  final SpMemberMappingState state;

  Future<void> _showLinkSearch(
    BuildContext context,
    WidgetRef ref,
    List<Member> members,
  ) async {
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      title: l10n.spMemberMappingOptionLink(member.name),
    );

    if (!context.mounted) return;
    if (result case MemberSearchResultSelected(:final memberId)) {
      ref
          .read(spMemberMappingControllerProvider)
          .setDecision(
            member.id,
            SpLinkMemberDecision(
              spMemberId: member.id,
              localMemberId: memberId,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final decision = state.decisions[member.id];
    final suggestion = _suggestionFor(member.id);

    final selectedValue = decision is SpLinkMemberDecision
        ? decision.localMemberId
        : kSpMemberImportSentinel;

    final consumedElsewhere = <String>{};
    for (final entry in state.decisions.entries) {
      if (entry.key == member.id) continue;
      final other = entry.value;
      if (other is SpLinkMemberDecision) {
        consumedElsewhere.add(other.localMemberId);
      }
    }

    final linkableMembers = state.localMembers
        .where((local) => !consumedElsewhere.contains(local.id))
        .toList(growable: false);

    final items = <PrismSelectItem<String>>[
      PrismSelectItem(
        value: kSpMemberImportSentinel,
        label: l10n.spMemberMappingOptionImportNew,
        fieldLabel: l10n.spMemberMappingOptionImportNew,
        leading: Icon(AppIcons.cloudDownload),
      ),
      for (final local in state.localMembers)
        PrismSelectItem(
          value: local.id,
          label: l10n.spMemberMappingOptionLink(local.name),
          fieldLabel: local.name,
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
      label: l10n.spMemberMappingMemberSemantics(member.name),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final stackControls =
              constraints.maxWidth < _kStackedRowBreakpoint || textScale >= 1.3;
          final menuWidth = constraints.maxWidth.clamp(280.0, 360.0).toDouble();
          final info = _MemberInfo(
            name: member.name,
            matchLabel: _matchLabel(l10n, suggestion),
          );
          final actions = _MappingActions(
            selectedValue: selectedValue,
            items: items,
            menuWidth: menuWidth,
            searchEnabled: linkableMembers.isNotEmpty,
            onChanged: (value) => _setDecision(ref, value),
            onSearch: () => _showLinkSearch(context, ref, linkableMembers),
          );

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: stackControls
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [info, const SizedBox(height: 8), actions],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: constraints.maxWidth < 680 ? 220 : 260,
                        child: actions,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _setDecision(WidgetRef ref, String? value) {
    if (value == null) return;
    final controller = ref.read(spMemberMappingControllerProvider);
    if (value == kSpMemberImportSentinel) {
      controller.setDecision(
        member.id,
        SpImportMemberDecision(spMemberId: member.id),
      );
    } else {
      controller.setDecision(
        member.id,
        SpLinkMemberDecision(spMemberId: member.id, localMemberId: value),
      );
    }
  }

  String _matchLabel(
    AppLocalizations l10n,
    SpMemberMatchSuggestion? suggestion,
  ) {
    if (suggestion?.confidence == SpMemberMatchConfidence.ambiguous) {
      return l10n.spMemberMappingMultipleMatches;
    }
    final local = suggestion?.suggestedLocal;
    if (local == null) return l10n.spMemberMappingNoMatch;
    return switch (suggestion!.confidence) {
      SpMemberMatchConfidence.persistedMapping =>
        l10n.spMemberMappingMatchedPrevious(local.name),
      SpMemberMatchConfidence.pluralKitId => l10n.spMemberMappingMatchedPk(
        local.name,
      ),
      SpMemberMatchConfidence.exactName => l10n.spMemberMappingMatchedName(
        local.name,
      ),
      SpMemberMatchConfidence.ambiguous ||
      SpMemberMatchConfidence.none => l10n.spMemberMappingNoMatch,
    };
  }

  SpMemberMatchSuggestion? _suggestionFor(String spMemberId) {
    for (final suggestion in state.suggestions) {
      if (suggestion.spMember.id == spMemberId) return suggestion;
    }
    return null;
  }
}

class _MemberInfo extends StatelessWidget {
  const _MemberInfo({required this.name, required this.matchLabel});

  final String name;
  final String matchLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 2),
        Text(
          matchLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MappingActions extends StatelessWidget {
  const _MappingActions({
    required this.selectedValue,
    required this.items,
    required this.menuWidth,
    required this.searchEnabled,
    required this.onChanged,
    required this.onSearch,
  });

  final String selectedValue;
  final List<PrismSelectItem<String>> items;
  final double menuWidth;
  final bool searchEnabled;
  final ValueChanged<String?> onChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: PrismSelect<String>(
            value: selectedValue,
            items: items,
            menuWidth: menuWidth,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        PrismGlassIconButton(
          icon: AppIcons.search,
          tooltip: l10n.search,
          size: 40,
          onPressed: searchEnabled ? onSearch : null,
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: PrismButton(
                  icon: AppIcons.arrowBack,
                  label: l10n.back,
                  onPressed: onBack,
                  tone: PrismButtonTone.subtle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrismButton(
                  icon: AppIcons.check,
                  label: l10n.spMemberMappingContinue,
                  onPressed: onContinue,
                  tone: PrismButtonTone.filled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
