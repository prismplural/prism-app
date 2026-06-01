import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/text_presentation.dart';

void main() {
  group('requestsTextPresentation', () {
    test('detects literal and entity form of VS15', () {
      expect(requestsTextPresentation('\u231B\uFE0E'), isTrue);
      expect(requestsTextPresentation('&#x231b;&#xFE0E;'), isTrue);
      expect(requestsTextPresentation('&#x231b;&#65038;'), isTrue);
    });

    test('ignores emoji without VS15', () {
      expect(requestsTextPresentation('⌛'), isFalse);
      expect(requestsTextPresentation('⌛️'), isFalse);
      expect(requestsTextPresentation('✨'), isFalse);
    });
  });

  group('textStyleForTextPresentation', () {
    test('leaves ordinary emoji text styles alone', () {
      const style = TextStyle(fontFamilyFallback: ['NotoColorEmoji']);

      expect(textStyleForTextPresentation(style, '✨'), same(style));
    });

    test('adds symbol fonts before existing fallbacks for VS15 text', () {
      const style = TextStyle(fontFamilyFallback: ['NotoColorEmoji']);

      final fallback = textStyleForTextPresentation(
        style,
        '\u231B\uFE0E',
      ).fontFamilyFallback;

      expect(fallback, isNotNull);
      expect(fallback, contains('Noto Sans Symbols'));
      expect(fallback, contains('NotoColorEmoji'));
      expect(
        fallback!.indexOf('Noto Sans Symbols'),
        lessThan(fallback.indexOf('NotoColorEmoji')),
      );
    });
  });
}
