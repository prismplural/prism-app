import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';

void main() {
  testWidgets('uses a subtle plain decorative icon treatment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icon(AppIcons.noteOutlined),
            title: 'Select a note',
            subtitle: 'Choose a note from the list.',
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ExcludeSemantics),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 34 && widget.height == 34,
        ),
      ),
      findsAtLeastNWidgets(1),
    );

    final titleText = tester.widget<Text>(find.text('Select a note'));
    expect(titleText.style?.fontWeight, FontWeight.w600);
    expect(titleText.style?.fontSize, lessThan(24));

    expect(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
  });
}
