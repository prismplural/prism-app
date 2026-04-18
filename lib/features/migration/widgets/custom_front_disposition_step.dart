import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_analysis.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Step shown between the preview and the actual import when the SP export
/// contains custom fronts. Lets the user decide, per CF, how each one should
/// be handled.
class CustomFrontDispositionStep extends ConsumerWidget {
  const CustomFrontDispositionStep({super.key, required this.data});

  final SpExportData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dispositions = ref.watch(cfDispositionProvider);
    final suggestions = ref.watch(cfSuggestionsProvider);
    final controller = ref.read(cfDispositionControllerProvider);
    final usage = analyzeCfUsage(data);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Text(
                context.l10n.migrationCfStepExplainer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _OptionsLegend(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => controller.resetToDefaults(data),
                  icon: Icon(AppIcons.refresh, size: 16),
                  label: Text(
                    context.l10n.migrationCfResetDefaults,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final cf in data.customFronts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CfCard(
                    cf: cf,
                    stats: usage[cf.id] ?? const CfUsageStats(),
                    suggestion: suggestions[cf.id],
                    selected: dispositions[cf.id] ??
                        suggestions[cf.id]?.disposition ??
                        CfDisposition.mergeAsNote,
                    onChanged: (value) =>
                        controller.setDisposition(cf.id, value),
                  ),
                ),
            ],
          ),
        ),
        _BottomBar(
          onBack: () =>
              ref.read(importerProvider.notifier).backToPreview(),
          onContinue: () => ref
              .read(importerProvider.notifier)
              .continueFromDispositions(),
        ),
      ],
    );
  }
}

class _CfCard extends StatelessWidget {
  const _CfCard({
    required this.cf,
    required this.stats,
    required this.suggestion,
    required this.selected,
    required this.onChanged,
  });

  final SpCustomFront cf;
  final CfUsageStats stats;
  final CfSuggestion? suggestion;
  final CfDisposition selected;
  final ValueChanged<CfDisposition> onChanged;

  Color _swatchColor(ThemeData theme) {
    final raw = cf.color;
    if (raw == null || raw.isEmpty) return theme.colorScheme.primary;
    final cleaned = raw.startsWith('#') ? raw.substring(1) : raw;
    final hex = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return theme.colorScheme.primary;
    return Color(parsed);
  }

  String _optionLabel(BuildContext context, CfDisposition d) {
    switch (d) {
      case CfDisposition.importAsMember:
        return context.l10n.migrationCfOptionMember;
      case CfDisposition.mergeAsNote:
        return context.l10n.migrationCfOptionNote;
      case CfDisposition.convertToSleep:
        return context.l10n.migrationCfOptionSleep;
      case CfDisposition.skip:
        return context.l10n.migrationCfOptionSkip;
    }
  }

  String _reasonText(BuildContext context) {
    final reason = suggestion?.disposition;
    switch (reason) {
      case CfDisposition.convertToSleep:
        return context.l10n.migrationCfReasonSleepName;
      case CfDisposition.skip:
        return context.l10n.migrationCfReasonZeroUsage;
      case CfDisposition.importAsMember:
        return context.l10n.migrationCfReasonPrimaryHeavy;
      case CfDisposition.mergeAsNote:
        if (stats.asPrimary == 0 && stats.asCoFronter > 0) {
          return context.l10n.migrationCfReasonCoFronterOnly;
        }
        return context.l10n.migrationCfReasonFallback;
      case null:
        return context.l10n.migrationCfReasonFallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: _swatchColor(theme),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cf.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.migrationCfUsageSummary(
                        stats.asPrimary,
                        stats.asCoFronter,
                        stats.asTimerTarget,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _reasonText(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final option in CfDisposition.values)
            _OptionRow(
              selected: selected == option,
              label: _optionLabel(context, option),
              onTap: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final outline = theme.colorScheme.outlineVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? primary : outline,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegendLine(
            label: context.l10n.migrationCfOptionMember,
            description: context.l10n.migrationCfOptionMemberDesc,
          ),
          const SizedBox(height: 6),
          _LegendLine(
            label: context.l10n.migrationCfOptionNote,
            description: context.l10n.migrationCfOptionNoteDesc,
          ),
          const SizedBox(height: 6),
          _LegendLine(
            label: context.l10n.migrationCfOptionSleep,
            description: context.l10n.migrationCfOptionSleepDesc,
          ),
          const SizedBox(height: 6),
          _LegendLine(
            label: context.l10n.migrationCfOptionSkip,
            description: context.l10n.migrationCfOptionSkipDesc,
          ),
        ],
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label — ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: PrismButton(
                onPressed: onBack,
                label: context.l10n.migrationCfBack,
                tone: PrismButtonTone.outlined,
                expanded: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                onPressed: onContinue,
                icon: AppIcons.download,
                label: context.l10n.migrationCfContinue,
                tone: PrismButtonTone.filled,
                expanded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
