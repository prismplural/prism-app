import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches all custom field definitions, ordered by displayOrder.
final customFieldsProvider = StreamProvider<List<CustomField>>((ref) {
  final repo = ref.watch(customFieldsRepositoryProvider);
  return repo.watchAllFields();
});

/// Watches a single custom field by ID.
final customFieldByIdProvider =
    StreamProvider.autoDispose.family<CustomField?, String>((ref, id) {
  final repo = ref.watch(customFieldsRepositoryProvider);
  return repo.watchFieldById(id);
});

/// Watches all custom field values for a given member.
final memberCustomFieldValuesProvider =
    StreamProvider.autoDispose.family<List<CustomFieldValue>, String>((ref, memberId) {
  final repo = ref.watch(customFieldsRepositoryProvider);
  return repo.watchValuesForMember(memberId);
});

/// Notifier for custom field CRUD operations.
class CustomFieldNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createField({
    required String name,
    required CustomFieldType fieldType,
    DatePrecision? datePrecision,
    int displayOrder = 0,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      final field = CustomField(
        id: _uuid.v4(),
        name: name,
        fieldType: fieldType,
        datePrecision: datePrecision,
        displayOrder: displayOrder,
        createdAt: DateTime.now(),
      );
      await repo.createField(field);
    });
  }

  Future<void> updateField(CustomField field) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      await repo.updateField(field);
    });
  }

  Future<void> deleteField(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      await repo.deleteField(id);
    });
  }

  Future<void> reorderFields(List<CustomField> fields) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      for (int i = 0; i < fields.length; i++) {
        await repo.updateField(fields[i].copyWith(displayOrder: i));
      }
    });
  }
}

final customFieldNotifierProvider =
    AsyncNotifierProvider<CustomFieldNotifier, void>(CustomFieldNotifier.new);

/// Notifier for custom field value mutations.
class CustomFieldValueNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> setValue({
    required String customFieldId,
    required String memberId,
    required String value,
    String? existingId,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      final fieldValue = CustomFieldValue(
        id: existingId ?? _uuid.v4(),
        customFieldId: customFieldId,
        memberId: memberId,
        value: value,
      );
      await repo.upsertValue(fieldValue);
    });
  }

  Future<void> deleteValue(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(customFieldsRepositoryProvider);
      await repo.deleteValue(id);
    });
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
        CustomFieldValueNotifier.new);
