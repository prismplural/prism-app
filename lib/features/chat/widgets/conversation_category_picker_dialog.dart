import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

class ConversationCategoryPickerResult {
  const ConversationCategoryPickerResult(this.categoryId);

  final String? categoryId;
}

Future<ConversationCategoryPickerResult?> showConversationCategoryPickerDialog(
  BuildContext context, {
  required List<ConversationCategory> categories,
  required String? currentCategoryId,
}) {
  final effectiveCurrentCategoryId =
      categories.any((category) => category.id == currentCategoryId)
      ? currentCategoryId
      : null;

  return PrismDialog.show<ConversationCategoryPickerResult>(
    context: context,
    title: context.l10n.chatInfoCategory,
    builder: (dialogContext) => _ConversationCategoryPickerDialogBody(
      categories: categories,
      currentCategoryId: effectiveCurrentCategoryId,
    ),
  );
}

class _ConversationCategoryPickerDialogBody extends StatelessWidget {
  const _ConversationCategoryPickerDialogBody({
    required this.categories,
    required this.currentCategoryId,
  });

  final List<ConversationCategory> categories;
  final String? currentCategoryId;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConversationCategoryOptionRow(
              label: context.l10n.chatInfoCategoryNone,
              categoryId: null,
              selected: currentCategoryId == null,
            ),
            for (final category in categories)
              _ConversationCategoryOptionRow(
                label: category.name,
                categoryId: category.id,
                selected: currentCategoryId == category.id,
              ),
          ],
        ),
      ),
    );
  }
}

class _ConversationCategoryOptionRow extends StatelessWidget {
  const _ConversationCategoryOptionRow({
    required this.label,
    required this.categoryId,
    required this.selected,
  });

  final String label;
  final String? categoryId;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismListRow(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      selected: selected,
      title: Text(label),
      trailing: selected
          ? Icon(AppIcons.checkRounded, color: theme.colorScheme.primary)
          : null,
      onTap: () => Navigator.of(
        context,
      ).pop(ConversationCategoryPickerResult(categoryId)),
    );
  }
}
