import 'package:flutter/foundation.dart';

enum CommitIntent { noop, set, delete }

@immutable
class SliderEditState {
  const SliderEditState({
    required this.currentValue,
    this.initialValue,
    this.touched = false,
    this.clearedPending = false,
  });

  final double currentValue;
  final double? initialValue;
  final bool touched;
  final bool clearedPending;

  factory SliderEditState.pristine({required double midpoint}) =>
      SliderEditState(currentValue: midpoint);

  factory SliderEditState.loaded({required double value}) =>
      SliderEditState(currentValue: value, initialValue: value);

  bool get isDirty =>
      (touched && currentValue != initialValue) ||
      (clearedPending && initialValue != null);

  bool get canClear => initialValue != null || touched || clearedPending;

  bool get semanticIsUnset =>
      clearedPending || (initialValue == null && !touched);

  CommitIntent get commitIntent {
    if (clearedPending) {
      return initialValue != null ? CommitIntent.delete : CommitIntent.noop;
    }
    if (touched && currentValue != initialValue) return CommitIntent.set;
    return CommitIntent.noop;
  }

  SliderEditState onDrag(double v) =>
      copyWith(currentValue: v, clearedPending: false);

  SliderEditState onDragEnd(double v) =>
      copyWith(currentValue: v, touched: true, clearedPending: false);

  SliderEditState onClear() => copyWith(touched: false, clearedPending: true);

  SliderEditState onCommitSuccess({
    required CommitIntent intent,
    required double midpoint,
  }) {
    switch (intent) {
      case CommitIntent.delete:
        return SliderEditState.pristine(midpoint: midpoint);
      case CommitIntent.set:
        return SliderEditState(currentValue: currentValue, initialValue: currentValue);
      case CommitIntent.noop:
        return this;
    }
  }

  SliderEditState onExternalReload({double? newValue, required double midpoint}) {
    if (newValue == null) return SliderEditState.pristine(midpoint: midpoint);
    return SliderEditState(currentValue: newValue, initialValue: newValue);
  }

  SliderEditState copyWith({
    double? currentValue,
    bool? touched,
    bool? clearedPending,
  }) {
    return SliderEditState(
      currentValue: currentValue ?? this.currentValue,
      initialValue: initialValue,
      touched: touched ?? this.touched,
      clearedPending: clearedPending ?? this.clearedPending,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SliderEditState &&
        other.currentValue == currentValue &&
        other.initialValue == initialValue &&
        other.touched == touched &&
        other.clearedPending == clearedPending;
  }

  @override
  int get hashCode => Object.hash(currentValue, initialValue, touched, clearedPending);

  @override
  String toString() =>
      'SliderEditState(currentValue: $currentValue, initialValue: $initialValue, '
      'touched: $touched, clearedPending: $clearedPending)';
}
