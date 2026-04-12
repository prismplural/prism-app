import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// A sheet for managing conversation categories (create, rename, reorder, delete).
///
/// Use via [PrismSheet.show].
class CategoryManagementSheet extends ConsumerStatefulWidget {
  const CategoryManagementSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  static Future<void> show(BuildContext context) {
    return PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          CategoryManagementSheet(scrollController: scrollController),
    );
  }

  @override
  ConsumerState<CategoryManagementSheet> createState() =>
      _CategoryManagementSheetState();
}

class _CategoryManagementSheetState
    extends ConsumerState<CategoryManagementSheet> {
  final _newCategoryController = TextEditingController();
  String? _editingId;
  final _editController = TextEditingController();

  @override
  void dispose() {
    _newCategoryController.dispose();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _createCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) return;

    try {
      await ref.read(categoryNotifierProvider.notifier).createCategory(name);
      _newCategoryController.clear();
      Haptics.success();
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatCategoriesCreateFailed(e));
      }
    }
  }

  Future<void> _saveEdit(ConversationCategory category) async {
    final name = _editController.text.trim();
    if (name.isEmpty || name == category.name) {
      setState(() => _editingId = null);
      return;
    }

    try {
      await ref
          .read(categoryNotifierProvider.notifier)
          .updateCategory(category.copyWith(name: name));
      setState(() => _editingId = null);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatCategoriesRenameFailed(e));
      }
    }
  }

  Future<void> _confirmDelete(ConversationCategory category) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.chatCategoriesDeleteTitle(category.name),
      message: context.l10n.chatCategoriesDeleteMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      Haptics.heavy();
      await ref
          .read(categoryNotifierProvider.notifier)
          .deleteCategory(category.id);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatCategoriesDeleteFailed(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(conversationCategoriesProvider);

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(title: context.l10n.chatCategoriesTitle),
          const SizedBox(height: 8),
          Expanded(
            child: categoriesAsync.when(
              loading: () =>
                  const SizedBox(height: 200, child: PrismLoadingState()),
              error: (e, _) => SizedBox(
                height: 200,
                child: Center(child: Text('Error: $e')),
              ),
              data: (categories) {
                return ListView(
                  controller: widget.scrollController,
                  children: [
                    if (categories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          context.l10n.chatCategoriesNone,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          itemCount: categories.length,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex--;
                            final reordered = List<ConversationCategory>.from(
                              categories,
                            );
                            final item = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, item);
                            ref
                                .read(categoryNotifierProvider.notifier)
                                .reorder(reordered);
                          },
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final isEditing = _editingId == category.id;

                            return PrismListRow(
                              key: ValueKey(category.id),
                              padding: EdgeInsets.zero,
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: Icon(AppIcons.dragHandle),
                              ),
                              title: isEditing
                                  ? PrismTextField(
                                      controller: _editController,
                                      autofocus: true,
                                      hintText: context.l10n.chatCategoriesCategoryNameHint,
                                      onSubmitted: (_) => _saveEdit(category),
                                    )
                                  : GestureDetector(
                                      onTap: () {
                                        _editController.text = category.name;
                                        setState(
                                          () => _editingId = category.id,
                                        );
                                      },
                                      child: Text(category.name),
                                    ),
                              trailing: isEditing
                                  ? PrismIconButton(
                                      icon: AppIcons.check,
                                      size: 32,
                                      iconSize: 18,
                                      onPressed: () => _saveEdit(category),
                                    )
                                  : PrismIconButton(
                                      icon: AppIcons.deleteOutline,
                                      size: 32,
                                      iconSize: 18,
                                      color: theme.colorScheme.error,
                                      onPressed: () => _confirmDelete(category),
                                    ),
                            );
                          },
                        ),
                      ),

                    // Inline create field
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PrismTextField(
                            controller: _newCategoryController,
                            hintText: context.l10n.chatCategoriesNewHint,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _createCategory(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PrismIconButton(
                          icon: AppIcons.addCircle,
                          color: theme.colorScheme.primary,
                          size: 40,
                          iconSize: 20,
                          onPressed: _createCategory,
                          tooltip: context.l10n.chatCategoriesAddTooltip,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
