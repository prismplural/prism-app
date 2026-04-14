import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart';
import 'package:prism_plurality/domain/repositories/conversation_categories_repository.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';

void main() {
  group('CategoryNotifier', () {
    test('deleteCategory sets error state when repository throws', () async {
      final container = ProviderContainer(
        overrides: [
          conversationCategoriesRepositoryProvider.overrideWithValue(
            _ThrowingCategoryRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Initialize the notifier so it enters the AsyncData state.
      await container.read(categoryNotifierProvider.future);
      expect(container.read(categoryNotifierProvider).hasError, isFalse);

      // Trigger a delete that will throw.
      await container
          .read(categoryNotifierProvider.notifier)
          .deleteCategory('nonexistent-id');

      expect(container.read(categoryNotifierProvider).hasError, isTrue);
    });

    test('updateCategory sets error state when repository throws', () async {
      final container = ProviderContainer(
        overrides: [
          conversationCategoriesRepositoryProvider.overrideWithValue(
            _ThrowingCategoryRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(categoryNotifierProvider.future);

      final category = ConversationCategory(
        id: 'test-id',
        name: 'Test',
        displayOrder: 0,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      await container
          .read(categoryNotifierProvider.notifier)
          .updateCategory(category);

      expect(container.read(categoryNotifierProvider).hasError, isTrue);
    });
  });
}

/// A fake repository where every mutation throws, for testing error paths.
class _ThrowingCategoryRepository implements ConversationCategoriesRepository {
  @override
  Stream<List<ConversationCategory>> watchAll() => Stream.value(const []);

  @override
  Future<ConversationCategory?> getById(String id) async => null;

  @override
  Future<void> create(ConversationCategory category) async =>
      throw Exception('create failed');

  @override
  Future<void> update(ConversationCategory category) async =>
      throw Exception('update failed');

  @override
  Future<void> delete(String id) async => throw Exception('delete failed');
}
