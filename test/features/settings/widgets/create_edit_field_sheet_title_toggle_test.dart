// Tests for the shared "Show title on profiles" toggle wired into the
// create/edit field sheet for every custom field type.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ── Fake notifier (same signature as real CustomFieldNotifier) ───────────────

class _FakeCustomFieldNotifier extends CustomFieldNotifier {
  CustomField? lastCreated;
  CustomField? lastUpdated;
  String? lastWrittenConfigFieldId;
  CustomFieldTypeConfig? lastWrittenConfig;
  String? lastClearedConfigFieldId;
  bool clearTypedConfigCalled = false;

  @override
  Future<void> build() async {}

  @override
  Future<Object?> createField({
    required String name,
    required CustomFieldType fieldType,
    DatePrecision? datePrecision,
    int? displayOrder,
    String? fieldTypeId,
    CustomFieldTypeConfig? typeConfig,
    String? parentFieldId,
  }) async {
    lastCreated = CustomField(
      id: 'created-id',
      name: name,
      fieldType: fieldType,
      datePrecision: datePrecision,
      displayOrder: displayOrder ?? 0,
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

  @override
  Future<Object?> clearTypedConfig(String fieldId) async {
    clearTypedConfigCalled = true;
    lastClearedConfigFieldId = fieldId;
    return null;
  }
}

// ── Test helpers ─────────────────────────────────────────────────────────────

Widget _buildSheet({
  CustomField? field,
  _FakeCustomFieldNotifier? notifier,
  ({
    SystemTerminology term,
    String? customSingular,
    String? customPlural,
    bool useEnglish,
  })?
  terminology,
}) {
  final fakeNotifier = notifier ?? _FakeCustomFieldNotifier();
  return ProviderScope(
    overrides: [
      customFieldNotifierProvider.overrideWith(() => fakeNotifier),
      if (terminology != null)
        terminologySettingProvider.overrideWithValue(terminology),
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
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ── Widget tests ─────────────────────────────────────────────────────────────

void main() {
  // ── Text type ─────────────────────────────────────────────────────────────

  group('Create/Edit Field Sheet — Show title toggle: Text type', () {
    testWidgets('toggle is present for text type (default type)', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      // Text is the default type, so the toggle should be visible immediately.
      expect(find.text('Show title on profiles'), findsOneWidget);
    });

    testWidgets(
      'saving text field with default toggle produces typeConfig == null',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeCustomFieldNotifier();
        await tester.pumpWidget(_buildSheet(notifier: notifier));
        await tester.pumpAndSettle();

        // Type is already 'text'; toggle is ON (show title = true) by default.
        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, 'My Text Field');
        await tester.pump();

        await tester.tap(find.byIcon(AppIcons.check));
        await tester.pumpAndSettle();

        expect(notifier.lastCreated, isNotNull);
        // Toggle at default → churn-avoidance → typeConfig must be null.
        expect(
          notifier.lastCreated!.typeConfig,
          isNull,
          reason: 'Default-title text field should save typeConfig == null',
        );
      },
    );

    testWidgets(
      'flipping toggle OFF produces TextConfig(hideTitleOnProfile: true)',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeCustomFieldNotifier();
        await tester.pumpWidget(_buildSheet(notifier: notifier));
        await tester.pumpAndSettle();

        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, 'Hidden Label Field');
        await tester.pump();

        // Flip the toggle OFF (switch value false → hideTitleOnProfile = true).
        final toggleSwitch = tester.widget<Switch>(
          find
              .descendant(
                of: find.widgetWithText(
                  SwitchListTile,
                  'Show title on profiles',
                ),
                matching: find.byType(Switch),
              )
              .first,
        );
        expect(toggleSwitch.value, isTrue); // starts ON

        await tester.tap(
          find.widgetWithText(SwitchListTile, 'Show title on profiles'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.check));
        await tester.pumpAndSettle();

        expect(notifier.lastCreated, isNotNull);
        final config = notifier.lastCreated!.typeConfig;
        expect(config, isA<TextConfig>());
        expect(effectiveHideTitleOnProfile(config), isTrue);
      },
    );

    testWidgets(
      'opening sheet on text field with hideTitleOnProfile: true shows toggle as OFF',
      (tester) async {
        _useTallViewport(tester);
        final existingField = CustomField(
          id: 'field-text-1',
          name: 'Hidden',
          fieldType: CustomFieldType.text,
          displayOrder: 0,
          createdAt: DateTime.utc(2026, 1, 1),
          fieldTypeId: 'text',
          typeConfig: const TextConfig(hideTitleOnProfile: true),
        );

        await tester.pumpWidget(_buildSheet(field: existingField));
        await tester.pumpAndSettle();

        final sw = tester.widget<Switch>(
          find
              .descendant(
                of: find.widgetWithText(
                  SwitchListTile,
                  'Show title on profiles',
                ),
                matching: find.byType(Switch),
              )
              .first,
        );
        // value = !hideTitleOnProfile → false when hidden
        expect(sw.value, isFalse);
      },
    );

    testWidgets(
      'reverting a hidden-title text field back to default clears the config',
      (tester) async {
        _useTallViewport(tester);
        final existingField = CustomField(
          id: 'field-text-revert',
          name: 'Hidden',
          fieldType: CustomFieldType.text,
          displayOrder: 0,
          createdAt: DateTime.utc(2026, 1, 1),
          fieldTypeId: 'text',
          typeConfig: const TextConfig(hideTitleOnProfile: true),
        );
        final notifier = _FakeCustomFieldNotifier();
        await tester.pumpWidget(
          _buildSheet(field: existingField, notifier: notifier),
        );
        await tester.pumpAndSettle();

        // Flip the toggle back ON (show title) → hideTitleOnProfile = false →
        // _buildTextConfig returns null → the config must be CLEARED, not left
        // stale. The old `typeConfig != null` guard silently dropped this write.
        await tester.tap(
          find.widgetWithText(SwitchListTile, 'Show title on profiles'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.check));
        await tester.pumpAndSettle();

        expect(
          notifier.clearTypedConfigCalled,
          isTrue,
          reason: 'reverting to default must clear type_config_json',
        );
        expect(notifier.lastClearedConfigFieldId, 'field-text-revert');
        expect(
          notifier.lastWrittenConfig,
          isNull,
          reason: 'no stale config should be written on revert',
        );
      },
    );
  });

  group('Create/Edit Field Sheet — Show title toggle: Member type', () {
    testWidgets('member type chip uses custom terminology', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildSheet(
          terminology: (
            term: SystemTerminology.custom,
            customSingular: 'companion',
            customPlural: 'companions',
            useEnglish: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Companion'), findsOneWidget);
      expect(find.text('Member'), findsNothing);
    });

    testWidgets('editing member field saves selected layout', (tester) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final existingField = CustomField(
        id: 'field-member-layout',
        name: 'Siblings',
        fieldType: CustomFieldType.text,
        displayOrder: 0,
        createdAt: DateTime.utc(2026, 1, 1),
        fieldTypeId: 'member',
        typeConfig: const MemberConfig(extra: {'future': true}),
      );

      await tester.pumpWidget(
        _buildSheet(field: existingField, notifier: notifier),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stacked'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(notifier.lastWrittenConfigFieldId, 'field-member-layout');
      final config = notifier.lastWrittenConfig;
      expect(config, isA<MemberConfig>());
      final memberConfig = config! as MemberConfig;
      expect(memberConfig.displayLayout, DisplayLayout.stacked);
      expect(memberConfig.extra, {'future': true});
    });

    testWidgets(
      'editing member field preserves extra config when show-title is toggled on',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeCustomFieldNotifier();
        final existingField = CustomField(
          id: 'field-member-1',
          name: 'Partner',
          fieldType: CustomFieldType.text,
          displayOrder: 0,
          createdAt: DateTime.utc(2026, 1, 1),
          fieldTypeId: 'member',
          typeConfig: const MemberConfig(
            hideTitleOnProfile: true,
            extra: {'future': true},
          ),
        );

        await tester.pumpWidget(
          _buildSheet(field: existingField, notifier: notifier),
        );
        await tester.pumpAndSettle();

        final sw = tester.widget<Switch>(
          find
              .descendant(
                of: find.widgetWithText(
                  SwitchListTile,
                  'Show title on profiles',
                ),
                matching: find.byType(Switch),
              )
              .first,
        );
        expect(sw.value, isFalse);

        await tester.tap(
          find.widgetWithText(SwitchListTile, 'Show title on profiles'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.check));
        await tester.pumpAndSettle();

        expect(notifier.lastWrittenConfigFieldId, 'field-member-1');
        final config = notifier.lastWrittenConfig;
        expect(config, isA<MemberConfig>());
        expect(effectiveHideTitleOnProfile(config), isFalse);
        expect((config! as MemberConfig).extra, {'future': true});
        expect(notifier.clearTypedConfigCalled, isFalse);
      },
    );
  });

  // ── Choice type ───────────────────────────────────────────────────────────

  group('Create/Edit Field Sheet — Show title toggle: Choice type', () {
    testWidgets('toggle is present after selecting Choice', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choice'));
      await tester.pumpAndSettle();

      expect(find.text('Show title on profiles'), findsOneWidget);
    });

    testWidgets(
      'flipping toggle OFF saves ChoiceConfig with hideTitleOnProfile: true',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeCustomFieldNotifier();
        await tester.pumpWidget(_buildSheet(notifier: notifier));
        await tester.pumpAndSettle();

        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, 'Mood');
        await tester.pump();

        await tester.tap(find.text('Choice'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(SwitchListTile, 'Show title on profiles'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.check));
        await tester.pumpAndSettle();

        expect(notifier.lastCreated, isNotNull);
        final config = notifier.lastCreated!.typeConfig as ChoiceConfig?;
        expect(config, isNotNull);
        expect(effectiveHideTitleOnProfile(config), isTrue);
      },
    );

    testWidgets(
      'opening choice field with hideTitleOnProfile: true shows toggle as OFF',
      (tester) async {
        _useTallViewport(tester);
        final existingField = CustomField(
          id: 'field-choice-1',
          name: 'Mood',
          fieldType: CustomFieldType.choice,
          displayOrder: 0,
          createdAt: DateTime.utc(2026, 1, 1),
          fieldTypeId: 'choice',
          typeConfig: const ChoiceConfig(hideTitleOnProfile: true),
        );

        await tester.pumpWidget(_buildSheet(field: existingField));
        await tester.pumpAndSettle();

        final sw = tester.widget<Switch>(
          find
              .descendant(
                of: find.widgetWithText(
                  SwitchListTile,
                  'Show title on profiles',
                ),
                matching: find.byType(Switch),
              )
              .first,
        );
        expect(sw.value, isFalse);
      },
    );
  });

  // ── Slider type ───────────────────────────────────────────────────────────

  group('Create/Edit Field Sheet — Show title toggle: Slider type', () {
    testWidgets('toggle is present after selecting Slider', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Slider'));
      await tester.pumpAndSettle();

      expect(find.text('Show title on profiles'), findsOneWidget);
    });

    testWidgets(
      'flipping toggle OFF saves SliderConfig with hideTitleOnProfile: true',
      (tester) async {
        _useTallViewport(tester);
        final notifier = _FakeCustomFieldNotifier();
        await tester.pumpWidget(_buildSheet(notifier: notifier));
        await tester.pumpAndSettle();

        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, 'Energy Level');
        await tester.pump();

        await tester.tap(find.text('Slider'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(SwitchListTile, 'Show title on profiles'),
        );
        await tester.pumpAndSettle();

        // Use the top-bar save button specifically (size = topBarActionSize).
        // find.byIcon(AppIcons.check) is ambiguous because the selected gradient
        // preset chip also renders a check icon.
        await tester.tap(find.byTooltip('Save'));
        await tester.pumpAndSettle();

        expect(notifier.lastCreated, isNotNull);
        final config = notifier.lastCreated!.typeConfig as SliderConfig?;
        expect(config, isNotNull);
        expect(effectiveHideTitleOnProfile(config), isTrue);
      },
    );

    testWidgets(
      'opening slider field with hideTitleOnProfile: true shows toggle as OFF',
      (tester) async {
        _useTallViewport(tester);
        final existingField = CustomField(
          id: 'field-slider-1',
          name: 'Energy Level',
          fieldType: CustomFieldType.text, // legacy int maps to text
          displayOrder: 0,
          createdAt: DateTime.utc(2026, 1, 1),
          fieldTypeId: 'slider',
          typeConfig: const SliderConfig(
            mode: SliderMode.labeled,
            hideTitleOnProfile: true,
          ),
        );

        await tester.pumpWidget(_buildSheet(field: existingField));
        await tester.pumpAndSettle();

        final sw = tester.widget<Switch>(
          find
              .descendant(
                of: find.widgetWithText(
                  SwitchListTile,
                  'Show title on profiles',
                ),
                matching: find.byType(Switch),
              )
              .first,
        );
        expect(sw.value, isFalse);
      },
    );
  });

  // ── Pure Dart unit tests for churn-avoidance helpers ─────────────────────

  group('Churn-avoidance: effectiveHideTitleOnProfile', () {
    test('returns false for null config', () {
      expect(effectiveHideTitleOnProfile(null), isFalse);
    });

    test('returns true for TextConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(const TextConfig(hideTitleOnProfile: true)),
        isTrue,
      );
    });

    test('returns false for TextConfig with hideTitleOnProfile: false', () {
      expect(effectiveHideTitleOnProfile(const TextConfig()), isFalse);
    });

    test('returns true for ChoiceConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(
          const ChoiceConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('returns true for SliderConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(
          const SliderConfig(
            mode: SliderMode.labeled,
            hideTitleOnProfile: true,
          ),
        ),
        isTrue,
      );
    });

    test('returns true for ColorConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(
          const ColorConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('returns true for DateConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(const DateConfig(hideTitleOnProfile: true)),
        isTrue,
      );
    });

    test('returns true for LongTextConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(
          const LongTextConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('returns true for ScaleConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(
          const ScaleConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('returns true for GroupConfig with hideTitleOnProfile: true', () {
      expect(
        effectiveHideTitleOnProfile(
          const GroupConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });
  });
}
