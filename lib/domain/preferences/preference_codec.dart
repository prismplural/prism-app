class PreferenceDecodeException implements Exception {
  const PreferenceDecodeException(this.message);

  final String message;

  @override
  String toString() => 'PreferenceDecodeException: $message';
}

abstract class PreferenceCodec<T> {
  const PreferenceCodec();

  String get valueType;

  Object? encode(T value);

  T decode(Object? value);

  bool isValid(T value) => true;
}

final class BoolPreferenceCodec extends PreferenceCodec<bool> {
  const BoolPreferenceCodec();

  @override
  String get valueType => 'bool';

  @override
  Object encode(bool value) => value;

  @override
  bool decode(Object? value) {
    if (value is bool) return value;
    throw PreferenceDecodeException('Expected bool, got ${value.runtimeType}');
  }
}

final class IntPreferenceCodec extends PreferenceCodec<int> {
  const IntPreferenceCodec({this.min, this.max});

  final int? min;
  final int? max;

  @override
  String get valueType => 'int';

  @override
  Object encode(int value) => value;

  @override
  int decode(Object? value) {
    if (value is int) return value;
    throw PreferenceDecodeException('Expected int, got ${value.runtimeType}');
  }

  @override
  bool isValid(int value) {
    final min = this.min;
    final max = this.max;
    if (min != null && value < min) return false;
    if (max != null && value > max) return false;
    return true;
  }
}

final class DoublePreferenceCodec extends PreferenceCodec<double> {
  const DoublePreferenceCodec({this.min, this.max});

  final double? min;
  final double? max;

  @override
  String get valueType => 'double';

  @override
  Object encode(double value) => value;

  @override
  double decode(Object? value) {
    if (value is double && value.isFinite) return value;
    if (value is int) return value.toDouble();
    throw PreferenceDecodeException(
      'Expected double, got ${value.runtimeType}',
    );
  }

  @override
  bool isValid(double value) {
    if (!value.isFinite) return false;
    final min = this.min;
    final max = this.max;
    if (min != null && value < min) return false;
    if (max != null && value > max) return false;
    return true;
  }
}

final class StringPreferenceCodec extends PreferenceCodec<String> {
  const StringPreferenceCodec({this.allowedValues});

  final Set<String>? allowedValues;

  @override
  String get valueType => 'string';

  @override
  Object encode(String value) => value;

  @override
  String decode(Object? value) {
    if (value is String) return value;
    throw PreferenceDecodeException(
      'Expected string, got ${value.runtimeType}',
    );
  }

  @override
  bool isValid(String value) {
    final allowed = allowedValues;
    return allowed == null || allowed.contains(value);
  }
}

final class JsonPreferenceCodec<T> extends PreferenceCodec<T> {
  const JsonPreferenceCodec({required this.toJson, required this.fromJson});

  final Object? Function(T value) toJson;
  final T Function(Object? value) fromJson;

  @override
  String get valueType => 'json';

  @override
  Object? encode(T value) => toJson(value);

  @override
  T decode(Object? value) => fromJson(value);
}
