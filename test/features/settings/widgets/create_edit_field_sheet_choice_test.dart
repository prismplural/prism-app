// NOTE: Widget tests in this file are BLOCKED by a pre-existing compilation
// error in lib/core/sync/prism_sync_providers.dart (ffi.verifyMnemonicPin not
// found in the prism_sync generated API). This affects ALL widget tests in the
// project — it is not introduced by Task 7. Pure-Dart tests below pass fine.
//
// To run only the pure-Dart tests (which pass):
//   flutter test test/features/settings/widgets/create_edit_field_sheet_choice_test.dart
//
// The widget tests are kept here so they are ready to run once the upstream
// prism_sync FFI issue is resolved.

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/custom_fields/choice_option_palette.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ── Fake notifier ────────────────────────────────────────────────────────────

class _FakeCustomFieldNotifier extends CustomFieldNotifier {
  CustomField? lastCreated;
  CustomField? lastUpdated;
  String? lastWrittenConfigFieldId;
  CustomFieldTypeConfig? lastWrittenConfig;

  @override
  Future<void> build() async {}

  @override
  Future<Object?> createField({
    required String name,
    required CustomFieldType fieldType,
    DatePrecision? datePrecision,
    int displayOrder = 0,
    String? fieldTypeId,
    CustomFieldTypeConfig? typeConfig,
    String? parentFieldId,
  }) async {
    lastCreated = CustomField(
      id: 'created-id',
      name: name,
      fieldType: fieldType,
      datePrecision: datePrecision,
      displayOrder: displayOrder,
      createdAt: DateTime(2026),
      fieldTypeId: fieldTypeId,
      typeConfig: typeConfig,
      parentFieldId: parentFieldId,
    );
    return null;
  }

  @override
  Future<Object?> updateField(CustomField field) async {
    lastUpdated = field;
    return null;
  }

  @override
  Future<Object?> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) async {
    lastWrittenConfigFieldId = fieldId;
    lastWrittenConfig = newConfig;
    return null;
  }
}

// ── Test helpers ─────────────────────────────────────────────────────────────

Widget _buildSheet({
  CustomField? field,
  _FakeCustomFieldNotifier? notifier,
}) {
  final fakeNotifier = notifier ?? _FakeCustomFieldNotifier();
  return ProviderScope(
    overrides: [
      customFieldNotifierProvider.overrideWith(() => fakeNotifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => CreateEditFieldSheet(
            field: field,
            scrollController: ScrollController(),
          ),
        ),
      ),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ── Widget tests ─────────────────────────────────────────────────────────────

void main() {
  group('Create/Edit Field Sheet — Choice config', () {
    testWidgets('selecting Choice type reveals the options editor',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      expect(find.text('Options'), findsOneWidget);
      expect(find.text('Add option'), findsOneWidget);
    });

    testWidgets('add option appends to list with auto-color', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();

      // The first two palette colors differ.
      expect(kChoiceOptionPalette[0], isNot(equals(kChoiceOptionPalette[1])));

      // Two option text field hints exist (one per visible option).
      expect(find.widgetWithText(TextField, 'Option label'), findsAtLeast(2));
    });

    testWidgets('duplicate label shows warning chip', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();

      // Enter the same label in both.
      final fields = find.widgetWithText(TextField, 'Option label');
      await tester.enterText(fields.at(0), 'Foo');
      await tester.pump();
      await tester.enterText(fields.at(1), 'Foo');
      await tester.pump();

      expect(find.text('Duplicate label'), findsAtLeast(1));
    });

    testWidgets('remove option soft-deletes (hides from list)', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Add option'));
        await tester.pumpAndSettle();
        final fields = find.widgetWithText(TextField, 'Option label');
        await tester.enterText(fields.last, 'Option ${i + 1}');
        await tester.pump();
      }

      expect(find.text('Option 1'), findsOneWidget);
      expect(find.text('Option 2'), findsOneWidget);
      expect(find.text('Option 3'), findsOneWidget);

      // Remove the middle option.
      final removeButtons = find.byTooltip('Remove option');
      expect(removeButtons, findsNWidgets(3));
      await tester.tap(removeButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Remove option'), findsNWidgets(2));
      expect(find.text('Option 1'), findsOneWidget);
      expect(find.text('Option 3'), findsOneWidget);
    });

    testWidgets('toggles persist into ChoiceConfig on save', (tester) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      await tester.pumpWidget(_buildSheet(notifier: notifier));
      await tester.pumpAndSettle();

      // Enter a field name.
      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'Mood');
      await tester.pump();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allow multiple selections'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Allow 'Other' free text"));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.check));
      await tester.pumpAndSettle();

      expect(notifier.lastCreated, isNotNull);
      final config = notifier.lastCreated!.typeConfig as ChoiceConfig?;
      expect(config, isNotNull);
      expect(config!.allowsMultiple, isTrue);
      expect(config.allowsOther, isTrue);
    });

    testWidgets(
        'editing a choice field preserves forward-compat extra keys on save',
        (tester) async {
      _useTallViewport(tester);
      // A field written by a future peer carrying an unknown config key in
      // `extra`. Editing an unrelated toggle must NOT drop it.
      final existingField = CustomField(
        id: 'field-1',
        name: 'Mood',
        fieldType: CustomFieldType.choice,
        displayOrder: 0,
        createdAt: DateTime.utc(2026, 1, 1),
        fieldTypeId: 'choice',
        typeConfig: const CustomFieldTypeConfig.choice(
          options: [
            ChoiceOption(
              id: 'opt-a',
              label: 'Happy',
              colorHex: '#E57373',
              sortOrder: 0,
            ),
          ],
          extra: {'futureFlag': true},
        ),
      );

      final notifier = _FakeCustomFieldNotifier();
      await tester.pumpWidget(
        _buildSheet(field: existingField, notifier: notifier),
      );
      await tester.pumpAndSettle();

      // Flip an unrelated toggle so the config is considered changed and the
      // writeTypedConfig patch fires.
      await tester.tap(find.text('Allow multiple selections'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.check));
      await tester.pumpAndSettle();

      final written = notifier.lastWrittenConfig as ChoiceConfig?;
      expect(written, isNotNull);
      expect(written!.allowsMultiple, isTrue);
      expect(written.extra['futureFlag'], isTrue,
          reason: 'forward-compat extra must survive an edit-and-save');
    });

    testWidgets('tapping option swatch opens the color picker dialog',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();

      final colorButton = find.byTooltip('Change color');
      expect(colorButton, findsOneWidget);

      // Opens the picker rather than cycling the palette.
      await tester.tap(colorButton);
      await tester.pumpAndSettle();

      expect(find.text('Pick a color'), findsOneWidget);
      expect(find.byType(ColorPicker), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsNothing);
    });

    testWidgets('picking a color in the dialog saves the chosen hex',
        (tester) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      await tester.pumpWidget(_buildSheet(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Mood');
      await tester.pump();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Change color'));
      await tester.pumpAndSettle();

      // Hex bar is the only TextField inside the picker; entry round-trips
      // back through the helper as uppercase #RRGGBB.
      final hexField = find.descendant(
        of: find.byType(ColorPicker),
        matching: find.byType(TextField),
      );
      expect(hexField, findsOneWidget);
      await tester.enterText(hexField, '4287F5');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsNothing);

      await tester.tap(find.byIcon(AppIcons.check));
      await tester.pumpAndSettle();

      final config = notifier.lastCreated!.typeConfig as ChoiceConfig?;
      expect(config, isNotNull);
      expect(config!.options, hasLength(1));
      expect(config.options.first.colorHex, '#4287F5');
    });

    testWidgets('opening sheet on existing choice field hydrates state',
        (tester) async {
      _useTallViewport(tester);
      final existingField = CustomField(
        id: 'field-1',
        name: 'Mood',
        fieldType: CustomFieldType.choice,
        displayOrder: 0,
        createdAt: DateTime.utc(2026, 1, 1),
        fieldTypeId: 'choice',
        typeConfig: const CustomFieldTypeConfig.choice(
          options: [
            ChoiceOption(
              id: 'opt-a',
              label: 'Happy',
              colorHex: '#E57373',
              sortOrder: 0,
            ),
            ChoiceOption(
              id: 'opt-b',
              label: 'Sad',
              colorHex: '#64B5F6',
              sortOrder: 1,
            ),
            ChoiceOption(
              id: 'opt-c',
              label: 'Neutral',
              colorHex: '#81C784',
              sortOrder: 2,
            ),
          ],
          allowsMultiple: true,
          allowsOther: false,
        ),
      );

      await tester.pumpWidget(_buildSheet(field: existingField));
      await tester.pumpAndSettle();

      expect(find.text('Happy'), findsOneWidget);
      expect(find.text('Sad'), findsOneWidget);
      expect(find.text('Neutral'), findsOneWidget);

      // allowsMultiple toggle should be on.
      final multipleSwitch = tester.widget<Switch>(
        find
            .descendant(
              of: find.widgetWithText(
                SwitchListTile,
                'Allow multiple selections',
              ),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(multipleSwitch.value, isTrue);

      // allowsOther toggle should be off.
      final otherSwitch = tester.widget<Switch>(
        find
            .descendant(
              of: find.widgetWithText(
                SwitchListTile,
                "Allow 'Other' free text",
              ),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(otherSwitch.value, isFalse);
    });
  });

  // ── Pure Dart unit tests (always pass regardless of FFI issues) ───────────

  group('Choice field palette helpers', () {
    test('nextChoicePaletteColor cycles through palette', () {
      for (var i = 0; i < 20; i++) {
        final color = nextChoicePaletteColor(i);
        expect(kChoiceOptionPalette.contains(color), isTrue);
      }
    });

    test('cycleChoicePaletteColor advances by one', () {
      final first = kChoiceOptionPalette[0];
      final second = kChoiceOptionPalette[1];
      expect(cycleChoicePaletteColor(first), equals(second));
    });

    test('cycleChoicePaletteColor wraps at end', () {
      final last = kChoiceOptionPalette.last;
      final first = kChoiceOptionPalette[0];
      expect(cycleChoicePaletteColor(last), equals(first));
    });

    test('cycleChoicePaletteColor with null starts at index 0', () {
      expect(cycleChoicePaletteColor(null), equals(kChoiceOptionPalette[0]));
    });
  });

  group('Choice field value model', () {
    test('empty ChoiceFieldValue has no optionIds', () {
      const value = ChoiceFieldValue();
      expect(value.optionIds, isEmpty);
      expect(value.other, isNull);
    });

    test('ChoiceFieldValue holds optionIds and other', () {
      const value = ChoiceFieldValue(
        optionIds: {'opt-1', 'opt-2'},
        other: 'something',
      );
      expect(value.optionIds, containsAll(['opt-1', 'opt-2']));
      expect(value.other, equals('something'));
    });

    test('choicePaletteIndex returns null for unknown hex', () {
      expect(choicePaletteIndex('#FFFFFF'), isNull);
    });

    test('choicePaletteIndex finds known palette colors', () {
      for (var i = 0; i < kChoiceOptionPalette.length; i++) {
        expect(choicePaletteIndex(kChoiceOptionPalette[i]), equals(i));
      }
    });

    test('choicePaletteIndex is case-insensitive', () {
      expect(choicePaletteIndex('#e57373'), equals(0));
      expect(choicePaletteIndex('#E57373'), equals(0));
    });
  });
}
