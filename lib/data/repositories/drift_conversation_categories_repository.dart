import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/data/mappers/conversation_category_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
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

  @override
  AppDatabase get syncOutboxDatabase => _dao.attachedDatabase;

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
    await runSyncedWrite(() async {
      final companion = ConversationCategoryMapper.toCompanion(category);
      await _dao.create(companion);
      await syncRecordCreate(_table, category.id, _fields(category));
    });
  }

  @override
  Future<void> update(domain.ConversationCategory category) async {
    await runSyncedWrite(() async {
      final existingRow = await _dao.getByIdRow(category.id);
      if (existingRow == null || existingRow.isDeleted) return;

      final changedFields = diffSyncFields(
        _categoryFieldsFromRow(existingRow),
        _fields(category),
      );
      if (changedFields.isEmpty) return;

      final companion = _partialCategoryCompanion(changedFields);
      await _dao.updateCategory(category.id, companion);
      await syncRecordUpdate(_table, category.id, changedFields);
    });
  }

  @override
  Future<void> delete(String id) async {
    await runSyncedWrite(() async {
      await _dao.softDelete(id);
      await syncRecordDelete(_table, id);
    });
  }

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC.
  @visibleForTesting
  Map<String, dynamic> debugCategoryFields(domain.ConversationCategory c) =>
      _fields(c);

  ConversationCategoriesCompanion _partialCategoryCompanion(
    Map<String, dynamic> fields,
  ) {
    return ConversationCategoriesCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      displayOrder: fields.containsKey('display_order')
          ? Value(fields['display_order'] as int)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      modifiedAt: fields.containsKey('modified_at')
          ? Value(parseSyncDateTime(fields['modified_at']))
          : const Value.absent(),
    );
  }

  Map<String, dynamic> _categoryFieldsFromRow(ConversationCategoryRow row) {
    return {
      'name': row.name,
      'display_order': row.displayOrder,
      'created_at': toSyncUtc(row.createdAt),
      'modified_at': toSyncUtc(row.modifiedAt),
      'is_deleted': row.isDeleted,
    };
  }

  Map<String, dynamic> _fields(domain.ConversationCategory c) =>
      categoryFields(c);

  /// Field-map builder for conversation-category sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `create()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> categoryFields(domain.ConversationCategory c) {
    return {
      'name': c.name,
      'display_order': c.displayOrder,
      'created_at': toSyncUtc(c.createdAt),
      'modified_at': toSyncUtc(c.modifiedAt),
      'is_deleted': false,
    };
  }
}
