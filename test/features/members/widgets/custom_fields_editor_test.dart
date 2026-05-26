import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_editor.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  const memberId = 'member-1';

  testWidgets('long text value is staged locally and is NOT persisted '
      'when the editor unmounts without commit', (tester) async {
    final repo = _FakeCustomFieldsRepository();
    final controller = CustomFieldsEditorController();
    final showEditor = ValueNotifier(true);
    final field = CustomField(
      id: 'second-bio',
      name: 'Second bio',
      fieldType: CustomFieldType.longText,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      _subject(
        repo: repo,
        controller: controller,
        showEditor: showEditor,
        memberId: memberId,
        fields: [field],
        values: const [],
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(EditableText),
      '## Private bio\n\nA longer note-level field.',
    );
    await tester.pump();

    // Edit is staged, not persisted.
    expect(repo.upsertedValues, isEmpty);
    expect(controller.hasPendingChanges, isTrue);

    showEditor.value = false;
    await tester.pumpAndSettle();

    // Closing the editor without committing drops the staged edit.
    expect(repo.upsertedValues, isEmpty);
  });

  testWidgets('commit() flushes the staged long-text value through the '
      'value notifier exactly once', (tester) async {
    final repo = _FakeCustomFieldsRepository();
    final controller = CustomFieldsEditorController();
    final showEditor = ValueNotifier(true);
    final field = CustomField(
      id: 'second-bio',
      name: 'Second bio',
      fieldType: CustomFieldType.longText,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      _subject(
        repo: repo,
        controller: controller,
        showEditor: showEditor,
        memberId: memberId,
        fields: [field],
        values: const [],
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Already staged');
    await tester.pump();
    expect(repo.upsertedValues, isEmpty);

    await controller.commit();
    await tester.pump();
    expect(repo.upsertedValues, hasLength(1));
    expect(controller.hasPendingChanges, isFalse);

    // A second commit with no further edits is a no-op.
    await controller.commit();
    expect(repo.upsertedValues, hasLength(1));
  });

  testWidgets(
    'long text edit button opens full-screen editor and stages the result '
    '(commit still required to persist)',
    (tester) async {
      final repo = _FakeCustomFieldsRepository();
      final controller = CustomFieldsEditorController();
      final showEditor = ValueNotifier(true);
      final field = CustomField(
        id: 'second-bio',
        name: 'Second bio',
        fieldType: CustomFieldType.longText,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        _subject(
          repo: repo,
          controller: controller,
          showEditor: showEditor,
          memberId: memberId,
          fields: [field],
          values: const [],
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Second bio'), findsWidgets);

      await tester.enterText(
        find.byType(EditableText).last,
        '# Full screen\n\nStaged from the larger editor.',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      // Full-screen save returns the value to the parent editor; no write yet.
      expect(repo.upsertedValues, isEmpty);
      expect(controller.hasPendingChanges, isTrue);

      await controller.commit();
      await tester.pump();
      expect(repo.upsertedValues, hasLength(1));
      expect(
        repo.upsertedValues.single.value,
        '# Full screen\n\nStaged from the larger editor.',
      );
    },
  );
}

Widget _subject({
  required _FakeCustomFieldsRepository repo,
  required CustomFieldsEditorController controller,
  required ValueNotifier<bool> showEditor,
  required String memberId,
  required List<CustomField> fields,
  required List<CustomFieldValue> values,
}) {
  return ProviderScope(
    overrides: [
      customFieldsRepositoryProvider.overrideWithValue(repo),
      customFieldsProvider.overrideWithValue(AsyncValue.data(fields)),
      memberCustomFieldValuesProvider(
        memberId,
      ).overrideWithValue(AsyncValue.data(values)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: showEditor,
          builder: (context, isVisible, _) {
            if (!isVisible) return const SizedBox.shrink();
            return CustomFieldsEditor(
              memberId: memberId,
              controller: controller,
            );
          },
        ),
      ),
    ),
  );
}

class _FakeCustomFieldsRepository implements CustomFieldsRepository {
  final upsertedValues = <CustomFieldValue>[];
  final deletedValueIds = <String>[];

  @override
  Future<void> createField(CustomField field) async {}

  @override
  Future<void> createFieldFromImport(CustomField field) async {}

  @override
  Future<void> deleteField(String id, {bool deleteChildren = false}) async {}

  @override
  Future<void> deleteValue(String id) async {
    deletedValueIds.add(id);
  }

  @override
  Future<void> deleteValuesForField(String fieldId) async {}

  @override
  Future<void> deleteValuesForMember(String memberId) async {}

  @override
  Future<void> deleteAllFields() async {}

  @override
  Future<List<CustomFieldValue>> getAllValues() async => const [];

  @override
  Future<CustomField?> getFieldById(String id) async => null;

  @override
  Future<CustomFieldValue?> getValueForField(
    String fieldId,
    String memberId,
  ) async => null;

  @override
  Future<void> updateField(CustomField field) async {}

  @override
  Future<void> renameField(String fieldId, String newName) async {}

  @override
  Future<void> moveFieldToParent(String fieldId, String? newParentId) async {}

  @override
  Future<void> setFieldDatePrecision(
    String fieldId,
    DatePrecision? newPrecision,
  ) async {}

  @override
  Future<void> setFieldDisplayOrder(String fieldId, int newOrder) async {}

  @override
  Future<void> reorderFields(List<CustomField> fields) async {}

  @override
  Future<void> upsertValue(CustomFieldValue value) async {
    upsertedValues.add(value);
  }

  @override
  Stream<List<CustomField>> watchAllFields() => const Stream.empty();

  @override
  Future<List<CustomField>> getAllFields() async => const [];

  @override
  Stream<CustomField?> watchFieldById(String id) => const Stream.empty();

  @override
  Stream<List<CustomFieldValue>> watchValuesForMember(String memberId) =>
      const Stream.empty();

  @override
  Stream<List<CustomFieldValue>> watchValuesForField(String fieldId) =>
      const Stream.empty();

  @override
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) async {}
}
