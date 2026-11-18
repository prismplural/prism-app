import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/chat/widgets/emoji_name_completion_overlay.dart';

/// Physical counterpart of a logical key used in these tests.
///
/// `KeyDownEvent`/`KeyUpEvent` require a real [PhysicalKeyboardKey] and the SDK
/// has no `PhysicalKeyboardKey.none`, so every key a test synthesises is mapped
/// to its actual physical key. An unmapped key is a test bug and throws instead
/// of silently standing in a placeholder.
PhysicalKeyboardKey _physicalKeyFor(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.arrowDown => PhysicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp => PhysicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
    LogicalKeyboardKey.tab => PhysicalKeyboardKey.tab,
    LogicalKeyboardKey.escape => PhysicalKeyboardKey.escape,
    LogicalKeyboardKey.keyA => PhysicalKeyboardKey.keyA,
    _ => throw ArgumentError.value(
      key,
      'key',
      'No physical key mapped for this logical key in the completion tests',
    ),
  };
}

/// Key events also need a timestamp; the overlay reads the logical key and the
/// event type.
KeyDownEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: _physicalKeyFor(key),
  logicalKey: key,
  timeStamp: Duration.zero,
);

KeyUpEvent _keyUp(LogicalKeyboardKey key) => KeyUpEvent(
  physicalKey: _physicalKeyFor(key),
  logicalKey: key,
  timeStamp: Duration.zero,
);

const _matches = <Emoji>[
  Emoji('🌻', 'sunflower | flower'),
  Emoji('🌞', 'sun with face | sun'),
  Emoji('☀️', 'sun'),
];

void main() {
  Widget buildSubject({
    List<Emoji> emojis = _matches,
    ValueChanged<Emoji>? onSelect,
    double availableWidth = 320,
    double availableHeight = 240,
    double textScale = 1,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EmojiNameCompletionOverlay(
                matches: emojis,
                onSelect: onSelect ?? (emoji) {},
                availableWidth: availableWidth,
                availableHeight: availableHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder rowText(String label) => find.descendant(
    of: find.byKey(EmojiNameCompletionOverlay.surfaceKey),
    matching: find.text(label),
  );

  testWidgets('renders one glyph and annotation row per match', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(EmojiNameCompletionOverlay.surfaceKey), findsOneWidget);
    expect(rowText('sunflower'), findsOneWidget);
    expect(rowText('sun with face'), findsOneWidget);
    expect(rowText('sun'), findsOneWidget);
    expect(find.text('🌻'), findsOneWidget);
    expect(find.text('☀️'), findsOneWidget);
  });

  testWidgets('empty matches render nothing at all', (tester) async {
    await tester.pumpWidget(buildSubject(emojis: const []));
    await tester.pumpAndSettle();

    expect(find.byKey(EmojiNameCompletionOverlay.surfaceKey), findsNothing);
  });

  testWidgets('no room above the field renders nothing', (tester) async {
    await tester.pumpWidget(buildSubject(availableHeight: 0));
    await tester.pumpAndSettle();

    expect(find.byKey(EmojiNameCompletionOverlay.surfaceKey), findsNothing);
  });

  testWidgets('a popup too narrow to read is not shown', (tester) async {
    await tester.pumpWidget(buildSubject(availableWidth: 100));
    await tester.pumpAndSettle();

    expect(find.byKey(EmojiNameCompletionOverlay.surfaceKey), findsNothing);
  });

  testWidgets('rows carry glyph and annotation as their accessible name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('🌻 sunflower'), findsOneWidget);
    expect(find.bySemanticsLabel('☀️ sun'), findsOneWidget);
    final data = tester
        .getSemantics(find.bySemanticsLabel('🌻 sunflower'))
        .getSemanticsData();
    expect(data.label, '🌻 sunflower');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('tapping a row selects that emoji', (tester) async {
    Emoji? selected;
    await tester.pumpWidget(
      buildSubject(onSelect: (emoji) => selected = emoji),
    );
    await tester.pumpAndSettle();

    await tester.tap(rowText('sun with face'));
    await tester.pumpAndSettle();

    expect(selected?.emoji, '🌞');
  });

  testWidgets('rows are at least a 44 logical pixel touch target', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final row = find
        .ancestor(
          of: rowText('sunflower'),
          matching: find.byType(GestureDetector),
        )
        .first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(row).width, greaterThanOrEqualTo(100));
  });

  testWidgets('keyboard down and enter select the second match', (
    tester,
  ) async {
    Emoji? selected;
    await tester.pumpWidget(
      buildSubject(onSelect: (emoji) => selected = emoji),
    );
    await tester.pumpAndSettle();
    final state = tester.state<EmojiNameCompletionOverlayState>(
      find.byType(EmojiNameCompletionOverlay),
    );

    expect(
      state.handleKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown)),
      isTrue,
    );
    await tester.pump();
    expect(state.handleKeyEvent(_keyDown(LogicalKeyboardKey.enter)), isTrue);
    await tester.pumpAndSettle();

    expect(selected?.emoji, '🌞');
  });

  testWidgets('arrow up wraps to the last match', (tester) async {
    Emoji? selected;
    await tester.pumpWidget(
      buildSubject(onSelect: (emoji) => selected = emoji),
    );
    await tester.pumpAndSettle();
    final state = tester.state<EmojiNameCompletionOverlayState>(
      find.byType(EmojiNameCompletionOverlay),
    );

    state.handleKeyEvent(_keyDown(LogicalKeyboardKey.arrowUp));
    await tester.pump();
    state.handleKeyEvent(_keyDown(LogicalKeyboardKey.tab));
    await tester.pumpAndSettle();

    expect(selected?.emoji, '☀️');
  });

  testWidgets('escape is consumed but selects nothing', (tester) async {
    var selections = 0;
    await tester.pumpWidget(buildSubject(onSelect: (_) => selections++));
    await tester.pumpAndSettle();
    final state = tester.state<EmojiNameCompletionOverlayState>(
      find.byType(EmojiNameCompletionOverlay),
    );

    expect(state.handleKeyEvent(_keyDown(LogicalKeyboardKey.escape)), isTrue);
    await tester.pumpAndSettle();

    expect(selections, 0);
  });

  testWidgets('unrelated keys are not consumed', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();
    final state = tester.state<EmojiNameCompletionOverlayState>(
      find.byType(EmojiNameCompletionOverlay),
    );

    expect(state.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyA)), isFalse);
    expect(state.handleKeyEvent(_keyUp(LogicalKeyboardKey.arrowDown)), isFalse);
  });

  testWidgets('large text scale keeps rows readable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildSubject(availableWidth: 240, availableHeight: 160, textScale: 2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(EmojiNameCompletionOverlay.surfaceKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(EmojiNameCompletionOverlay.surfaceKey)).height,
      lessThanOrEqualTo(160),
    );
    await tester.tap(rowText('sunflower'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // Regression for the measured B1 defect: a hidden popup (no room, or an
  // anchored width too narrow for a row) must not consume navigation or
  // selection keys, and must never call onSelect for a row nobody can see.
  group('hidden popup does not consume keys', () {
    for (final entry in <({String name, double height, double width})>[
      (name: 'no room above the field', height: 0, width: 320),
      (name: 'too narrow to read', height: 240, width: 100),
    ]) {
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
      ]) {
        testWidgets('${entry.name}: ${key.keyLabel} is not consumed', (
          tester,
        ) async {
          var selections = 0;
          await tester.pumpWidget(
            buildSubject(
              availableHeight: entry.height,
              availableWidth: entry.width,
              onSelect: (_) => selections++,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(EmojiNameCompletionOverlay.surfaceKey),
            findsNothing,
          );

          final state = tester.state<EmojiNameCompletionOverlayState>(
            find.byType(EmojiNameCompletionOverlay),
          );
          expect(state.handleKeyEvent(_keyDown(key)), isFalse);
          await tester.pumpAndSettle();

          expect(selections, 0);
          expect(
            find.byKey(EmojiNameCompletionOverlay.surfaceKey),
            findsNothing,
          );
        });
      }
    }

    testWidgets('a visible popup still consumes and selects exactly once', (
      tester,
    ) async {
      var selections = 0;
      Emoji? selected;
      await tester.pumpWidget(
        buildSubject(
          onSelect: (emoji) {
            selections++;
            selected = emoji;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EmojiNameCompletionOverlay.surfaceKey), findsOneWidget);

      final state = tester.state<EmojiNameCompletionOverlayState>(
        find.byType(EmojiNameCompletionOverlay),
      );
      expect(state.handleKeyEvent(_keyDown(LogicalKeyboardKey.enter)), isTrue);
      await tester.pumpAndSettle();

      expect(selections, 1);
      expect(selected?.emoji, '🌻');
    });
  });

  testWidgets('a shrinking match list resets the highlight to the best row', (
    tester,
  ) async {
    Emoji? selected;
    await tester.pumpWidget(
      buildSubject(onSelect: (emoji) => selected = emoji),
    );
    await tester.pumpAndSettle();
    final state = tester.state<EmojiNameCompletionOverlayState>(
      find.byType(EmojiNameCompletionOverlay),
    );

    // Highlight the second row, then narrow the catalog to one match.
    state.handleKeyEvent(_keyDown(LogicalKeyboardKey.arrowDown));
    await tester.pump();
    await tester.pumpWidget(
      buildSubject(
        emojis: const [Emoji('☀️', 'sun')],
        onSelect: (emoji) => selected = emoji,
      ),
    );
    await tester.pumpAndSettle();

    tester
        .state<EmojiNameCompletionOverlayState>(
          find.byType(EmojiNameCompletionOverlay),
        )
        .handleKeyEvent(_keyDown(LogicalKeyboardKey.enter));
    await tester.pumpAndSettle();

    expect(selected?.emoji, '☀️');
  });
}
