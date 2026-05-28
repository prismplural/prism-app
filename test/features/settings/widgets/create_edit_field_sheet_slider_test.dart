import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeCustomFieldNotifier extends CustomFieldNotifier {
  String? lastWrittenConfigFieldId;
  CustomFieldTypeConfig? lastWrittenConfig;

  @override
  Future<void> build() async {}

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

Widget _buildSheet({
  required CustomField field,
  required _FakeCustomFieldNotifier notifier,
}) {
  return ProviderScope(
    overrides: [customFieldNotifierProvider.overrideWith(() => notifier)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CreateEditFieldSheet(
          field: field,
          scrollController: ScrollController(),
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

/// Builds a labeled slider field in custom-gradient mode with [gradientColorsHex].
CustomField _sliderField({
  String id = 'slider-1',
  String name = 'Intensity',
  String? gradientPresetId,
  List<String>? gradientColorsHex,
  String? leftColorHex,
  String? centerColorHex,
  String? rightColorHex,
}) {
  return CustomField(
    id: id,
    name: name,
    fieldType: CustomFieldType.text,
    displayOrder: 0,
    createdAt: DateTime.utc(2026, 1, 1),
    fieldTypeId: 'slider',
    typeConfig: CustomFieldTypeConfig.slider(
      mode: SliderMode.labeled,
      gradientPresetId: gradientPresetId,
      gradientColorsHex: gradientColorsHex,
      leftColorHex: leftColorHex,
      centerColorHex: centerColorHex,
      rightColorHex: rightColorHex,
    ),
  );
}

void main() {
  group('Create/Edit Field Sheet - Slider config', () {
    // ── Legacy compat ───────────────────────────────────────────────────────

    testWidgets('selecting a preset preserves inactive custom gradient colors', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientColorsHex: ['#111111', '#222222', '#333333'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Soft').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(notifier.lastWrittenConfigFieldId, 'slider-1');
      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientPresetId, 'soft-hard');
      // Legacy mirrored fields are written regardless of preset selection.
      expect(config.leftColorHex, '#111111');
      expect(config.centerColorHex, '#222222');
      expect(config.rightColorHex, '#333333');
    });

    testWidgets('custom gradient colors survive preset→custom round-trip', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientColorsHex: ['#111111', '#222222', '#333333'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // Preview a preset then switch back to Custom.
      await tester.tap(find.textContaining('Soft').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();
      // Enter a left label to make the field dirty.
      await tester.enterText(find.byType(TextField).at(1), 'Low');
      await tester.pump();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(notifier.lastWrittenConfigFieldId, 'slider-1');
      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientPresetId, isNull);
      expect(config.leftLabel, 'Low');
      // Seeded from the soft-hard preset (leftHex=#F4EBD8, rightHex=#3A2E4D,
      // centerHex=#A89B8C) when switching to Custom.
      expect(config.gradientColorsHex, isNotNull);
      expect(config.gradientColorsHex!.length, 3);
    });

    // ── Hydration from legacy left/center/right ─────────────────────────────

    testWidgets('hydrates from legacy leftColorHex/rightColorHex when gradientColorsHex absent', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        leftColorHex: '#AAAAAA',
        rightColorHex: '#555555',
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      // Should have persisted a 2-color list from the legacy fields.
      expect(config!.gradientColorsHex, ['#AAAAAA', '#555555']);
      expect(config.leftColorHex, '#AAAAAA');
      expect(config.rightColorHex, '#555555');
      expect(config.centerColorHex, isNull); // 2-color → center must be null
    });

    // ── Build-config mirroring ──────────────────────────────────────────────

    testWidgets('2-color custom gradient: legacy center is null', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientColorsHex: ['#FF0000', '#0000FF'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientColorsHex, ['#FF0000', '#0000FF']);
      expect(config.leftColorHex, '#FF0000');
      expect(config.rightColorHex, '#0000FF');
      expect(config.centerColorHex, isNull);
    });

    testWidgets('4-color custom gradient: legacy center = index 2', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientColorsHex: ['#AA0000', '#BB0000', '#CC0000', '#DD0000'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(
        config!.gradientColorsHex,
        ['#AA0000', '#BB0000', '#CC0000', '#DD0000'],
      );
      expect(config.leftColorHex, '#AA0000');
      expect(config.rightColorHex, '#DD0000');
      // list.length ~/ 2 = 4 ~/ 2 = 2 → index 2 = '#CC0000'
      expect(config.centerColorHex, '#CC0000');
    });

    // ── Swatch row add/remove/reorder via callbacks ─────────────────────────

    testWidgets('swatch row: reorder callback changes list order', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      // Start with 3 colors; we'll simulate a reorder by finding the
      // ReorderableListView and invoking onReorder directly.
      final field = _sliderField(
        gradientColorsHex: ['#AA0000', '#00BB00', '#0000CC'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // The swatch row is visible because preset is null.
      expect(find.byType(ReorderableListView), findsWidgets);

      // Invoke the ReorderableListView's onReorder programmatically (index 0 → 2).
      final listView = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView).first,
      );
      listView.onReorder(0, 2);
      await tester.pump();

      // Save to capture the config.
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      // After moving index 0 → 1 (adjusted: newIndex > oldIndex → newIndex--),
      // list becomes [#00BB00, #AA0000, #0000CC].
      expect(config!.gradientColorsHex, ['#00BB00', '#AA0000', '#0000CC']);
    });

    testWidgets('preset → custom seeds swatch list from preset colors', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      // Field starts with femme-masc preset selected.
      final field = _sliderField(
        gradientPresetId: 'femme-masc',
        gradientColorsHex: null,
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // Tap the "Custom" chip to switch to custom mode.
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();

      // The swatch row should now be visible.
      expect(find.byType(ReorderableListView), findsWidgets);

      // Save immediately to capture the seeded config.
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientPresetId, isNull);
      // femme-masc has leftHex=#E89BB8, centerHex=#F0E6D6, rightHex=#8FAA9A.
      expect(config.gradientColorsHex, ['#E89BB8', '#F0E6D6', '#8FAA9A']);
    });

    testWidgets('custom colors survive previewing a preset and returning', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      // Field already saved in CUSTOM mode with hand-picked colors.
      final field = _sliderField(
        gradientPresetId: null,
        gradientColorsHex: ['#AA0000', '#BB0000', '#CC0000'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // Preview a preset, then switch back to custom.
      await tester.tap(find.text('Cool ↔ Warm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientPresetId, isNull);
      // Original custom colors preserved — NOT replaced by the cool-warm preset.
      expect(config.gradientColorsHex, ['#AA0000', '#BB0000', '#CC0000']);
    });

    testWidgets('add-color tile is hidden when 6 colors present', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientColorsHex: [
          '#AA0000',
          '#BB0000',
          '#CC0000',
          '#DD0000',
          '#EE0000',
          '#FF0000',
        ],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // The add-color tooltip should not appear when there are 6 colors.
      expect(find.byTooltip('Add color'), findsNothing);
    });

    testWidgets('add-color tile is visible when fewer than 6 colors', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientColorsHex: ['#AA0000', '#BB0000'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add color'), findsOneWidget);
    });

    testWidgets('remove badge deletes a swatch (down to min 2)', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientPresetId: null,
        gradientColorsHex: ['#AA0000', '#BB0000', '#CC0000'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // Three swatches → three remove badges. Tap the first to remove index 0.
      expect(find.byIcon(Icons.close), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientColorsHex, ['#BB0000', '#CC0000']);
    });

    testWidgets('remove badge hidden at the minimum of 2 colors', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = _sliderField(
        gradientPresetId: null,
        gradientColorsHex: ['#AA0000', '#BB0000'],
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      // At the 2-color minimum, no remove badges are shown.
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
