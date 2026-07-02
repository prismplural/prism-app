import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/custom_fields/orphan_promotion.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';

/// Watches all custom field definitions, ordered by displayOrder.
///
/// **Raw on-disk view.** Children with a `parentFieldId` are emitted as-is,
/// including ones whose parent is missing or non-group. Consumers that render
/// a top-level list should watch [topLevelCustomFieldsProvider] instead;
/// consumers that need the exact on-disk parent (e.g. the group editor that
/// filters by `parentFieldId == groupId`) should keep using this provider.
final customFieldsProvider = StreamProvider<List<CustomField>>((ref) {
  final repo = ref.watch(customFieldsRepositoryProvider);
  return repo.watchAllFields();
});

/// Render-layer view of all custom fields with orphaned children promoted to
/// the top level.
///
/// A child whose parent is missing/soft-deleted or is not a group-typed field
/// has its `parentFieldId` cleared in the projection. This is a purely
/// in-memory transform; the DB row is unchanged so the child re-attaches on
/// the next stream emission if the parent comes back via sync.
///
/// Use this for any UI that displays a top-level list of custom fields. Do
/// **not** use it on write paths — writing back a promoted instance would
/// propagate the cleared parent to disk.
final topLevelCustomFieldsProvider = Provider<AsyncValue<List<CustomField>>>(
  (ref) => ref.watch(customFieldsProvider).whenData(promoteOrphansForRender),
);

/// Watches a single custom field by ID.
final customFieldByIdProvider = StreamProvider.autoDispose
    .family<CustomField?, String>((ref, id) {
      final repo = ref.watch(customFieldsRepositoryProvider);
      return repo.watchFieldById(id);
    });

/// Watches all custom field values for a given member.
final memberCustomFieldValuesProvider = StreamProvider.autoDispose
    .family<List<CustomFieldValue>, String>((ref, memberId) {
      final repo = ref.watch(customFieldsRepositoryProvider);
      return repo.watchValuesForMember(memberId);
    });

/// Watches all member values for a given custom field.
final customFieldValuesForFieldProvider = StreamProvider.autoDispose
    .family<List<CustomFieldValue>, String>((ref, fieldId) {
      final repo = ref.watch(customFieldsRepositoryProvider);
      return repo.watchValuesForField(fieldId);
    });

/// Notifier for custom field CRUD operations.
class CustomFieldNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  /// Returns the caught error or `null` on success. Callers must check —
  /// `AsyncValue.guard` would otherwise swallow `InvalidFieldTypeException`
  /// and other failures into state with no UI surface.
  Future<Object?> createField({
    String? id,
    required String name,
    required CustomFieldType fieldType,
    DatePrecision? datePrecision,
    int? displayOrder,
    String? fieldTypeId,
    CustomFieldTypeConfig? typeConfig,
    String? parentFieldId,
  }) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      final field = CustomField(
        id: id ?? _uuid.v4(),
        name: name,
        fieldType: fieldType,
        datePrecision: datePrecision,
        displayOrder: displayOrder ?? 0,
        createdAt: DateTime.now(),
        fieldTypeId: fieldTypeId,
        typeConfig: typeConfig,
        parentFieldId: parentFieldId,
      );
      try {
        if (displayOrder == null && repo is DriftCustomFieldsRepository) {
          await repo.createFieldAtEnd(field);
        } else {
          final resolvedDisplayOrder = await _resolveCreateDisplayOrder(
            requestedDisplayOrder: displayOrder,
            parentFieldId: parentFieldId,
          );
          await repo.createField(
            field.copyWith(displayOrder: resolvedDisplayOrder),
          );
        }
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  Future<int> _resolveCreateDisplayOrder({
    required int? requestedDisplayOrder,
    required String? parentFieldId,
  }) async {
    if (requestedDisplayOrder != null) return requestedDisplayOrder;

    final repo = ref.read(customFieldsRepositoryProvider);
    final fields = await repo.getAllFields();
    var nextOrder = 0;
    for (final field in fields) {
      if (field.parentFieldId != parentFieldId) continue;
      if (field.displayOrder >= nextOrder) {
        nextOrder = field.displayOrder + 1;
      }
    }
    return nextOrder;
  }

  /// Updates [field] via the repository (full-row diff path — for cases
  /// where the caller legitimately changed the `fieldTypeId` or otherwise
  /// needs whole-row semantics). UI edits of individual columns should
  /// prefer the patch wrappers ([renameField], [setFieldDatePrecision],
  /// [writeTypedConfig]) for CRDT correctness.
  ///
  /// Returns the caught error (or `null` on success). Callers MUST check
  /// the return value and surface non-null errors via toast.
  Future<Object?> updateField(CustomField field) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.updateField(field);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  /// Patch [fieldId]'s parent to [newParentId]. Pass `null` to move to top
  /// level.
  ///
  /// Returns the [InvalidFieldTypeException] or [DepthLimitExceededException]
  /// when the move is rejected, or `null` on success. Callers should surface
  /// the returned exception via toast/snackbar so user-explicit moves fail
  /// loudly rather than silently swallow. Storage/unknown errors still flow
  /// through `AsyncValue.guard` into `state`.
  Future<Exception?> moveFieldToParent(
    String fieldId,
    String? newParentId,
  ) async {
    Exception? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.moveFieldToParent(fieldId, newParentId);
      } on InvalidFieldTypeException catch (e) {
        failure = e;
        rethrow;
      } on DepthLimitExceededException catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  /// Patch [fieldId]'s name. Single-column write — peers' concurrent edits to
  /// other columns are preserved.
  ///
  /// Returns the caught error (e.g. storage failure) or `null` on success.
  /// Callers should surface non-null returns via toast so failures don't
  /// silently swallow.
  Future<Object?> renameField(String fieldId, String newName) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.renameField(fieldId, newName);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  /// Patch [fieldId]'s date precision. Single-column write.
  ///
  /// Returns the caught error or `null` on success — see [renameField] for
  /// the rationale.
  Future<Object?> setFieldDatePrecision(
    String fieldId,
    DatePrecision? newPrecision,
  ) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.setFieldDatePrecision(fieldId, newPrecision);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  /// Write a whole-config blob for [fieldId] using the LWW invariant.
  ///
  /// Any config mutation must write the entire blob — no field-level
  /// merge inside the JSON. CRDT convergence depends on this contract.
  ///
  /// Returns the caught error (codec encoding failure, storage failure)
  /// or `null` on success. Callers MUST check the return value and surface
  /// non-null errors via toast — choice option edits, slider config edits,
  /// etc. all flow through here and silent failures would be a UX dead-end.
  Future<Object?> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.writeTypedConfig(fieldId, newConfig);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  /// Clear [fieldId]'s typeConfig (resets `type_config_json` to NULL).
  /// Returns the caught error or `null` on success — callers must check.
  Future<Object?> clearTypedConfig(String fieldId) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.clearTypedConfig(fieldId);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  Future<void> deleteField(String id, {bool deleteChildren = false}) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      await repo.deleteField(id, deleteChildren: deleteChildren);
    });
  }

  Future<void> reorderFields(List<CustomField> fields) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      await repo.reorderFields(fields);
    });
  }
}

final customFieldNotifierProvider =
    AsyncNotifierProvider<CustomFieldNotifier, void>(CustomFieldNotifier.new);

/// Notifier for custom field value mutations.
class CustomFieldValueNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Writes [value] for ([customFieldId], [memberId]) via the repository.
  ///
  /// Returns the caught error (or `null` on success). Callers MUST check the
  /// return value: the member edit sheet's bulk-commit path uses this to
  /// surface per-field failures via toast and keep the failed editor dirty
  /// so a retry re-stages cleanly. `AsyncValue.guard` would otherwise swallow
  /// the error into state with no UI signal.
  Future<Object?> setValue({
    required String customFieldId,
    required String memberId,
    required String value,
  }) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        final deterministicId = deriveCustomFieldValueId(
          customFieldId: customFieldId,
          memberId: memberId,
        );
        final fieldValue = CustomFieldValue(
          id: deterministicId,
          customFieldId: customFieldId,
          memberId: memberId,
          value: value,
        );
        await repo.upsertValue(fieldValue);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  /// Clears the active value for ([customFieldId], [memberId]), resolving its
  /// live row id at commit time so a minted refill can't leave the clear
  /// addressing a dead id. No-op when nothing is set. Returns the caught error
  /// (or `null`) — see [setValue] for why callers must check the return value.
  Future<Object?> deleteValueFor({
    required String customFieldId,
    required String memberId,
  }) async {
    Object? failure;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      try {
        await repo.deleteValueFor(customFieldId, memberId);
      } catch (e) {
        failure = e;
        rethrow;
      }
    });
    return failure;
  }

  Future<void> deleteValuesForMember(String memberId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      await repo.deleteValuesForMember(memberId);
    });
  }
}

final customFieldValueNotifierProvider =
    AsyncNotifierProvider<CustomFieldValueNotifier, void>(
      CustomFieldValueNotifier.new,
    );
