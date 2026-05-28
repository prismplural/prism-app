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

void main() {
  group('Create/Edit Field Sheet - Slider config', () {
    testWidgets('selecting a preset preserves inactive custom gradient colors', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = CustomField(
        id: 'slider-1',
        name: 'Intensity',
        fieldType: CustomFieldType.text,
        displayOrder: 0,
        createdAt: DateTime.utc(2026, 1, 1),
        fieldTypeId: 'slider',
        typeConfig: const CustomFieldTypeConfig.slider(
          mode: SliderMode.labeled,
          gradientPresetId: null,
          leftColorHex: '#111111',
          centerColorHex: '#222222',
          rightColorHex: '#333333',
        ),
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
      expect(config.leftColorHex, '#111111');
      expect(config.centerColorHex, '#222222');
      expect(config.rightColorHex, '#333333');
    });

    testWidgets('custom gradient colors survive preset previews in the editor', (
      tester,
    ) async {
      _useTallViewport(tester);
      final notifier = _FakeCustomFieldNotifier();
      final field = CustomField(
        id: 'slider-1',
        name: 'Intensity',
        fieldType: CustomFieldType.text,
        displayOrder: 0,
        createdAt: DateTime.utc(2026, 1, 1),
        fieldTypeId: 'slider',
        typeConfig: const CustomFieldTypeConfig.slider(
          mode: SliderMode.labeled,
          gradientPresetId: null,
          leftColorHex: '#111111',
          centerColorHex: '#222222',
          rightColorHex: '#333333',
        ),
      );

      await tester.pumpWidget(_buildSheet(field: field, notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Soft').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(1),
        'Low',
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(notifier.lastWrittenConfigFieldId, 'slider-1');
      final config = notifier.lastWrittenConfig as SliderConfig?;
      expect(config, isNotNull);
      expect(config!.gradientPresetId, isNull);
      expect(config.leftLabel, 'Low');
      expect(config.leftColorHex, '#111111');
      expect(config.centerColorHex, '#222222');
      expect(config.rightColorHex, '#333333');
    });
  });
}
