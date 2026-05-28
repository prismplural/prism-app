// ignore_for_file: avoid_print
//
// NOTE: Widget tests in test/features/ currently fail to compile because of a
// pre-existing FFI dependency chain (sqlite3_flutter_libs) that requires a
// native build artifact. These tests are committed so they run automatically
// once that blocker is resolved.
//
// To run the pure-Dart encoder/decoder edge-case tests that don't need FFI,
// run them directly:
//
//   flutter test test/domain/models/choice_field_value_codec_test.dart
//
// The tests below cover the WIDGET layer contracts per spec Task 8 §4.
// Each group documents its pattern even when the test can't be driven headlessly.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/choice_field_widgets.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _memberId = 'member-1';

ChoiceOption _option(String id, String label, {String? color, int order = 0}) {
  return ChoiceOption(id: id, label: label, colorHex: color, sortOrder: order);
}

ChoiceOption _deletedOption(String id, String label) {
  return ChoiceOption(id: id, label: label, isDeleted: true);
}

CustomField _choiceField({
  required List<ChoiceOption> options,
  bool allowsMultiple = false,
  bool allowsOther = false,
}) {
  return CustomField(
    id: 'field-1',
    name: 'Hobbies',
    fieldType: CustomFieldType.choice,
    fieldTypeId: 'choice',
    createdAt: DateTime(2026, 1, 1),
    typeConfig: CustomFieldTypeConfig.choice(
      options: options,
      allowsMultiple: allowsMultiple,
      allowsOther: allowsOther,
    ),
  );
}

CustomFieldValue _value(String raw) {
  return CustomFieldValue(
    id: 'val-1',
    customFieldId: 'field-1',
    memberId: _memberId,
    value: raw,
  );
}

Widget _wrapEditor({
  required CustomField field,
  CustomFieldValue? value,
  _FakeCustomFieldsRepository? repo,
}) {
  final r = repo ?? _FakeCustomFieldsRepository();
  return ProviderScope(
    overrides: [
      customFieldsRepositoryProvider.overrideWithValue(r),
      customFieldsProvider.overrideWithValue(AsyncValue.data([field])),
      memberCustomFieldValuesProvider(
        _memberId,
      ).overrideWithValue(AsyncValue.data(value != null ? [value] : [])),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: buildChoiceEditor(
          // ignore: prefer_const_constructors  // context is runtime
          // We call the builder directly to keep this self-contained.
          // Normally this is called via the renderer registry in
          // CustomFieldsEditor._buildFieldEditor.
          _FakeContext(),
          field,
          value,
          _memberId,
        ),
      ),
    ),
  );
}

// A fake BuildContext stand-in is not possible without the widget tree.
// Tests below use tester.pumpWidget to supply the real context.
Widget _editorSubject({
  required CustomField field,
  CustomFieldValue? value,
  _FakeCustomFieldsRepository? repo,
  CustomFieldsEditorController? controller,
}) {
  final r = repo ?? _FakeCustomFieldsRepository();
  Widget body = Consumer(
    builder: (context, ref, _) =>
        buildChoiceEditor(context, field, value, _memberId),
  );
  if (controller != null) {
    body = CustomFieldEditorScope(controller: controller, child: body);
  }
  return ProviderScope(
    overrides: [
      customFieldsRepositoryProvider.overrideWithValue(r),
      customFieldsProvider.overrideWithValue(AsyncValue.data([field])),
      memberCustomFieldValuesProvider(
        _memberId,
      ).overrideWithValue(AsyncValue.data(value != null ? [value] : [])),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: body),
    ),
  );
}

Widget _displaySubject({
  required CustomField field,
  required CustomFieldValue value,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Builder(
        builder: (context) => buildChoiceDisplay(context, field, value),
      ),
    ),
  );
}

Widget _compactSubject({
  required CustomField field,
  required CustomFieldValue value,
  double width = 400,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: Builder(
          builder: (context) => buildChoiceCompact(context, field, value),
        ),
      ),
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ─── Editor tests ───────────────────────────────────────────────────────────

  group('ChoiceEditor — empty state (no options selected)', () {
    testWidgets('renders all chips unselected', (tester) async {
      final field = _choiceField(
        options: [
          _option('a', 'Apples'),
          _option('b', 'Bananas'),
          _option('c', 'Cherries'),
        ],
      );

      await tester.pumpWidget(_editorSubject(field: field, value: null));
      await tester.pump();

      // All three labels appear in the tree.
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Bananas'), findsOneWidget);
      expect(find.text('Cherries'), findsOneWidget);

      // No PrismChip is in the "selected" visual state — assert via
      // widget-tree: all PrismChip widgets have selected == false.
      final chips = tester.widgetList<PrismChip>(find.byType(PrismChip));
      for (final chip in chips) {
        expect(
          chip.selected,
          isFalse,
          reason: 'All chips should be unselected',
        );
      }
    });
  });

  group('ChoiceEditor — single-select', () {
    testWidgets('tapping a chip stages selection; commit persists it', (
      tester,
    ) async {
      final repo = _FakeCustomFieldsRepository();
      final controller = CustomFieldsEditorController();
      final field = _choiceField(
        options: [_option('a', 'Apples'), _option('b', 'Bananas')],
      );

      await tester.pumpWidget(
        _editorSubject(
          field: field,
          value: null,
          repo: repo,
          controller: controller,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Apples'));
      await tester.pump();

      // Tap stages the edit; the notifier has not yet been touched.
      expect(repo.upsertedValues, isEmpty);
      expect(controller.hasPendingChanges, isTrue);

      await controller.commit();
      await tester.pump();

      expect(repo.upsertedValues, hasLength(1));
      expect(repo.upsertedValues.single.value, contains('"a"'));
    });

    testWidgets(
      'tapping a second chip replaces the first; commit writes the latest',
      (tester) async {
        final repo = _FakeCustomFieldsRepository();
        final controller = CustomFieldsEditorController();
        final field = _choiceField(
          options: [_option('a', 'Apples'), _option('b', 'Bananas')],
        );
        // Pre-select 'a'
        final existing = _value('{"options":["a"]}');

        await tester.pumpWidget(
          _editorSubject(
            field: field,
            value: existing,
            repo: repo,
            controller: controller,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Bananas'));
        await tester.pump();
        await controller.commit();
        await tester.pump();

        // Single upsert with only 'b'; the intermediate 'a' selection never
        // reached disk because edits don't fire writes between taps.
        expect(repo.upsertedValues, hasLength(1));
        final lastValue = repo.upsertedValues.last.value;
        expect(lastValue, contains('"b"'));
        expect(lastValue, isNot(contains('"a"')));
      },
    );

    testWidgets('deselecting the only selected chip deletes on commit', (
      tester,
    ) async {
      final repo = _FakeCustomFieldsRepository();
      final controller = CustomFieldsEditorController();
      final field = _choiceField(options: [_option('a', 'Apples')]);
      final existing = _value('{"options":["a"]}');

      await tester.pumpWidget(
        _editorSubject(
          field: field,
          value: existing,
          repo: repo,
          controller: controller,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Apples'));
      await tester.pump();
      expect(repo.deletedValueIds, isEmpty);

      await controller.commit();
      await tester.pump();
      expect(repo.deletedValueIds, contains('val-1'));
    });
  });

  group('ChoiceEditor — multi-select (allowsMultiple: true)', () {
    testWidgets('tapping toggles chips independently; commit writes them all', (
      tester,
    ) async {
      final repo = _FakeCustomFieldsRepository();
      final controller = CustomFieldsEditorController();
      final field = _choiceField(
        options: [
          _option('a', 'Apples'),
          _option('b', 'Bananas'),
          _option('c', 'Cherries'),
        ],
        allowsMultiple: true,
      );

      await tester.pumpWidget(
        _editorSubject(
          field: field,
          value: null,
          repo: repo,
          controller: controller,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Apples'));
      await tester.pump();
      await tester.tap(find.text('Cherries'));
      await tester.pump();
      await controller.commit();
      await tester.pump();

      // Both 'a' and 'c' should appear in the single committed encoded value.
      expect(repo.upsertedValues, hasLength(1));
      final lastValue = repo.upsertedValues.last.value;
      expect(lastValue, contains('"a"'));
      expect(lastValue, contains('"c"'));
      expect(lastValue, isNot(contains('"b"')));
    });
  });

  group('ChoiceEditor — Other chip', () {
    testWidgets('Other chip is hidden when allowsOther is false', (
      tester,
    ) async {
      final field = _choiceField(
        options: [_option('a', 'Apples')],
        allowsOther: false,
      );

      await tester.pumpWidget(_editorSubject(field: field, value: null));
      await tester.pump();

      expect(find.text('Other…'), findsNothing);
    });

    testWidgets('Other chip is visible when allowsOther is true', (
      tester,
    ) async {
      final field = _choiceField(
        options: [_option('a', 'Apples')],
        allowsOther: true,
      );

      await tester.pumpWidget(_editorSubject(field: field, value: null));
      await tester.pump();

      expect(find.text('Other…'), findsOneWidget);
    });

    testWidgets(
      'tapping Other chip expands text field; commit persists the typed text',
      (tester) async {
        final repo = _FakeCustomFieldsRepository();
        final controller = CustomFieldsEditorController();
        final field = _choiceField(
          options: [_option('a', 'Apples')],
          allowsOther: true,
        );

        await tester.pumpWidget(
          _editorSubject(
            field: field,
            value: null,
            repo: repo,
            controller: controller,
          ),
        );
        await tester.pump();

        // Before tap: no text field visible for Other.
        expect(find.byType(TextField), findsNothing);

        await tester.tap(find.text('Other…'));
        await tester.pump();

        // After tap: TextField expands.
        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Dragonfruit');
        await tester.pump();

        // Editing alone does not write — even mid-keystroke.
        expect(repo.upsertedValues, isEmpty);

        // Commit flushes the buffered Other text into the encoded value.
        await controller.commit();
        await tester.pump();
        expect(repo.upsertedValues, hasLength(1));
        expect(repo.upsertedValues.last.value, contains('"Dragonfruit"'));
      },
    );
  });

  group('ChoiceEditor — deleted option handling', () {
    testWidgets(
      'deleted option still renders when member has it selected (faded)',
      (tester) async {
        final field = _choiceField(
          options: [
            _option('a', 'Apples'),
            _deletedOption('d', 'Dragon Fruit'),
          ],
        );
        // Member has the deleted option selected.
        final existing = _value('{"options":["d"]}');

        await tester.pumpWidget(_editorSubject(field: field, value: existing));
        await tester.pump();

        // The deleted option label should appear.
        expect(find.text('Dragon Fruit'), findsOneWidget);

        // It must be wrapped in Opacity (faded) — find an Opacity with < 1.0
        final opacityWidgets = tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.text('Dragon Fruit'),
                matching: find.byType(Opacity),
              ),
            )
            .toList();
        expect(
          opacityWidgets.any((o) => o.opacity < 1.0),
          isTrue,
          reason: 'Deleted option should be rendered faded',
        );
      },
    );
  });

  // ─── Display tests ──────────────────────────────────────────────────────────

  group('ChoiceDisplay — read-only chip row', () {
    testWidgets('renders selected options as chips', (tester) async {
      final field = _choiceField(
        options: [_option('a', 'Apples'), _option('b', 'Bananas')],
      );
      final value = _value('{"options":["a","b"]}');

      await tester.pumpWidget(_displaySubject(field: field, value: value));
      await tester.pump();

      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Bananas'), findsOneWidget);
    });

    testWidgets('renders selected options in settings order', (tester) async {
      final options = List.generate(50, (index) {
        final reverseId = (49 - index).toString().padLeft(2, '0');
        return _option('id-$reverseId', 'Option ${index + 1}', order: index);
      });
      final field = _choiceField(options: options);
      final encodedIds = options.map((option) => option.id).toList()..sort();
      final value = _value(jsonEncode({'options': encodedIds}));

      await tester.pumpWidget(_displaySubject(field: field, value: value));
      await tester.pump();

      final chipLabels = tester
          .widgetList<PrismChip>(find.byType(PrismChip))
          .map((chip) => chip.label)
          .toList();

      expect(chipLabels.take(5), [
        'Option 1',
        'Option 2',
        'Option 3',
        'Option 4',
        'Option 5',
      ]);
      expect(chipLabels.last, 'Option 50');
    });

    testWidgets('chips are not interactive (no FilterChip selection state)', (
      tester,
    ) async {
      final field = _choiceField(options: [_option('a', 'Apples')]);
      final value = _value('{"options":["a"]}');

      await tester.pumpWidget(_displaySubject(field: field, value: value));
      await tester.pump();

      // All PrismChips should have onTap == null (display-only).
      final chips = tester.widgetList<PrismChip>(find.byType(PrismChip));
      for (final chip in chips) {
        expect(chip.onTap, isNull, reason: 'Display chips should be read-only');
      }
    });

    testWidgets('Other pill renders when value has other text', (tester) async {
      final field = _choiceField(
        options: [_option('a', 'Apples')],
        allowsOther: true,
      );
      final value = _value('{"options":["a"],"other":"Mango"}');

      await tester.pumpWidget(_displaySubject(field: field, value: value));
      await tester.pump();

      expect(find.text('Other: Mango'), findsOneWidget);
    });
  });

  // ─── Compact tests ───────────────────────────────────────────────────────────

  group('ChoiceCompact — first 3 chips + overflow', () {
    testWidgets('shows first 3 chips and +N more text when overflow', (
      tester,
    ) async {
      final field = _choiceField(
        options: [
          _option('a', 'Apples'),
          _option('b', 'Bananas'),
          _option('c', 'Cherries'),
          _option('d', 'Dates'),
          _option('e', 'Elderberry'),
        ],
      );
      // All 5 selected.
      final value = _value('{"options":["a","b","c","d","e"]}');

      await tester.pumpWidget(
        _compactSubject(field: field, value: value, width: 500),
      );
      await tester.pump();

      // At least 3 chip labels should be visible.
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Bananas'), findsOneWidget);
      expect(find.text('Cherries'), findsOneWidget);

      // The overflow indicator should show +2 more.
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('uses settings order before applying visible chip limit', (
      tester,
    ) async {
      final options = List.generate(50, (index) {
        final reverseId = (49 - index).toString().padLeft(2, '0');
        return _option('id-$reverseId', 'Option ${index + 1}', order: index);
      });
      final field = _choiceField(options: options);
      final encodedIds = options.map((option) => option.id).toList()..sort();
      final value = _value(jsonEncode({'options': encodedIds}));

      await tester.pumpWidget(
        _compactSubject(field: field, value: value, width: 500),
      );
      await tester.pump();

      final chipLabels = tester
          .widgetList<PrismChip>(find.byType(PrismChip))
          .map((chip) => chip.label)
          .toList();

      expect(chipLabels, ['Option 1', 'Option 2', 'Option 3']);
      expect(find.text('+47 more'), findsOneWidget);
    });

    testWidgets('falls back to plain text in narrow context (< 200px)', (
      tester,
    ) async {
      final field = _choiceField(
        options: [
          _option('a', 'Apples'),
          _option('b', 'Bananas'),
          _option('c', 'Cherries'),
          _option('d', 'Dates'),
        ],
      );
      final value = _value('{"options":["a","b","c","d"]}');

      await tester.pumpWidget(
        _compactSubject(field: field, value: value, width: 120),
      );
      await tester.pump();

      // In narrow context there should be no PrismChip widgets.
      // A Text widget with the compact plain-text representation is rendered
      // directly instead.
      expect(find.byType(PrismChip), findsNothing);
    });
  });

  // ─── Long-press menu pattern documentation ───────────────────────────────────

  group('ChoiceEditor — long-press menu (pattern documentation)', () {
    // The long-press context menu uses BlurPopupAnchor with
    // BlurPopupTrigger.manual. A GlobalKey<BlurPopupAnchorState> per option is
    // created in _ChoiceEditorWidgetState._popupKeys. Long-pressing a chip
    // calls _handleLongPress which calls `_popupKeyFor(option.id).currentState?.show()`.
    //
    // Driving this flow requires:
    //   1. A real overlay (provided by MaterialApp ✓).
    //   2. A long-press gesture recognizer on the GestureDetector wrapping each chip.
    //   3. The BlurPopupAnchor to have been built before the gesture is fired.
    //
    // Tapping "Edit label" inside the menu opens a PrismDialog with a
    // PrismTextField. Filling the field and tapping Save calls
    // `customFieldNotifierProvider.writeTypedConfig`.
    //
    // Tapping "Delete" calls `PrismDialog.confirm` with destructive=true;
    // confirming calls `writeTypedConfig` with `isDeleted: true` on the option.
    //
    // These interactions require a complete navigation stack and are tested
    // through integration tests (see test/integration/ when that tree is added).
    // For now the test asserts the widget structure is in place.

    testWidgets('BlurPopupAnchor is present for each active option', (
      tester,
    ) async {
      final field = _choiceField(
        options: [_option('a', 'Apples'), _option('b', 'Bananas')],
      );

      await tester.pumpWidget(_editorSubject(field: field, value: null));
      await tester.pump();

      // Each active option chip is wrapped in a BlurPopupAnchor (manual trigger).
      final anchors = tester.widgetList<BlurPopupAnchor>(
        find.byType(BlurPopupAnchor),
      );
      // 2 options → 2 BlurPopupAnchors.
      expect(anchors.length, equals(2));
      for (final anchor in anchors) {
        expect(anchor.trigger, equals(BlurPopupTrigger.manual));
      }
    });
  });
}

// ─── Fake repository ─────────────────────────────────────────────────────────

class _FakeCustomFieldsRepository implements CustomFieldsRepository {
  final upsertedValues = <CustomFieldValue>[];
  final deletedValueIds = <String>[];
  final writtenConfigs = <String, CustomFieldTypeConfig>{};

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
  Future<List<CustomFieldValue>> getAllValues() async => [];

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
  Future<List<CustomField>> getAllFields() async => const [];

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

  @override
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) async {
    writtenConfigs[fieldId] = newConfig;
  }

  @override
  Future<void> clearTypedConfig(String fieldId) async {
    writtenConfigs.remove(fieldId);
  }
}

// Stand-in to satisfy the compiler for the unused _wrapEditor helper above.
// Actual tests call _editorSubject which constructs context via Consumer.
class _FakeContext extends BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
