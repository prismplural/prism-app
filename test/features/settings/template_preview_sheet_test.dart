import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/settings/widgets/template_preview_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  final now = DateTime.now();

  CustomField makeField({
    required String id,
    required String name,
    required String fieldTypeId,
    required CustomFieldType fieldType,
    String? parentFieldId,
    CustomFieldTypeConfig? typeConfig,
    String? unknownTypeConfigRaw,
  }) => CustomField(
    id: id,
    name: name,
    fieldType: fieldType,
    createdAt: now,
    fieldTypeId: fieldTypeId,
    parentFieldId: parentFieldId,
    typeConfig: typeConfig,
    unknownTypeConfigRaw: unknownTypeConfigRaw,
  );

  FieldTemplate buildTemplate() {
    final group = makeField(
      id: 'g',
      name: 'Stats',
      fieldTypeId: 'group',
      fieldType: CustomFieldType.text,
      typeConfig: const GroupConfig(),
    );
    final scale = makeField(
      id: 's',
      name: 'Power',
      fieldTypeId: 'scale',
      fieldType: CustomFieldType.text,
      parentFieldId: 'g',
      typeConfig: const ScaleConfig(emoji: '⭐', steps: 5),
    );
    final choice = makeField(
      id: 'c',
      name: 'Mood',
      fieldTypeId: 'choice',
      fieldType: CustomFieldType.choice,
      parentFieldId: 'g',
      typeConfig: const ChoiceConfig(
        options: [ChoiceOption(id: 'o1', label: 'Happy', colorHex: '#ff0000')],
      ),
    );
    final unknown = makeField(
      id: 'u',
      name: 'Future',
      fieldTypeId: 'futurething',
      fieldType: CustomFieldType.text,
      unknownTypeConfigRaw: '{"x":1}',
    );
    return FieldTemplate.fromDomain([group, scale, choice, unknown]);
  }

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );

  testWidgets('previews every field, ownership line, unknown badge, and CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TemplatePreviewSheetContent(
          template: buildTemplate(),
          scrollController: ScrollController(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Power'), findsWidgets);
    expect(find.text('Mood'), findsWidgets);
    expect(find.text('Future'), findsWidgets);
    expect(find.text('Newer version'), findsOneWidget);
    expect(find.textContaining('×5'), findsWidgets);
    expect(
      find.textContaining("Changes won't affect the original"),
      findsOneWidget,
    );
    expect(find.text('Import fields'), findsOneWidget);
  });

  testWidgets('tapping Import fields confirms with true', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bool? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await TemplatePreviewSheet.show(
                  context,
                  template: buildTemplate(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import fields'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
