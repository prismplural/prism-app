import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/data/mappers/conversation_category_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/conversation_category.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/conversation_categories_repository.dart';

class DriftConversationCategoriesRepository
    with SyncRecordMixin
    implements ConversationCategoriesRepository {
  final ConversationCategoriesDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'conversation_categories';

  DriftConversationCategoriesRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.ConversationCategory>> watchAll() {
    return _dao.watchAll().map(
      (rows) => rows.map(ConversationCategoryMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.ConversationCategory?> getById(String id) async {
    final row = await _dao.getById(id);
    return row != null ? ConversationCategoryMapper.toDomain(row) : null;
  }

  @override
  Future<void> create(domain.ConversationCategory category) async {
    final companion = ConversationCategoryMapper.toCompanion(category);
    await _dao.create(companion);
    await syncRecordCreate(_table, category.id, _fields(category));
  }

  @override
  Future<void> update(domain.ConversationCategory category) async {
    final companion = ConversationCategoryMapper.toCompanion(category);
    await _dao.updateCategory(category.id, companion);
    await syncRecordUpdate(_table, category.id, _fields(category));
  }

  @override
  Future<void> delete(String id) async {
    await _dao.softDelete(id);
    await syncRecordDelete(_table, id);
  }

  Map<String, dynamic> _fields(domain.ConversationCategory c) {
    return {
      'name': c.name,
      'display_order': c.displayOrder,
      'created_at': c.createdAt.toIso8601String(),
      'modified_at': c.modifiedAt.toIso8601String(),
      'is_deleted': false,
    };
  }
}
