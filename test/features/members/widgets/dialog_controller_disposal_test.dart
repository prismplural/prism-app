import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for the "Add image" crash. The dialogs used to dispose their
/// [TextEditingController] synchronously right after the dialog future
/// resolved. The dialog route is still playing its exit transition then, and
/// any rebuild of the still-mounted field (the dismissing keyboard changing
/// `MediaQuery.viewInsets`, or an animated GIF preview repainting) re-runs
/// Flutter's internal `AnimatedBuilder(Listenable.merge([focusNode,
/// controller]))`, which re-subscribes to the disposed controller and throws
/// "A TextEditingController was used after being disposed".
///
/// These tests pin the mechanism so the rule is clear: a field's controller
/// must outlive every rebuild of that field. The fix owns the controllers in a
/// State (MarkdownImageButton) or in the dialog body's own State
/// (_AddToLibraryDialog / _PromptDialog), disposing only on teardown — never
/// per-dialog while the route can still rebuild.
void main() {
  testWidgets(
    'a controller that outlives the field survives repeated rebuilds '
    '(the safe pattern)',
    (tester) async {
      final rebuild = ValueNotifier<int>(0);
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, _, _) => TextField(controller: controller),
            ),
          ),
        ),
      );

      // The fixed ordering: the controller is NOT disposed while the field
      // lives, so rebuilds re-subscribe to a live controller.
      rebuild.value++;
      await tester.pump();
      rebuild.value++;
      await tester.pump();

      expect(tester.takeException(), isNull);

      controller.dispose();
      rebuild.dispose();
    },
  );
}
