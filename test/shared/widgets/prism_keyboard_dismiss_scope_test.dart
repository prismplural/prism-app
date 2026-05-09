import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/prism_keyboard_dismiss_scope.dart';

void main() {
  testWidgets('dismisses focused text field on mobile touch outside', (
    tester,
  ) async {
    await _withMobilePlatform(() async {
      final focusNode = FocusNode();
      var outsideTapped = false;
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PrismKeyboardDismissScope(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: focusNode),
                  GestureDetector(
                    key: const Key('outside'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => outsideTapped = true,
                    child: const SizedBox(width: 200, height: 200),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const Key('outside')));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
      expect(outsideTapped, isTrue);
    });
  });

  testWidgets('keeps focus when tapping a TextFieldTapRegion control', (
    tester,
  ) async {
    await _withMobilePlatform(() async {
      final focusNode = FocusNode();
      var controlTapped = false;
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PrismKeyboardDismissScope(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: focusNode),
                  TextFieldTapRegion(
                    child: GestureDetector(
                      key: const Key('field-control'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controlTapped = true,
                      child: const SizedBox(width: 200, height: 200),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const Key('field-control')));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
      expect(controlTapped, isTrue);
    });
  });

  testWidgets('moves focus normally when another text field is tapped', (
    tester,
  ) async {
    await _withMobilePlatform(() async {
      final firstFocusNode = FocusNode();
      final secondFocusNode = FocusNode();
      addTearDown(firstFocusNode.dispose);
      addTearDown(secondFocusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PrismKeyboardDismissScope(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(
                    key: const Key('first-field'),
                    focusNode: firstFocusNode,
                  ),
                  TextField(
                    key: const Key('second-field'),
                    focusNode: secondFocusNode,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('first-field')));
      await tester.pump();

      expect(firstFocusNode.hasFocus, isTrue);
      expect(secondFocusNode.hasFocus, isFalse);

      await tester.tap(find.byKey(const Key('second-field')));
      await tester.pump();

      expect(firstFocusNode.hasFocus, isFalse);
      expect(secondFocusNode.hasFocus, isTrue);
    });
  });
}

Future<void> _withMobilePlatform(Future<void> Function() body) async {
  final previousPlatform = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previousPlatform;
  }
}
