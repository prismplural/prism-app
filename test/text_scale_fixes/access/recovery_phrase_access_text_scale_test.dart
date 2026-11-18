// Recovery-word entry: every slot a user must transcribe is laid out at the full
// requested size, the 1-12 ordinals are never clipped, the first and last slots
// are reachable, and the word-suggestion strip above the keyboard fits its chips.
//
// Rows and ordinals are sized from the text they hold - the original 40dp row and
// 18dp ordinal stay as floors, and one measured ordinal column covers 1..12 - and
// the suggestion band is one measured chip line plus its padding with the
// original 48dp floor. Paste, autocomplete, focus order and submit behave exactly
// as before and are asserted here.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';

import 'access_text_scale_harness.dart';

/// A canonical BIP39 12-word mnemonic with a valid checksum (synthetic, not key
/// material: it is the published all-"abandon" test vector).
const _phrase =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

Widget _host(
  Widget child, {
  TextScaler? systemScaler,
  double appFontScale = 1.0,
}) {
  return ProviderScope(
    child: accessApp(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
      systemScaler: systemScaler,
      appFontScale: appFontScale,
    ),
  );
}

Finder get _fields => find.byType(TextField);

/// The word slot renders its word at the size the editable really uses.
///
/// The editable's own span, scaler and width are the authority here: a painter
/// built from `TextField.style` loses the ambient DefaultTextStyle and font, so
/// its "needed" height would belong to a different font than the word on screen.
void _expectWordSlotFits(
  WidgetTester tester,
  int index, {
  required String reason,
}) {
  final editable = editableOf(tester, _fields.at(index));
  // `preferredLineHeight` comes from the style's font metrics rather than from
  // this one word's glyphs, so allow a dp for ascent/descent variation.
  final needed = editableLineHeight(editable);
  expect(
    editable.size.height + 1.0,
    greaterThanOrEqualTo(needed),
    reason:
        '$reason: the word needs ${needed.toStringAsFixed(1)}dp but the slot '
        'laid it out at ${editable.size.height.toStringAsFixed(1)}dp',
  );
}

/// Distance between the tops of two fields in the same column, one row apart.
double _rowPitch(WidgetTester tester) {
  return tester.getRect(_fields.at(2)).top - tester.getRect(_fields.at(0)).top;
}

void main() {
  setUpAll(loadAccessFonts);

  testWidgets('default text: the 2x6 grid keeps its 40dp row and 46dp pitch, '
      'and every slot holds a full line', (tester) async {
    useWindow(tester, compactPhone);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(PrismMnemonicField(controller: controller)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_fields, findsNWidgets(12));

    // Baseline geometry preserved: one row is 40dp plus 6dp of spacing.
    expect(_rowPitch(tester), closeTo(46, 0.5));

    for (var i = 0; i < 12; i++) {
      _expectWordSlotFits(tester, i, reason: 'slot ${i + 1} at 1x');
    }
  });

  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
  ]) {
    testWidgets('${scenario.name}: all twelve slots and their numbers are laid '
        'out at full size and the first and last slots are reachable', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          PrismMnemonicField(controller: controller),
          systemScaler: scenario.scaler,
          appFontScale: scenario.app,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a word slot must hold its scaled word line box instead of reporting '
            'an overflow.',
      );

      // Every word slot is tall enough for its own line box, measured from the
      // editable that renders the word.
      for (var i = 0; i < 12; i++) {
        _expectWordSlotFits(
          tester,
          i,
          reason:
              'slot ${i + 1} must show the whole word it asks the user to '
              'type.',
        );
      }

      // Rows do not overlap: the pitch grows with the slot height.
      final pitch = _rowPitch(tester);
      final fieldHeight = tester.getSize(_fields.first).height;
      expect(
        pitch,
        greaterThan(fieldHeight),
        reason:
            'row ${2} must start below row 1 (pitch $pitch, field $fieldHeight)',
      );

      // Slot numbers are not clipped and are not wrapped in a narrow column.
      for (var slot = 1; slot <= 12; slot++) {
        final label = find.text('$slot');
        expect(label, findsOneWidget);
        final paragraph = paragraphOf(tester, label);
        final neededWidth = paragraphIntrinsicWidth(paragraph);
        expect(
          paragraph.size.width + 0.5,
          greaterThanOrEqualTo(neededWidth),
          reason:
              'slot number "$slot" must not be clipped by its column (it needs '
              '${neededWidth.toStringAsFixed(1)}dp).',
        );
        expect(
          paragraphLineCount(paragraph),
          1,
          reason: 'slot number "$slot" must stay on one line',
        );
      }

      // First and last slot are inside the field's own box.
      final fieldRect = tester.getRect(find.byType(PrismMnemonicField));
      expect(
        tester.getRect(_fields.first).top,
        greaterThanOrEqualTo(fieldRect.top - 0.5),
      );
      expect(
        tester.getRect(_fields.at(11)).bottom,
        lessThanOrEqualTo(fieldRect.bottom + 0.5),
        reason: 'the twelfth slot must not be pushed out of the field',
      );
    });
  }

  testWidgets('nonlinear scaler: the fitting follows each font size instead of a '
      'single ratio', (tester) async {
    useWindow(tester, compactPhone);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        PrismMnemonicField(controller: controller),
        systemScaler: const NonlinearTextScaler(),
        appFontScale: 1.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scaler = effectiveScaler(tester, _fields.first);
    // The nonlinear scaler triples sizes below 20 and multiplies larger ones by
    // 1.6, so a width derived from one font size cannot serve the other.
    expect(scaler.scale(11), closeTo(33, 0.01));
    expect(scaler.scale(28), closeTo(44.8, 0.01));

    for (var i = 0; i < 12; i++) {
      _expectWordSlotFits(tester, i, reason: 'nonlinear scaler, slot ${i + 1}');
    }
    final paragraph = paragraphOf(tester, find.text('12'));
    expect(
      paragraph.size.width + 0.5,
      greaterThanOrEqualTo(paragraphIntrinsicWidth(paragraph)),
      reason:
          'the slot number keeps one full glyph width under a nonlinear '
          'scaler',
    );
  });

  testWidgets('short window with the keyboard up: the suggestion strip and its '
      'chips stay on screen at full size', (tester) async {
    useWindow(tester, compactPhone, keyboardInset: 280);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        PrismMnemonicField(controller: controller, autofocus: true),
        systemScaler: maxSystemScaler,
        appFontScale: maxAppFontScale,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_fields.first, 'abou');
    await tester.pumpAndSettle();

    final suggestion = find.text('about');
    expect(suggestion, findsOneWidget);

    final suggestionRect = tester.getRect(suggestion);
    expect(
      suggestionRect.bottom,
      lessThanOrEqualTo(
        (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
            tester.view.devicePixelRatio,
      ),
      reason: 'the suggestion strip must sit above the keyboard inset',
    );
    expect(suggestionRect.top, greaterThanOrEqualTo(0));

    // The chip paints its word at the requested size instead of clipping it in
    // a fixed 48dp band: measured from the chip's own paragraph.
    final paragraph = paragraphOf(tester, suggestion);
    // Measured at the width the chip actually laid the word out with, using the
    // paragraph's own resolved span: no padding or slack is invented for the band.
    final needed = paragraphHeight(paragraph, atWidth: paragraph.size.width);
    final chip = find.ancestor(
      of: suggestion,
      matching: find.byType(GlassSurface),
    );
    expect(chip, findsOneWidget);
    final surface = tester.widget<GlassSurface>(chip);
    debugPrint(
      'RECOVERY_METRICS size=${paragraph.size} naturalHeight=$needed '
      'paintBounds=${paragraph.paintBounds} span=${paragraph.text} '
      'heightBehavior=${paragraph.textHeightBehavior} '
      'scaler=${paragraph.textScaler} chip=${tester.getRect(chip)} '
      'padding=${surface.padding} borderWidth=${surface.borderWidth}',
    );
    tester.element(suggestion).visitAncestorElements((element) {
      final object = element.renderObject;
      if (object is RenderBox &&
          object.hasSize &&
          (object is RenderAbstractViewport ||
              (object is RenderClipRect && object.clipBehavior != Clip.none) ||
              (object is RenderClipRRect &&
                  object.clipBehavior != Clip.none))) {
        final clip = MatrixUtils.transformRect(
          object.getTransformTo(null),
          object.paintBounds,
        );
        expect(
          rectInside(suggestionRect, clip),
          isTrue,
          reason: 'the suggestion must survive ancestor clip $clip',
        );
      }
      return true;
    });
    expect(
      paragraph.size.height + 0.5,
      greaterThanOrEqualTo(needed),
      reason:
          'the suggestion chip must paint its word at the requested size: it '
          'needs ${needed.toStringAsFixed(1)}dp and has '
          '${paragraph.size.height.toStringAsFixed(1)}dp.',
    );

    // Tapping the suggestion still inserts the full word and keeps the strip
    // out of the way (unchanged autocomplete behaviour).
    expect(suggestion.hitTestable(), findsOneWidget);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(controller.text, 'about');
  });

  testWidgets('pasting a whole phrase and a long word keeps the slot semantics '
      'intact', (tester) async {
    useWindow(tester, compactPhone);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        PrismMnemonicField(controller: controller),
        systemScaler: maxSystemScaler,
        appFontScale: maxAppFontScale,
      ),
    );
    await tester.pumpAndSettle();

    // A whole phrase pasted into slot 1 distributes across all twelve slots.
    await tester.enterText(_fields.first, _phrase);
    await tester.pumpAndSettle();
    expect(controller.text, _phrase);
    expect(find.text('12 of 12 words'), findsOneWidget);

    // The word formatter still caps one word at eight characters and leaves the
    // other slots alone.
    await tester.enterText(_fields.at(5), 'abcdefghij');
    await tester.pumpAndSettle();
    final words = controller.text.split(' ');
    expect(words, hasLength(12));
    expect(words[5], 'abcdefgh');
    expect(words[11], 'about');
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitting from the last slot still reports the phrase', (
    tester,
  ) async {
    useWindow(tester, compactPhone);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;

    await tester.pumpWidget(
      _host(
        PrismMnemonicField(
          controller: controller,
          onSubmitted: (value) => submitted = value,
        ),
        systemScaler: maxSystemScaler,
        appFontScale: maxAppFontScale,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_fields.at(11), 'about');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(submitted, 'about');
  });
}
