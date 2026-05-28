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
      fieldTypeId: 'long_text',
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
      fieldTypeId: 'long_text',
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
    'commit() is best-effort: a failure on one field does not block the rest '
    'and the failed field stays dirty so a retry re-stages cleanly',
    (tester) async {
      // Three text fields. The fake repo throws when asked to write
      // 'field-b'. Expect a/c to land and b to surface as a failure with
      // its dirty flag preserved.
      final repo = _FakeCustomFieldsRepository()
        ..failOnFieldId = 'field-b';
      final controller = CustomFieldsEditorController();
      final showEditor = ValueNotifier(true);
      final fields = [
        CustomField(
          id: 'field-a',
          name: 'Alpha',
          fieldType: CustomFieldType.text,
          fieldTypeId: 'text',
          createdAt: DateTime(2026, 1, 1),
        ),
        CustomField(
          id: 'field-b',
          name: 'Beta',
          fieldType: CustomFieldType.text,
          fieldTypeId: 'text',
          createdAt: DateTime(2026, 1, 1),
        ),
        CustomField(
          id: 'field-c',
          name: 'Gamma',
          fieldType: CustomFieldType.text,
          fieldTypeId: 'text',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      await tester.pumpWidget(
        _subject(
          repo: repo,
          controller: controller,
          showEditor: showEditor,
          memberId: memberId,
          fields: fields,
          values: const [],
        ),
      );
      await tester.pumpAndSettle();

      // Stage all three.
      final editables = find.byType(EditableText);
      expect(editables, findsNWidgets(3));
      await tester.enterText(editables.at(0), 'one');
      await tester.enterText(editables.at(1), 'two');
      await tester.enterText(editables.at(2), 'three');
      await tester.pump();
      expect(controller.hasPendingChanges, isTrue);

      final failures = await controller.commit();
      await tester.pump();

      // Two writes landed; the middle one is recorded as a failure.
      expect(repo.upsertedValues.map((v) => v.customFieldId), {
        'field-a',
        'field-c',
      });
      expect(failures.keys, ['field-b']);
      expect(failures['field-b'], isA<Exception>());

      // The failed field stays dirty so the next save retries it; the two
      // successful fields are clean.
      expect(controller.hasPendingChanges, isTrue);
      expect(controller.displayNameFor('field-b'), 'Beta');

      // Touch field-b again (re-stage) and let the repo accept it on retry.
      repo.failOnFieldId = null;
      // Re-trigger a change without altering the visible text: the simplest
      // path is to type the same value (the listener fires on every change).
      // Type a transient char then back to 'two' to force the dirty marker.
      await tester.enterText(editables.at(1), 'two-edit');
      await tester.pump();
      final retryFailures = await controller.commit();
      await tester.pump();
      expect(retryFailures, isEmpty);
      // Repo now has 3 writes total: a, c (from first commit) + b (retry).
      expect(
        repo.upsertedValues.map((v) => v.customFieldId).toList(),
        ['field-a', 'field-c', 'field-b'],
      );
      expect(controller.hasPendingChanges, isFalse);
    },
  );

  testWidgets(
    'staged edit survives a visibility toggle on the editor wrapper '
    '(in-sheet detail-view navigation must not destroy descendant state)',
    (tester) async {
      // The host's `_InactiveWhenHidden` must keep its wrapper shape constant
      // across visibility toggles; a `visible ? child : IgnorePointer(...)`
      // shape-toggle would drop descendant State on every navigation and take
      // staged custom-field edits with it.
      final repo = _FakeCustomFieldsRepository();
      final controller = CustomFieldsEditorController();
      final field = CustomField(
        id: 'field-a',
        name: 'Alpha',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      final inactive = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customFieldsRepositoryProvider.overrideWithValue(repo),
            customFieldsProvider.overrideWithValue(AsyncValue.data([field])),
            memberCustomFieldValuesProvider(
              memberId,
            ).overrideWithValue(const AsyncValue.data([])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: inactive,
                builder: (context, isInactive, _) {
                  return IgnorePointer(
                    ignoring: isInactive,
                    child: ExcludeFocus(
                      excluding: isInactive,
                      child: ExcludeSemantics(
                        excluding: isInactive,
                        child: CustomFieldsEditor(
                          memberId: memberId,
                          controller: controller,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'staged');
      await tester.pump();
      expect(controller.hasPendingChanges, isTrue);

      // Toggle the wrapper off and back on (mirrors navigating to main view
      // and back to the detail view). State must survive — if the wrapper
      // changed shape instead of toggling booleans, this would drop the
      // staged edit and the dirty flag.
      inactive.value = true;
      await tester.pumpAndSettle();
      inactive.value = false;
      await tester.pumpAndSettle();

      expect(controller.hasPendingChanges, isTrue);

      final failures = await controller.commit();
      await tester.pump();
      expect(failures, isEmpty);
      expect(repo.upsertedValues, hasLength(1));
      expect(repo.upsertedValues.single.customFieldId, 'field-a');
      expect(repo.upsertedValues.single.value, 'staged');
    },
  );

  test(
    'unregister() does not call notifyListeners — runs from dispose chains '
    'where the framework is locked and setState would assert',
    () {
      final controller = CustomFieldsEditorController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final state = _StubEditState('field-x');
      controller.register(state);
      controller.markDirty(state, true);
      expect(notifyCount, 1);

      controller.unregister(state);
      expect(notifyCount, 1);
      expect(controller.hasPendingChanges, isFalse);
    },
  );
}

class _StubEditState implements PendingFieldEditState {
  _StubEditState(this.fieldId);

  @override
  final String fieldId;

  @override
  String get fieldDisplayName => fieldId;

  @override
  Future<void> commitPendingValue() async {}
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

  /// When non-null, [upsertValue] throws for values targeting this field id.
  /// Used by the partial-failure test to simulate one editor failing mid-bulk.
  String? failOnFieldId;

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
    if (failOnFieldId != null && value.customFieldId == failOnFieldId) {
      throw Exception('forced failure for ${value.customFieldId}');
    }
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

  @override
  Future<void> clearTypedConfig(String fieldId) async {}
}
