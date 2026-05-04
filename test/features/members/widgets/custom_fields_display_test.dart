import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

void main() {
  const memberId = 'member-1';

  Widget subject({
    required List<CustomField> fields,
    required List<CustomFieldValue> values,
  }) {
    return ProviderScope(
      overrides: [
        customFieldsProvider.overrideWithValue(AsyncValue.data(fields)),
        memberCustomFieldValuesProvider(
          memberId,
        ).overrideWithValue(AsyncValue.data(values)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomFieldsDisplay(memberId: memberId),
          ),
        ),
      ),
    );
  }

  CustomField field(String id, CustomFieldType type, {String? name}) =>
      CustomField(
        id: id,
        name: name ?? 'Field $id',
        fieldType: type,
        createdAt: DateTime(2026, 1, 1),
      );

  CustomFieldValue value(String fieldId, String text) => CustomFieldValue(
    id: 'value-$fieldId',
    customFieldId: fieldId,
    memberId: memberId,
    value: text,
  );

  testWidgets('short text fields render inline markdown', (tester) async {
    await tester.pumpWidget(
      subject(
        fields: [field('short', CustomFieldType.text)],
        values: [value('short', 'hello **bold** and __strong__')],
      ),
    );
    await tester.pump();

    final span = _findTextSpanWithPlainText(tester, 'hello bold and strong');
    expect(span, isNotNull);
    expect(_spanForText(span!, 'bold')?.style?.fontWeight, FontWeight.bold);
    expect(_spanForText(span, 'strong')?.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('long text fields use full markdown rendering', (tester) async {
    await tester.pumpWidget(
      subject(
        fields: [field('long', CustomFieldType.longText)],
        values: [value('long', '# Heading\n\nBody text')],
      ),
    );
    await tester.pump();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('Field long'), findsOneWidget);
  });

  testWidgets('medium fields render as cards while short fields stay grouped', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        fields: [
          field('short', CustomFieldType.text, name: 'Role'),
          field(
            'medium',
            CustomFieldType.text,
            name: 'Detailed internal relationship context',
          ),
        ],
        values: [
          value('short', 'Protector'),
          value(
            'medium',
            'Often prefers quiet check-ins after stressful days.',
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(PrismSectionCard), findsOneWidget);
    expect(find.byType(PrismSurface), findsNWidgets(2));
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Detailed internal relationship context'), findsOneWidget);
  });

  testWidgets('long text truncates and opens full detail sheet', (
    tester,
  ) async {
    final longBody = '${List.filled(180, 'filler').join(' ')} FINAL_SENTINEL';

    await tester.pumpWidget(
      subject(
        fields: [field('bio', CustomFieldType.longText, name: 'Second bio')],
        values: [value('bio', longBody)],
      ),
    );
    await tester.pump();

    expect(find.text('View more'), findsOneWidget);
    expect(_hasRichTextContaining(tester, 'FINAL_SENTINEL'), isFalse);

    await tester.ensureVisible(find.text('View more'));
    await tester.tap(find.text('View more'));
    await tester.pumpAndSettle();

    expect(find.text('Second bio'), findsWidgets);
    expect(_hasRichTextContaining(tester, 'FINAL_SENTINEL'), isTrue);
  });
}

TextSpan? _findTextSpanWithPlainText(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final span = richText.text;
    if (span is TextSpan && span.toPlainText() == text) return span;
  }
  return null;
}

TextSpan? _spanForText(TextSpan root, String text) {
  for (final span in _flatten(root)) {
    if (span.text == text) return span;
  }
  return null;
}

Iterable<TextSpan> _flatten(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _flatten(child);
    }
  }
}

bool _hasRichTextContaining(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    if (richText.text.toPlainText().contains(text)) return true;
  }
  return false;
}
