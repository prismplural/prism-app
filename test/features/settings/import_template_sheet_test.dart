import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/settings/widgets/import_template_sheet.dart';
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

  String validCode() {
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
    return const FieldTemplateCodec().encode(
      FieldTemplate.fromDomain([group, scale]),
    );
  }

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );

  testWidgets('offers paste, choose-image, and scan entry points', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget);
  });

  testWidgets('a valid pasted template opens the preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, validCode());
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Import fields'), findsOneWidget);
  });

  testWidgets('garbage paste shows the "doesn\'t look right" error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'not-a-template');
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(find.textContaining("doesn't look right"), findsOneWidget);
  });

  testWidgets('a newer PF version shows the update message', (tester) async {
    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'PF2:abcdef');
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(find.textContaining('newer version of Prism'), findsOneWidget);
  });

  testWidgets('a malformed-config code shows the error without crashing', (
    tester,
  ) async {
    // A choice entry whose options aren't a List passes structural validation
    // but throws when inflated — must surface as a friendly error, not a crash.
    final bad = FieldTemplate(
      version: 1,
      entries: const [
        FieldTemplateEntry(
          name: 'Mood',
          fieldTypeId: 'choice',
          compactConfig: {'runtimeType': 'choice', 'options': 'notalist'},
        ),
      ],
    );
    final code = const FieldTemplateCodec().encode(bad);

    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, code);
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(find.textContaining("doesn't look right"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
