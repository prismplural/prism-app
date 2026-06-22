import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/core/sharing/field_template_png.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/settings/widgets/branded_template_card.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('renders a QR and does not print the raw code', (tester) async {
    await tester.pumpWidget(
      host(
        const BrandedTemplateCard(
          name: 'Stats',
          code: 'PF1:abc',
          fieldCount: 3,
          typeLabels: ['Rating', 'Choice'],
        ),
      ),
    );

    // The QR + embedded tEXt chunk carry the code; it can't fit legibly on the
    // card, so it is never printed.
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('PF1:abc'), findsNothing);
  });

  testWidgets('shows the template name and a type chip', (tester) async {
    await tester.pumpWidget(
      host(
        const BrandedTemplateCard(
          name: 'Stats',
          code: 'PF1:abc',
          fieldCount: 3,
          typeLabels: ['Rating'],
        ),
      ),
    );

    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
  });

  testWidgets('shows the no-QR note when the code is too long to scan', (
    tester,
  ) async {
    final tooLong = 'PF1:${'a' * 3000}';
    await tester.pumpWidget(
      host(
        BrandedTemplateCard(
          name: 'Everything',
          code: tooLong,
          fieldCount: 50,
          typeLabels: const ['Text'],
        ),
      ),
    );

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Too large for a QR code'), findsOneWidget);
    expect(find.text('Copy the text to import'), findsOneWidget);
  });

  testWidgets('renders in dark mode without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: BrandedTemplateCard(
              name: 'Stats',
              code: 'PF1:abc',
              fieldCount: 3,
              typeLabels: ['Rating'],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Stats'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  test('qrEccForCodeLength matches the QR v40 caps at every boundary', () {
    expect(qrEccForCodeLength(1273), QrErrorCorrectLevel.H);
    expect(qrEccForCodeLength(1274), QrErrorCorrectLevel.Q);
    expect(qrEccForCodeLength(1663), QrErrorCorrectLevel.Q);
    expect(qrEccForCodeLength(1664), QrErrorCorrectLevel.M);
    expect(qrEccForCodeLength(2331), QrErrorCorrectLevel.M);
    expect(qrEccForCodeLength(2332), QrErrorCorrectLevel.L);
    expect(qrEccForCodeLength(2953), QrErrorCorrectLevel.L);
    expect(qrEccForCodeLength(2954), isNull);
  });

  testWidgets('captureBrandedTemplateCardPng embeds the code in the PNG', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      host(
        BrandedTemplateCard(
          boundaryKey: key,
          name: 'Stats',
          code: 'PF1:cap',
          fieldCount: 2,
          typeLabels: const ['Rating'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    Uint8List? png;
    await tester.runAsync(() async {
      png = await captureBrandedTemplateCardPng(key, code: 'PF1:cap', pixelRatio: 1);
    });

    expect(png, isNotNull);
    expect(readTemplateFromPng(png!), 'PF1:cap');
  });

  testWidgets('image round-trip: a real template renders, reads back, and decodes intact', (
    tester,
  ) async {
    // Build a real template (choice with colors + scale), encode it, render the
    // card to a PNG, then read the embedded code back out and decode it — the
    // full "share an image → import it" loop on genuinely rendered bytes.
    final now = DateTime(2026, 1, 1);
    CustomField field(
      String id,
      String name,
      String typeId,
      CustomFieldType type, {
      String? parent,
      CustomFieldTypeConfig? config,
    }) => CustomField(
      id: id,
      name: name,
      fieldType: type,
      createdAt: now,
      fieldTypeId: typeId,
      parentFieldId: parent,
      typeConfig: config,
    );

    final template = FieldTemplate.fromDomain([
      field('g', 'Stats', 'group', CustomFieldType.text,
          config: const GroupConfig()),
      field('c', 'Mood', 'choice', CustomFieldType.choice, parent: 'g',
          config: const ChoiceConfig(options: [
            ChoiceOption(id: 'o1', label: 'Happy', colorHex: '#ff0000'),
            ChoiceOption(id: 'o2', label: 'Sad', colorHex: '#0000ff'),
          ])),
      field('s', 'Energy', 'scale', CustomFieldType.text, parent: 'g',
          config: const ScaleConfig(emoji: '⚡', steps: 7)),
    ]);
    final code = const FieldTemplateCodec().encode(template);

    final key = GlobalKey();
    await tester.pumpWidget(
      host(
        BrandedTemplateCard(
          boundaryKey: key,
          name: 'Stats',
          code: code,
          fieldCount: 2,
          typeLabels: const ['Choice', 'Rating'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    Uint8List? png;
    await tester.runAsync(() async {
      png = await captureBrandedTemplateCardPng(key, code: code);
    });
    expect(png, isNotNull);

    // Read the code back out of the rendered image bytes and decode it.
    final recovered = readTemplateFromPng(png!);
    expect(recovered, code);
    final decoded = const FieldTemplateCodec().decode(recovered!);

    expect(
      decoded.entries.map((e) => e.name).toList(),
      ['Stats', 'Mood', 'Energy'],
    );
    expect(
      decoded.entries.map((e) => e.fieldTypeId).toList(),
      ['group', 'choice', 'scale'],
    );

    // Restored configs survive the whole loop, not just the names.
    final fields = decoded.toDomainFields();
    final choice = fields.firstWhere((f) => f.fieldTypeId == 'choice');
    final choiceConfig = choice.typeConfig as ChoiceConfig;
    expect(
      choiceConfig.options.map((o) => o.label).toList(),
      ['Happy', 'Sad'],
    );
    expect(choiceConfig.options.first.colorHex, '#ff0000');
    final scale = fields.firstWhere((f) => f.fieldTypeId == 'scale');
    expect((scale.typeConfig as ScaleConfig).emoji, '⚡');
    expect((scale.typeConfig as ScaleConfig).steps, 7);
  });
}
