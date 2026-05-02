import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';

void main() {
  group('PinBuffer', () {
    test('stores only numeric digits up to its fixed capacity', () {
      final buffer = PinBuffer(length: 2);

      expect(buffer.appendDigit('1'), isTrue);
      expect(buffer.appendDigit('x'), isFalse);
      expect(buffer.appendDigit('23'), isFalse);
      expect(buffer.appendDigit('2'), isTrue);
      expect(buffer.appendDigit('3'), isFalse);

      expect(buffer.length, 2);
      expect(buffer.consumeStringAndClear(), '12');
    });

    test('removeLast zeros the removed slot', () {
      final buffer = PinBuffer(length: 3)
        ..appendDigit('4')
        ..appendDigit('5');

      buffer.removeLast();

      expect(buffer.length, 1);
      expect(buffer.debugCodeUnits, [0x34, 0, 0]);
    });

    test('consumeStringAndClear returns the PIN and zeros backing storage', () {
      final buffer = PinBuffer(length: 6);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        expect(buffer.appendDigit(digit), isTrue);
      }

      expect(buffer.consumeStringAndClear(), '123456');
      expect(buffer.length, 0);
      expect(buffer.debugCodeUnits, [0, 0, 0, 0, 0, 0]);
    });

    test(
      'consumeBytesAndClear returns PIN bytes and zeros backing storage',
      () {
        final buffer = PinBuffer(length: 6);
        for (final digit in ['1', '2', '3', '4', '5', '6']) {
          expect(buffer.appendDigit(digit), isTrue);
        }

        final bytes = buffer.consumeBytesAndClear();
        addTearDown(() => bytes.fillRange(0, bytes.length, 0));

        expect(bytes, isA<Uint8List>());
        expect(bytes, [0x31, 0x32, 0x33, 0x34, 0x35, 0x36]);
        expect(buffer.length, 0);
        expect(buffer.debugCodeUnits, [0, 0, 0, 0, 0, 0]);
      },
    );
  });
}
