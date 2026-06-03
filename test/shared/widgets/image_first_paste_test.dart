import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/widgets/image_first_paste.dart';

void main() {
  Widget harness({
    required Future<bool> Function() onPasteImage,
    required TextEditingController controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ImagePasteRegion(
          onPasteImage: onPasteImage,
          builder: (context, contextMenuBuilder) => TextField(
            controller: controller,
            autofocus: true,
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
      ),
    );
  }

  testWidgets('PasteTextIntent consults the image handler first', (
    tester,
  ) async {
    var calls = 0;
    final controller = TextEditingController();

    await tester.pumpWidget(
      harness(
        controller: controller,
        onPasteImage: () async {
          calls++;
          return true; // handled
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    Actions.invoke(
      tester.element(find.byType(TextField)),
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(controller.text, isEmpty); // image handled → text paste suppressed
  });

  testWidgets('handler returning false does not throw (text-paste fallback)', (
    tester,
  ) async {
    var calls = 0;
    final controller = TextEditingController();

    await tester.pumpWidget(
      harness(
        controller: controller,
        onPasteImage: () async {
          calls++;
          return false; // no image — fall through to default text paste
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    Actions.invoke(
      tester.element(find.byType(TextField)),
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('context-menu Paste routes through the image handler', (
    tester,
  ) async {
    var calls = 0;
    final controller = TextEditingController(text: 'hello');

    await tester.pumpWidget(
      harness(
        controller: controller,
        onPasteImage: () async {
          calls++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Surface the selection toolbar built by our contextMenuBuilder, then tap
    // its Paste button — the long-press / right-click path, independent of the
    // keyboard intent. Use bounded pumps (the toolbar/selection overlay never
    // settles, so pumpAndSettle would hang).
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pump();
    state.showToolbar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Paste'), findsOneWidget);
    await tester.tap(find.text('Paste'));
    await tester.pump();

    expect(calls, 1);
  });
}
