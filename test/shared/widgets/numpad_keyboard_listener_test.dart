import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/numpad_keyboard_listener.dart';

void main() {
  Future<void> pumpListener(
    WidgetTester tester, {
    required List<String> digits,
    required List<String> backspaces,
    List<String>? submits,
    List<String>? cancels,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumpadKeyboardListener(
            onDigit: digits.add,
            onBackspace: () => backspaces.add('x'),
            onSubmit: submits == null ? null : () => submits.add('x'),
            onCancel: cancels == null ? null : () => cancels.add('x'),
            enabled: enabled,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('top-row digits route to onDigit', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    for (final key in [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit9,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(digits, ['0', '5', '9']);
    expect(backspaces, isEmpty);
  });

  testWidgets('numpad cluster digits route to onDigit', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    for (final key in [
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad7,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(digits, ['1', '4', '7']);
  });

  testWidgets('Backspace and Delete fire onBackspace', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(backspaces, ['x', 'x']);
    expect(digits, isEmpty);
  });

  testWidgets('Enter and numpadEnter fire onSubmit when provided', (
    tester,
  ) async {
    final digits = <String>[];
    final backspaces = <String>[];
    final submits = <String>[];
    await pumpListener(
      tester,
      digits: digits,
      backspaces: backspaces,
      submits: submits,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(submits, ['x', 'x']);
  });

  testWidgets('Escape fires onCancel when provided', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    final cancels = <String>[];
    await pumpListener(
      tester,
      digits: digits,
      backspaces: backspaces,
      cancels: cancels,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancels, ['x']);
  });

  testWidgets('Ctrl+digit is ignored so app shortcuts still work', (
    tester,
  ) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(digits, isEmpty);
  });

  testWidgets('Meta+digit is ignored so app shortcuts still work', (
    tester,
  ) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(digits, isEmpty);
  });

  testWidgets('enabled=false suppresses all callbacks', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    final submits = <String>[];
    final cancels = <String>[];
    await pumpListener(
      tester,
      digits: digits,
      backspaces: backspaces,
      submits: submits,
      cancels: cancels,
      enabled: false,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(digits, isEmpty);
    expect(backspaces, isEmpty);
    expect(submits, isEmpty);
    expect(cancels, isEmpty);
  });

  testWidgets('onSubmit/onCancel null leaves keys ignored', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    // Should not throw; just ignored.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(digits, isEmpty);
    expect(backspaces, isEmpty);
  });

  testWidgets('held digit emits repeat events', (tester) async {
    final digits = <String>[];
    final backspaces = <String>[];
    await pumpListener(tester, digits: digits, backspaces: backspaces);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
    expect(digits, ['2', '2', '2']);
  });
}
