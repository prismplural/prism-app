import 'package:drift/drift.dart';

/// Represents a single optional field in a partial update.
///
/// Unlike a nullable value, this distinguishes between:
/// - field omitted entirely
/// - field explicitly set to a value
/// - field explicitly cleared to `null`
sealed class FieldPatch<T> {
  const FieldPatch();

  const factory FieldPatch.absent() = AbsentFieldPatch<T>;
  const factory FieldPatch.value(T? value) = ValueFieldPatch<T>;

  bool get isPresent;

  bool get isAbsent => !isPresent;

  T? get valueOrNull;

  T? applyTo(T? currentValue) {
    return when(absent: () => currentValue, value: (value) => value);
  }

  Value<T?> toDriftValue() {
    return when(
      absent: () => const Value.absent(),
      value: Value.new,
    );
  }

  R when<R>({
    required R Function() absent,
    required R Function(T? value) value,
  });
}

final class AbsentFieldPatch<T> extends FieldPatch<T> {
  const AbsentFieldPatch();

  @override
  bool get isPresent => false;

  @override
  T? get valueOrNull => null;

  @override
  R when<R>({
    required R Function() absent,
    required R Function(T? value) value,
  }) {
    return absent();
  }

  @override
  String toString() => 'FieldPatch.absent()';
}

final class ValueFieldPatch<T> extends FieldPatch<T> {
  const ValueFieldPatch(this.value);

  final T? value;

  @override
  bool get isPresent => true;

  @override
  T? get valueOrNull => value;

  @override
  R when<R>({
    required R Function() absent,
    required R Function(T? value) value,
  }) {
    return value(this.value);
  }

  @override
  String toString() => 'FieldPatch.value($value)';
}
