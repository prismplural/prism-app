import 'package:flutter/foundation.dart';

/// Fixed-size numeric PIN buffer that can zero its backing storage.
class PinBuffer {
  PinBuffer({required int length}) : _digits = Uint8List(length);

  final Uint8List _digits;
  int _length = 0;

  int get length => _length;
  bool get isEmpty => _length == 0;
  bool get isFull => _length == _digits.length;

  void replaceWith(PinBuffer source) {
    clear();
    if (source._length > _digits.length) {
      throw ArgumentError.value(
        source._length,
        'source',
        'Source PIN is longer than this buffer.',
      );
    }
    _digits.setRange(0, source._length, source._digits);
    _length = source._length;
  }

  bool contentEquals(PinBuffer other) {
    final maxLength = _digits.length > other._digits.length
        ? _digits.length
        : other._digits.length;
    var diff = _length ^ other._length;
    for (var i = 0; i < maxLength; i++) {
      final a = i < _digits.length ? _digits[i] : 0;
      final b = i < other._digits.length ? other._digits[i] : 0;
      diff |= a ^ b;
    }
    return diff == 0;
  }

  bool appendDigit(String digit) {
    if (isFull || digit.length != 1) return false;

    final codeUnit = digit.codeUnitAt(0);
    if (codeUnit < 0x30 || codeUnit > 0x39) return false;

    _digits[_length] = codeUnit;
    _length++;
    return true;
  }

  void removeLast() {
    if (isEmpty) return;
    _length--;
    _digits[_length] = 0;
  }

  String consumeStringAndClear() {
    final value = String.fromCharCodes(_digits.take(_length));
    clear();
    return value;
  }

  Uint8List consumeBytesAndClear() {
    final value = Uint8List(_length);
    value.setRange(0, _length, _digits);
    clear();
    return value;
  }

  void clear() {
    _digits.fillRange(0, _digits.length, 0);
    _length = 0;
  }

  @visibleForTesting
  List<int> get debugCodeUnits => List.unmodifiable(_digits);
}
