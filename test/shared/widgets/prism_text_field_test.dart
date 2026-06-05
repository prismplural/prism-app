import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

void main() {
  testWidgets('keeps Flutter default text-field scroll physics by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrismTextField(initialValue: 'Default field')),
      ),
    );

    final editableText = tester.widget<EditableText>(find.byType(EditableText));

    expect(editableText.scrollPhysics, isNull);
  });

  testWidgets('forwards explicit text-field scroll physics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrismTextField(
            initialValue: 'Pinned field',
            scrollPhysics: NeverScrollableScrollPhysics(),
          ),
        ),
      ),
    );

    final editableText = tester.widget<EditableText>(find.byType(EditableText));

    expect(editableText.scrollPhysics, isA<NeverScrollableScrollPhysics>());
  });
}
