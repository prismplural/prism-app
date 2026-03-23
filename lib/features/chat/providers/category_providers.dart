import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches all conversation categories ordered by display order.
final conversationCategoriesProvider =
    StreamProvider<List<ConversationCategory>>((ref) {
  final repo = ref.watch(conversationCategoriesRepositoryProvider);
  return repo.watchAll();
});

/// Category CRUD notifier.
class CategoryNotifier extends Notifier<void> {
  static const _uuid = Uuid();

  @override
  void build() {}

  Future<ConversationCategory> createCategory(String name) async {
    final repo = ref.read(conversationCategoriesRepositoryProvider);

    // Determine next display order.
    final existing =
        ref.read(conversationCategoriesProvider).value ?? [];
    final maxOrder = existing.isEmpty
        ? -1
        : existing
            .map((c) => c.displayOrder)
            .reduce((a, b) => a > b ? a : b);

    final now = DateTime.now();
    final category = ConversationCategory(
      id: _uuid.v4(),
      name: name,
      displayOrder: maxOrder + 1,
      createdAt: now,
      modifiedAt: now,
    );
    await repo.create(category);
    return category;
  }

  Future<void> updateCategory(ConversationCategory category) async {
    final repo = ref.read(conversationCategoriesRepositoryProvider);
    await repo.update(category.copyWith(modifiedAt: DateTime.now()));
  }

  Future<void> deleteCategory(String id) async {
    final repo = ref.read(conversationCategoriesRepositoryProvider);
    await repo.delete(id);
  }

  Future<void> reorder(List<ConversationCategory> categories) async {
    final repo = ref.read(conversationCategoriesRepositoryProvider);
    for (var i = 0; i < categories.length; i++) {
      if (categories[i].displayOrder != i) {
        await repo.update(
          categories[i].copyWith(
            displayOrder: i,
            modifiedAt: DateTime.now(),
          ),
        );
      }
    }
  }
}

final categoryNotifierProvider =
    NotifierProvider<CategoryNotifier, void>(CategoryNotifier.new);
