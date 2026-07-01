import 'package:collection/collection.dart';

List<T> sortedByNaturalText<T>(
  Iterable<T> values, {
  required String Function(T value) text,
  required String Function(T value) id,
  int direction = 1,
  int Function(T left, T right)? tieBreak,
}) {
  if (direction != 1 && direction != -1) {
    throw ArgumentError.value(direction, 'direction', 'must be 1 or -1');
  }

  final keyed = [
    for (final value in values)
      _NaturalTextSortEntry(value: value, lowerText: text(value).toLowerCase()),
  ];

  keyed.sort((left, right) {
    final byText = direction * compareNatural(left.lowerText, right.lowerText);
    if (byText != 0) return byText;

    final byTie = tieBreak?.call(left.value, right.value) ?? 0;
    if (byTie != 0) return byTie;

    return id(left.value).compareTo(id(right.value));
  });

  return [for (final entry in keyed) entry.value];
}

int compareNaturalText(String left, String right) {
  return compareNatural(left.toLowerCase(), right.toLowerCase());
}

class _NaturalTextSortEntry<T> {
  const _NaturalTextSortEntry({required this.value, required this.lowerText});

  final T value;
  final String lowerText;
}
