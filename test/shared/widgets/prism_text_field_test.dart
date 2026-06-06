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

  testWidgets('merges partial style overrides with typography theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: const TextTheme(
            bodyLarge: TextStyle(
              fontFamily: 'OpenDyslexic',
              fontSize: 18,
              letterSpacing: 0.6,
            ),
          ),
        ),
        home: const Scaffold(
          body: PrismTextField(
            initialValue: 'Styled field',
            hintText: 'Styled hint',
            style: TextStyle(color: Colors.red),
            hintStyle: TextStyle(color: Colors.blue),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));

    expect(field.style?.fontFamily, 'OpenDyslexic');
    expect(field.style?.letterSpacing, 0.6);
    expect(field.style?.fontSize, 18);
    expect(field.style?.color, Colors.red);
    expect(field.decoration?.hintStyle?.fontFamily, 'OpenDyslexic');
    expect(field.decoration?.hintStyle?.letterSpacing, 0.6);
    expect(field.decoration?.hintStyle?.fontSize, 18);
    expect(field.decoration?.hintStyle?.color, Colors.blue);
  });
}
