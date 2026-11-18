// Accept-invite sheet: the Cancel / Send Request row belongs to the sheet at
// every text scale, with the keyboard up, and with long input.
//
// The sheet is mounted by PrismSheet.showFullScreen, whose body is tight to the
// viewport, so its content has to scroll: the actions are pinned below the
// scrolling body, which carries the title, both fields, the preview and the scope
// rows. The assertions below describe that behaviour - every action stays inside
// the sheet, and cancelling sends nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/sharing/views/accept_invite_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

import 'access_text_scale_harness.dart';

/// Opens the real full-screen accept-invite sheet exactly like the sharing
/// screen does and keeps the value the route returns.
class _InviteHost extends StatelessWidget {
  const _InviteHost({required this.onResult});

  final void Function(bool?) onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (buttonContext) => TextButton(
            onPressed: () async {
              final result = await PrismSheet.showFullScreen<bool>(
                context: buttonContext,
                builder: (context, _) => const AcceptInviteSheet(),
              );
              onResult(result);
            },
            child: const Text('open invite sheet'),
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required Size size,
  TextScaler? systemScaler,
  double appFontScale = 1.0,
  double keyboardInset = 0,
  void Function(bool?)? onResult,
}) async {
  useWindow(tester, size, keyboardInset: keyboardInset);
  await tester.pumpWidget(
    ProviderScope(
      child: accessApp(
        _InviteHost(onResult: onResult ?? (_) {}),
        systemScaler: systemScaler,
        appFontScale: appFontScale,
      ),
    ),
  );
  await tester.tap(find.text('open invite sheet'));
  await tester.pumpAndSettle();
  expect(find.byType(AcceptInviteSheet), findsOneWidget);
}

void _expectActionRowOnSheet(
  WidgetTester tester,
  Size size, {
  double? maxBottom,
}) {
  final bottomLimit = maxBottom ?? size.height;
  for (final label in ['Cancel', 'Send Request']) {
    final button = find.widgetWithText(PrismButton, label);
    expect(button, findsOneWidget, reason: '$label must be on the sheet');
    final rect = tester.getRect(button);
    expect(
      rect.top,
      greaterThanOrEqualTo(0),
      reason: '$label is above the sheet top: $rect',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(bottomLimit),
      reason:
          '$label must stay on the sheet: it is at $rect on a '
          '${size.height}dp viewport (limit $bottomLimit).',
    );
    final labelRect = tester.getRect(find.text(label));
    expect(labelRect.bottom, lessThanOrEqualTo(bottomLimit));
    expect(labelRect.top, greaterThanOrEqualTo(0));
  }
}

void main() {
  setUpAll(loadAccessFonts);

  testWidgets('default text: Cancel and Send Request are on the sheet and '
      'Cancel dismisses without sending', (tester) async {
    bool? result;
    var closed = false;
    await _pumpSheet(
      tester,
      size: compactPhone,
      onResult: (value) {
        result = value;
        closed = true;
      },
    );

    expect(tester.takeException(), isNull);
    _expectActionRowOnSheet(tester, compactPhone);

    await tester.tap(find.widgetWithText(PrismButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull, reason: 'cancelling sends nothing');
    expect(find.byType(AcceptInviteSheet), findsNothing);
  });

  testWidgets('Send Request is inert until the sheet has something to send', (
    tester,
  ) async {
    await _pumpSheet(tester, size: compactPhone);

    final sendButton = tester.widget<PrismButton>(
      find.widgetWithText(PrismButton, 'Send Request'),
    );
    expect(sendButton.enabled, isFalse);

    await tester.tap(find.widgetWithText(PrismButton, 'Send Request'));
    await tester.pumpAndSettle();

    // The tap does nothing: the sheet is still there and nothing was sent.
    expect(find.byType(AcceptInviteSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
  ]) {
    testWidgets('${scenario.name}: the action row stays on a compact phone and '
        'Cancel still dismisses', (tester) async {
      bool? result;
      var closed = false;
      await _pumpSheet(
        tester,
        size: compactPhone,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
        onResult: (value) {
          result = value;
          closed = true;
        },
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the sheet body must fit the space it is given: it is tight to the '
            'viewport, so its content scrolls instead of overflowing.',
      );
      _expectActionRowOnSheet(tester, compactPhone);

      await tester.tap(find.widgetWithText(PrismButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('${scenario.name} with long input: nothing is pushed off the '
        'sheet', (tester) async {
      await _pumpSheet(
        tester,
        size: compactPhone,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
      );

      // A long display name and a long, invalid sharing code: the error
      // surface and the preview row both grow, and the action row must still
      // be on the sheet.
      const longName = 'Wren and Nico of the Long-Named System';
      final longCode = 'prism-share:${'ab' * 120}';
      // The body is a lazy ListView: a field below the fold is not built, so it is
      // scrolled to by its own label (never indexed among "all fields", which
      // would count only the ones that happen to exist).
      final body = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Sharing code'),
        120,
        scrollable: body,
      );
      await tester.pumpAndSettle();
      final codeField = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is PrismTextField && widget.labelText == 'Sharing code',
        ),
        matching: find.byType(TextField),
      );
      expect(codeField, findsOneWidget);
      await tester.enterText(codeField, longCode);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Your display name'),
        120,
        scrollable: body,
      );
      await tester.pumpAndSettle();
      final nameField = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is PrismTextField &&
              widget.labelText == 'Your display name',
        ),
        matching: find.byType(TextField),
      );
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, longName);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      _expectActionRowOnSheet(tester, compactPhone);
    });
  }

  testWidgets('composed 3.375x with the keyboard up on a compact phone: the '
      'action row is still reachable', (tester) async {
    await _pumpSheet(
      tester,
      size: compactPhone,
      systemScaler: maxSystemScaler,
      appFontScale: maxAppFontScale,
      keyboardInset: 260,
    );

    expect(tester.takeException(), isNull);
    // The sheet is padded above the keyboard, so the actions must clear it.
    _expectActionRowOnSheet(
      tester,
      compactPhone,
      maxBottom: compactPhone.height - 260,
    );

    // Typing into the code field keeps the sheet usable: the field is on the
    // sheet and the actions do not move off it.
    final body = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Sharing code'),
      120,
      scrollable: body,
    );
    await tester.pumpAndSettle();
    final codeField = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is PrismTextField && widget.labelText == 'Sharing code',
      ),
      matching: find.byType(TextField),
    );
    expect(codeField, findsOneWidget);
    await tester.enterText(codeField, 'prism-share:abc');
    await tester.pumpAndSettle();
    _expectActionRowOnSheet(
      tester,
      compactPhone,
      maxBottom: compactPhone.height - 260,
    );
  });
}
