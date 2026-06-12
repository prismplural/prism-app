import 'package:flutter/foundation.dart';

enum PrismIconPickerMode { both, emoji, icon }

enum PrismIconSelectionKind { emoji, phosphor }

@immutable
class PrismIconSelection {
  const PrismIconSelection.emoji(String emoji)
    : this._(kind: PrismIconSelectionKind.emoji, value: emoji);

  const PrismIconSelection.phosphor(String name)
    : this._(kind: PrismIconSelectionKind.phosphor, value: name);

  const PrismIconSelection._({required this.kind, required this.value});

  final PrismIconSelectionKind kind;
  final String value;

  String? get emoji => switch (kind) {
    PrismIconSelectionKind.emoji => value,
    PrismIconSelectionKind.phosphor => null,
  };

  String? get phosphorName => switch (kind) {
    PrismIconSelectionKind.emoji => null,
    PrismIconSelectionKind.phosphor => value,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrismIconSelection && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'PrismIconSelection($kind, $value)';
}
