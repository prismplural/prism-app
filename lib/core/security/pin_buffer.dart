import 'package:flutter/foundation.dart';

/// Fixed-size numeric PIN buffer that can zero its backing storage.
class PinBuffer {
  PinBuffer({required int length}) : _digits = Uint8List(length);

  final Uint8List _digits;
  int _length = 0;

  int get length => _length;
  bool get isEmpty => _length == 0;
  bool get isFull => _length == _digits.length;

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

  void clear() {
    _digits.fillRange(0, _digits.length, 0);
    _length = 0;
  }

  @visibleForTesting
  List<int> get debugCodeUnits => List.unmodifiable(_digits);
}
