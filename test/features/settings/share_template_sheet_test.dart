import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/core/sharing/field_template_codec.dart';
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

  // A single choice field with [optionCount] distinct options — distinct
  // labels/colors resist gzip so the encoded code grows predictably.
  FieldTemplate choiceTemplate(int optionCount) {
    return FieldTemplate.fromDomain([
      makeField(
        id: 'big',
        name: 'Element',
        fieldTypeId: 'choice',
        fieldType: CustomFieldType.choice,
        typeConfig: ChoiceConfig(
          options: [
            for (var i = 0; i < optionCount; i++)
              ChoiceOption(
                id: 'o$i',
                label: 'Option $i',
                colorHex: '#${i.toRadixString(16).padLeft(6, '0')}',
              ),
          ],
        ),
      ),
    ]);
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

  testWidgets('too long for a QR → text-only mode (no image, selectable code)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareTemplateSheetContent(
          template: choiceTemplate(1000),
          scrollController: ScrollController(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Share as text'), findsOneWidget);
    expect(find.text('Share image'), findsNothing);
    expect(find.text('Save image'), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Copy template'), findsOneWidget);
  });

  testWidgets('over the option cap → blocked with no card or share actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareTemplateSheetContent(
          template: choiceTemplate(kMaxChoiceOptions + 1),
          scrollController: ScrollController(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('too large to share'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Copy template'), findsNothing);
    expect(find.text('Share as text'), findsNothing);
    // Still lists what's inside so the user can see what to trim.
    expect(find.text("What's included"), findsOneWidget);
  });
}
