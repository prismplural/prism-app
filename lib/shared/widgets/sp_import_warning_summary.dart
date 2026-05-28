import 'package:flutter/material.dart';
import 'package:prism_plurality/features/migration/services/sp_import_warning_classifier.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';

class SpImportWarningSummary extends StatefulWidget {
  const SpImportWarningSummary({
    super.key,
    required this.warnings,
    this.onRetryAvatars,
    this.retryInProgress = false,
  });

  final List<String> warnings;
  final VoidCallback? onRetryAvatars;
  final bool retryInProgress;

  @override
  State<SpImportWarningSummary> createState() => _SpImportWarningSummaryState();
}

class _SpImportWarningSummaryState extends State<SpImportWarningSummary> {
  final Set<SpImportWarningKind> _expandedKinds = {};
  final Map<SpImportWarningKind, FocusNode> _focusNodes = {};
  late List<SpImportWarningCategory> _categories;

  @override
  void initState() {
    super.initState();
    _categories = SpImportWarningClassifier.classify(widget.warnings);
  }

  @override
  void didUpdateWidget(SpImportWarningSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.warnings, widget.warnings)) {
      _categories = SpImportWarningClassifier.classify(widget.warnings);
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeFor(SpImportWarningKind kind) {
    return _focusNodes.putIfAbsent(kind, FocusNode.new);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    if (categories.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;

    final sections = <Widget>[];
    for (var i = 0; i < categories.length; i++) {
      if (i > 0) sections.add(const SizedBox(height: 12));
      sections.add(_buildSection(context, theme, l10n, categories[i]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.spImportWarningsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.spImportWarningsSubtitle,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...sections,
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    SpImportWarningCategory category,
  ) {
    final kind = category.kind;
    final severity = category.severity;
    final (icon, color) = _severityIcon(severity, theme);

    final children = _buildChildren(context, theme, l10n, category);

    return PrismExpandableSection(
      leading: Icon(icon, color: color),
      title: Text(_headlineFor(kind, l10n)),
      subtitle: Text(
        _explanationFor(kind, l10n),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCountChip(context, theme, category, color),
          if (_showRetryFor(category) && widget.onRetryAvatars != null) ...[
            const SizedBox(width: 8),
            PrismButton(
              tone: PrismButtonTone.outlined,
              icon: AppIcons.refresh,
              onPressed: widget.retryInProgress ? () {} : widget.onRetryAvatars!,
              enabled: !widget.retryInProgress,
              label: widget.retryInProgress
                  ? l10n.spImportWarningsRetrying
                  : l10n.spImportWarningsRetry,
              density: PrismControlDensity.compact,
            ),
          ],
        ],
      ),
      accentColor: color,
      children: children,
      onExpansionChanged: (expanded) {
        if (expanded) {
          final node = _focusNodeFor(kind);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            node.requestFocus();
          });
        }
      },
    );
  }

  Widget _buildCountChip(
    BuildContext context,
    ThemeData theme,
    SpImportWarningCategory category,
    Color severityColor,
  ) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(8),
        ),
      ),
      child: Text(
        '${category.count}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: severityColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Semantics(
      label: context.l10n.spImportWarningsCountSemantics(category.count),
      container: true,
      child: ExcludeSemantics(child: chip),
    );
  }

  List<Widget> _buildChildren(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    SpImportWarningCategory category,
  ) {
    final kind = category.kind;
    final warnings = category.warnings;
    final showAll = _expandedKinds.contains(kind);
    final focusNode = _focusNodeFor(kind);

    final displayCount = (warnings.length <= 10 || showAll) ? warnings.length : 10;

    final warningList = ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayCount,
      itemBuilder: (context, i) {
        final text = Text(warnings[i], style: theme.textTheme.bodySmall);
        if (i == 0) {
          return Focus(focusNode: focusNode, child: text);
        }
        return text;
      },
    );

    if (warnings.length > 10 && !showAll) {
      return [
        warningList,
        PrismButton(
          tone: PrismButtonTone.outlined,
          density: PrismControlDensity.compact,
          label: l10n.spImportWarningsShowAll(warnings.length - 10),
          onPressed: () {
            setState(() => _expandedKinds.add(kind));
          },
        ),
      ];
    }

    return [warningList];
  }

  bool _showRetryFor(SpImportWarningCategory category) =>
      category.kind == SpImportWarningKind.avatars;
}

(IconData, Color) _severityIcon(
  SpImportWarningSeverity severity,
  ThemeData theme,
) {
  return switch (severity) {
    SpImportWarningSeverity.info => (
      AppIcons.infoOutline,
      theme.colorScheme.primary,
    ),
    SpImportWarningSeverity.warning => (
      AppIcons.warningRounded,
      AppColors.warning,
    ),
    SpImportWarningSeverity.error => (
      AppIcons.errorOutline,
      AppColors.error,
    ),
  };
}

String _headlineFor(SpImportWarningKind kind, AppLocalizations l10n) {
  return switch (kind) {
    SpImportWarningKind.avatars => l10n.spImportWarningsAvatarsHeadline,
    SpImportWarningKind.missingReferences =>
      l10n.spImportWarningsMissingReferencesHeadline,
    SpImportWarningKind.customFrontAdjustments =>
      l10n.spImportWarningsCustomFrontAdjustmentsHeadline,
    SpImportWarningKind.encryptedMessages =>
      l10n.spImportWarningsEncryptedMessagesHeadline,
    SpImportWarningKind.dataQuality => l10n.spImportWarningsDataQualityHeadline,
    SpImportWarningKind.syncEmission =>
      l10n.spImportWarningsSyncEmissionHeadline,
    SpImportWarningKind.other => l10n.spImportWarningsOtherHeadline,
  };
}

String _explanationFor(SpImportWarningKind kind, AppLocalizations l10n) {
  return switch (kind) {
    SpImportWarningKind.avatars => l10n.spImportWarningsAvatarsExplanation,
    SpImportWarningKind.missingReferences =>
      l10n.spImportWarningsMissingReferencesExplanation,
    SpImportWarningKind.customFrontAdjustments =>
      l10n.spImportWarningsCustomFrontAdjustmentsExplanation,
    SpImportWarningKind.encryptedMessages =>
      l10n.spImportWarningsEncryptedMessagesExplanation,
    SpImportWarningKind.dataQuality =>
      l10n.spImportWarningsDataQualityExplanation,
    SpImportWarningKind.syncEmission =>
      l10n.spImportWarningsSyncEmissionExplanation,
    SpImportWarningKind.other => l10n.spImportWarningsOtherExplanation,
  };
}
