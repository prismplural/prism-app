import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_picker_text_field_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  testWidgets('renders a labeled picker aligned with the text field input', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const Padding(
          padding: EdgeInsets.all(24),
          child: PrismPickerTextFieldRow(
            pickerLabel: 'Emoji',
            picker: SizedBox(
              key: Key('picker'),
              width: 48,
              height: 48,
              child: ColoredBox(color: Colors.blue),
            ),
            field: PrismTextField(labelText: 'Name', initialValue: 'Alice'),
          ),
        ),
        center: false,
      ),
    );

    final pickerLabelTop = tester.getTopLeft(find.text('Emoji')).dy;
    final fieldLabelTop = tester.getTopLeft(find.text('Name')).dy;
    final pickerTop = tester.getTopLeft(find.byKey(const Key('picker'))).dy;
    final fieldTop = tester.getTopLeft(find.byType(TextFormField)).dy;

    expect((pickerLabelTop - fieldLabelTop).abs(), lessThanOrEqualTo(1));
    expect((pickerTop - fieldTop).abs(), lessThanOrEqualTo(1));
  });
}
