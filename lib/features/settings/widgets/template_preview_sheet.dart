import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/field_template_summary.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// The import trust surface: shows every field a template will create, with an
/// ownership reassurance and a pinned "Import fields" CTA. Returns `true` when
/// the user confirms; the caller performs the actual import.
class TemplatePreviewSheet {
  static Future<bool?> show(
    BuildContext context, {
    required FieldTemplate template,
  }) {
    return PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (ctx, scrollController) => TemplatePreviewSheetContent(
        template: template,
        scrollController: scrollController,
      ),
    );
  }
}

class TemplatePreviewSheetContent extends ConsumerStatefulWidget {
  const TemplatePreviewSheetContent({
    super.key,
    required this.template,
    this.scrollController,
  });

  final FieldTemplate template;
  final ScrollController? scrollController;

  @override
  ConsumerState<TemplatePreviewSheetContent> createState() =>
      _TemplatePreviewSheetContentState();
}

class _TemplatePreviewSheetContentState
    extends ConsumerState<TemplatePreviewSheetContent> {
  // Inflate once (toDomainFields mints fresh ids); re-map cheaply on rebuild.
  late final _domainFields = widget.template.toDomainFields();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final summary = summarizeDomainFields(
      l10n,
      _domainFields,
      memberTypeLabel: terms.singular,
      groupNameFallback: l10n.customFieldGroupUntitledFallback,
    );
    final name = summary.isNotEmpty ? summary.first.name : '';
    final fieldCount = summary.where((item) => !item.isGroup).length;

    return Column(
      children: [
        PrismSheetTopBar(title: l10n.fieldTemplateImportPreviewTitle),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.fieldTemplateFieldCount(fieldCount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _OwnershipNote(text: l10n.fieldTemplateImportOwnershipLine),
                const SizedBox(height: 8),
                for (final item in summary) FieldTemplateSummaryRow(item: item),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: PrismButton(
              label: l10n.fieldTemplateImportConfirm,
              icon: AppIcons.check,
              tone: PrismButtonTone.filled,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ),
      ],
    );
  }
}

class _OwnershipNote extends StatelessWidget {
  const _OwnershipNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSurface(
      tone: PrismSurfaceTone.subtle,
      accentColor: theme.colorScheme.primary,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AppIcons.checkCircleOutline,
            color: theme.colorScheme.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
