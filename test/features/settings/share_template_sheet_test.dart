import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/settings/widgets/share_template_sheet.dart';
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
  }) => CustomField(
    id: id,
    name: name,
    fieldType: fieldType,
    createdAt: now,
    fieldTypeId: fieldTypeId,
    parentFieldId: parentFieldId,
    typeConfig: typeConfig,
  );

  FieldTemplate buildTemplate() {
    final group = makeField(
      id: 'g1',
      name: 'Stats',
      fieldTypeId: 'group',
      fieldType: CustomFieldType.text,
      typeConfig: const GroupConfig(),
    );
    final scale = makeField(
      id: 's1',
      name: 'Power',
      fieldTypeId: 'scale',
      fieldType: CustomFieldType.text,
      parentFieldId: 'g1',
      typeConfig: const ScaleConfig(emoji: '⭐', steps: 5),
    );
    final choice = makeField(
      id: 'c1',
      name: 'Mood',
      fieldTypeId: 'choice',
      fieldType: CustomFieldType.choice,
      parentFieldId: 'g1',
      typeConfig: const ChoiceConfig(
        options: [ChoiceOption(id: 'o1', label: 'Happy', colorHex: '#ff0000')],
      ),
    );
    return FieldTemplate.fromDomain([group, scale, choice]);
  }

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );

  testWidgets('leads with Copy + QR and lists what is included', (tester) async {
    await tester.pumpWidget(
      host(
        ShareTemplateSheetContent(
          template: buildTemplate(),
          scrollController: ScrollController(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Copy template'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text("What's included"), findsOneWidget);
    // Real field names appear in the summary (not just a count).
    expect(find.text('Power'), findsWidgets);
    expect(find.text('Mood'), findsWidgets);
  });
}
