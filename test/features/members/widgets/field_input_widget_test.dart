import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Pins FieldInputWidget.didUpdateWidget's silent-LWW behavior chosen for
/// 0.10.0 (focused user wins, unfocused staged edit is silently overwritten).
/// Revisit if a conflict-prompt is ever introduced.
void main() {
  const memberId = 'm-1';

  testWidgets(
    'peer edit silently overwrites a staged out-of-focus edit (LWW)',
    (tester) async {
      final controller = CustomFieldsEditorController();
      final field = CustomField(
        id: 'f1',
        name: 'Pronouns',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      final existing = ValueNotifier<CustomFieldValue?>(
        const CustomFieldValue(
          id: 'v1',
          customFieldId: 'f1',
          memberId: memberId,
          value: 'they/them',
        ),
      );

      await tester.pumpWidget(
        _subject(
          field: field,
          memberId: memberId,
          controller: controller,
          existing: existing,
        ),
      );
      await tester.pumpAndSettle();

      // Stage an edit, then unfocus by tapping outside the field.
      await tester.enterText(find.byType(EditableText), 'she/her');
      await tester.pump();
      expect(controller.hasPendingChanges, isTrue);

      // Unfocus: tap an empty area of the scaffold.
      await tester.tap(find.byKey(const ValueKey('unfocus-sink')));
      await tester.pumpAndSettle();

      // Peer edit arrives via the stream — simulate by rebuilding with a
      // new existingValue. This mirrors what happens when
      // memberCustomFieldValuesProvider emits an updated list.
      existing.value = const CustomFieldValue(
        id: 'v1',
        customFieldId: 'f1',
        memberId: memberId,
        value: 'he/him',
      );
      await tester.pumpAndSettle();

      // The visible text is the peer's value, and the staged edit is gone.
      expect(find.text('he/him'), findsOneWidget);
      expect(find.text('she/her'), findsNothing);
      expect(
        controller.hasPendingChanges,
        isFalse,
        reason: 'out-of-focus staged edit must be dropped silently',
      );
    },
  );

  testWidgets(
    'peer edit does NOT overwrite the visible text while user is focused — '
    'user still wins on save (dirty flag stays true)',
    (tester) async {
      final controller = CustomFieldsEditorController();
      final field = CustomField(
        id: 'f1',
        name: 'Pronouns',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      final existing = ValueNotifier<CustomFieldValue?>(
        const CustomFieldValue(
          id: 'v1',
          customFieldId: 'f1',
          memberId: memberId,
          value: 'they/them',
        ),
      );

      await tester.pumpWidget(
        _subject(
          field: field,
          memberId: memberId,
          controller: controller,
          existing: existing,
        ),
      );
      await tester.pumpAndSettle();

      // Focus the field by tapping it, then type. Focus must remain set when
      // the peer update arrives.
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'she/her');
      await tester.pump();
      expect(controller.hasPendingChanges, isTrue);

      // Peer edit arrives while user is still focused.
      existing.value = const CustomFieldValue(
        id: 'v1',
        customFieldId: 'f1',
        memberId: memberId,
        value: 'he/him',
      );
      await tester.pump();

      // User's text is preserved; dirty stays true so save will write it.
      expect(find.text('she/her'), findsOneWidget);
      expect(find.text('he/him'), findsNothing);
      expect(
        controller.hasPendingChanges,
        isTrue,
        reason: "focused user's text must survive a concurrent peer update",
      );
    },
  );

  testWidgets('when stream emits the same value the editor is already showing, '
      'didUpdateWidget short-circuits and does not toggle dirty', (
    tester,
  ) async {
    final controller = CustomFieldsEditorController();
    final field = CustomField(
      id: 'f1',
      name: 'Pronouns',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'text',
      createdAt: DateTime(2026, 1, 1),
    );
    final existing = ValueNotifier<CustomFieldValue?>(
      const CustomFieldValue(
        id: 'v1',
        customFieldId: 'f1',
        memberId: memberId,
        value: 'they/them',
      ),
    );

    await tester.pumpWidget(
      _subject(
        field: field,
        memberId: memberId,
        controller: controller,
        existing: existing,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'she/her');
    await tester.pump();
    expect(controller.hasPendingChanges, isTrue);

    // Stream re-emits the same value (no real change). didUpdateWidget
    // should early-return and leave the staged edit alone.
    existing.value = const CustomFieldValue(
      id: 'v1',
      customFieldId: 'f1',
      memberId: memberId,
      value: 'they/them',
    );
    await tester.pump();

    expect(find.text('she/her'), findsOneWidget);
    expect(controller.hasPendingChanges, isTrue);
  });

  testWidgets('month-day date fields can choose a year before 2000', (
    tester,
  ) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);
    final controller = CustomFieldsEditorController();
    final field = CustomField(
      id: 'birthday',
      name: 'Birthday',
      fieldType: CustomFieldType.date,
      datePrecision: DatePrecision.monthDay,
      createdAt: DateTime(2026, 1, 1),
    );
    const existing = CustomFieldValue(
      id: 'v1',
      customFieldId: 'birthday',
      memberId: memberId,
      value: '2000-01-15T00:00:00.000',
    );

    await tester.pumpWidget(
      _subject(
        field: field,
        memberId: memberId,
        controller: controller,
        existing: ValueNotifier<CustomFieldValue?>(existing),
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jan 15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('January 2000'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('1990'),
      find.byType(YearPicker),
      const Offset(0, 240),
    );
    await tester.tap(find.text('1990'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    expect(controller.hasPendingChanges, isTrue);
    final failures = await controller.commit();
    expect(failures, isEmpty);

    final values = await repo.getAllValues();
    expect(values, hasLength(1));
    expect(DateTime.parse(values.single.value), DateTime(1990, 1, 15));
  });
}

Widget _subject({
  required CustomField field,
  required String memberId,
  required CustomFieldsEditorController controller,
  required ValueNotifier<CustomFieldValue?> existing,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: ValueListenableBuilder<CustomFieldValue?>(
          valueListenable: existing,
          builder: (context, value, _) {
            return CustomFieldEditorScope(
              controller: controller,
              child: Column(
                children: [
                  FieldInputWidget(
                    field: field,
                    memberId: memberId,
                    existingValue: value,
                  ),
                  // Tap target for unfocusing the text field in tests.
                  GestureDetector(
                    key: const ValueKey('unfocus-sink'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: const SizedBox(height: 100, width: double.infinity),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
