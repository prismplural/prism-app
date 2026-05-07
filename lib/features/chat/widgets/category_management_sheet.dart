import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
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
  List<ConversationCategory>? _optimisticCategories;

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
        PrismToast.error(
          context,
          message: context.l10n.chatCategoriesCreateFailed(e),
        );
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
        PrismToast.error(
          context,
          message: context.l10n.chatCategoriesRenameFailed(e),
        );
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
        PrismToast.error(
          context,
          message: context.l10n.chatCategoriesDeleteFailed(e),
        );
      }
    }
  }

  Future<void> _reorderCategories(
    List<ConversationCategory> categories,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<ConversationCategory>.from(categories);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    setState(() => _optimisticCategories = reordered);
    await ref.read(categoryNotifierProvider.notifier).reorder(reordered);

    if (!mounted) return;
    final reorderState = ref.read(categoryNotifierProvider);
    if (reorderState.hasError) {
      setState(() => _optimisticCategories = null);
    }
  }

  List<ConversationCategory> _visibleCategories(
    List<ConversationCategory> categories,
  ) {
    final optimistic = _optimisticCategories;
    if (optimistic == null) return categories;

    if (!_hasSameCategorySet(optimistic, categories)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _optimisticCategories = null);
      });
      return categories;
    }

    if (_sameCategoryOrder(optimistic, categories)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _optimisticCategories = null);
      });
    }

    return optimistic;
  }

  bool _hasSameCategorySet(
    List<ConversationCategory> left,
    List<ConversationCategory> right,
  ) {
    if (left.length != right.length) return false;
    final leftIds = left.map((category) => category.id).toSet();
    final rightIds = right.map((category) => category.id).toSet();
    return leftIds.length == rightIds.length && leftIds.containsAll(rightIds);
  }

  bool _sameCategoryOrder(
    List<ConversationCategory> left,
    List<ConversationCategory> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].id != right[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(conversationCategoriesProvider);
    final bottomInset = modalBottomInsetOf(context);

    return SafeArea(
      bottom: false,
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
                final visibleCategories = _visibleCategories(categories);

                return ListView(
                  controller: widget.scrollController,
                  padding: EdgeInsets.fromLTRB(
                    PrismTokens.pageHorizontalPadding,
                    0,
                    PrismTokens.pageHorizontalPadding,
                    8 + bottomInset,
                  ),
                  children: [
                    if (visibleCategories.isEmpty)
                      PrismSectionCard(
                        child: Text(
                          context.l10n.chatCategoriesNone,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      PrismSectionCard(
                        padding: EdgeInsets.zero,
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: visibleCategories.length,
                          onReorder: (oldIndex, newIndex) {
                            _reorderCategories(
                              visibleCategories,
                              oldIndex,
                              newIndex,
                            );
                          },
                          itemBuilder: (context, index) {
                            final category = visibleCategories[index];
                            final isEditing = _editingId == category.id;
                            final isLast =
                                index == visibleCategories.length - 1;

                            return DecoratedBox(
                              key: ValueKey(category.id),
                              decoration: BoxDecoration(
                                border: isLast
                                    ? null
                                    : Border(
                                        bottom: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.08),
                                        ),
                                      ),
                              ),
                              child: PrismListRow(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    AppIcons.dragHandle,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                                title: isEditing
                                    ? PrismTextField(
                                        controller: _editController,
                                        autofocus: true,
                                        hintText: context
                                            .l10n
                                            .chatCategoriesCategoryNameHint,
                                        onSubmitted: (_) => _saveEdit(category),
                                      )
                                    : Text(category.name),
                                onTap: isEditing
                                    ? null
                                    : () {
                                        _editController.text = category.name;
                                        setState(
                                          () => _editingId = category.id,
                                        );
                                      },
                                trailing: isEditing
                                    ? PrismIconButton(
                                        icon: AppIcons.check,
                                        size: 36,
                                        iconSize: 18,
                                        onPressed: () => _saveEdit(category),
                                      )
                                    : PrismIconButton(
                                        icon: AppIcons.deleteOutline,
                                        size: 36,
                                        iconSize: 18,
                                        color: theme.colorScheme.error,
                                        onPressed: () =>
                                            _confirmDelete(category),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),

                    // Inline create field
                    const SizedBox(height: 14),
                    PrismSectionCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: PrismTextField(
                              controller: _newCategoryController,
                              hintText: context.l10n.chatCategoriesNewHint,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _createCategory(),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                    ),
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
