import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_editor.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  const memberId = 'member-1';

  testWidgets('long text value saves when editor closes without blur', (
    tester,
  ) async {
    final repo = _FakeCustomFieldsRepository();
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

    expect(repo.upsertedValues, isEmpty);

    showEditor.value = false;
    await tester.pumpAndSettle();

    expect(repo.upsertedValues, hasLength(1));
    expect(repo.upsertedValues.single.customFieldId, field.id);
    expect(repo.upsertedValues.single.memberId, memberId);
    expect(
      repo.upsertedValues.single.value,
      '## Private bio\n\nA longer note-level field.',
    );
  });

  testWidgets(
    'closing editor does not duplicate a blur-saved long text value',
    (tester) async {
      final repo = _FakeCustomFieldsRepository();
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
          showEditor: showEditor,
          memberId: memberId,
          fields: [field],
          values: const [],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(EditableText));
      await tester.enterText(find.byType(EditableText), 'Already saved');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(repo.upsertedValues, hasLength(1));

      showEditor.value = false;
      await tester.pumpAndSettle();

      expect(repo.upsertedValues, hasLength(1));
    },
  );

  testWidgets('long text edit button opens full-screen editor and saves', (
    tester,
  ) async {
    final repo = _FakeCustomFieldsRepository();
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
      '# Full screen\n\nSaved from the larger editor.',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(repo.upsertedValues, hasLength(1));
    expect(
      repo.upsertedValues.single.value,
      '# Full screen\n\nSaved from the larger editor.',
    );
  });
}

Widget _subject({
  required _FakeCustomFieldsRepository repo,
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
            return CustomFieldsEditor(memberId: memberId);
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
  Future<void> deleteField(String id) async {}

  @override
  Future<void> deleteValue(String id) async {
    deletedValueIds.add(id);
  }

  @override
  Future<void> deleteValuesForField(String fieldId) async {}

  @override
  Future<void> deleteValuesForMember(String memberId) async {}

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
  Future<void> reorderFields(List<CustomField> fields) async {}

  @override
  Future<void> upsertValue(CustomFieldValue value) async {
    upsertedValues.add(value);
  }

  @override
  Stream<List<CustomField>> watchAllFields() => const Stream.empty();

  @override
  Stream<CustomField?> watchFieldById(String id) => const Stream.empty();

  @override
  Stream<List<CustomFieldValue>> watchValuesForMember(String memberId) =>
      const Stream.empty();

  @override
  Stream<List<CustomFieldValue>> watchValuesForField(String fieldId) =>
      const Stream.empty();
}
