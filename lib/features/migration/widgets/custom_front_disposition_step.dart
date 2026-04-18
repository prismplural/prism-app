import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_analysis.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Icon(
                AppIcons.labelOutlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.migrationCfStepTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.migrationCfStepExplainer,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => controller.resetToDefaults(data),
                  icon: Icon(AppIcons.refresh, size: 18),
                  label: Text(context.l10n.migrationCfResetDefaults),
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 24),
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

  String _optionDescription(BuildContext context, CfDisposition d) {
    switch (d) {
      case CfDisposition.importAsMember:
        return context.l10n.migrationCfOptionMemberDesc;
      case CfDisposition.mergeAsNote:
        return context.l10n.migrationCfOptionNoteDesc;
      case CfDisposition.convertToSleep:
        return context.l10n.migrationCfOptionSleepDesc;
      case CfDisposition.skip:
        return context.l10n.migrationCfOptionSkipDesc;
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

    return PrismSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 16,
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
                      _reasonText(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrismSegmentedControl<CfDisposition>(
            selected: selected,
            onChanged: onChanged,
            segments: [
              PrismSegment(
                value: CfDisposition.importAsMember,
                label: context.l10n.migrationCfOptionMember,
              ),
              PrismSegment(
                value: CfDisposition.mergeAsNote,
                label: context.l10n.migrationCfOptionNote,
              ),
              PrismSegment(
                value: CfDisposition.convertToSleep,
                label: context.l10n.migrationCfOptionSleep,
              ),
              PrismSegment(
                value: CfDisposition.skip,
                label: context.l10n.migrationCfOptionSkip,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _optionDescription(context, selected),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
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
