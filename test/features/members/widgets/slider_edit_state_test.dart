import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/members/widgets/slider_edit_state.dart';

void main() {
  group('SliderEditState', () {
    group('pristine factory', () {
      test('initialises with midpoint, no value, no flags', () {
        final s = SliderEditState.pristine(midpoint: 50);
        expect(s.currentValue, 50.0);
        expect(s.initialValue, isNull);
        expect(s.touched, isFalse);
        expect(s.clearedPending, isFalse);
        expect(s.isDirty, isFalse);
        expect(s.canClear, isFalse);
        expect(s.semanticIsUnset, isTrue);
        expect(s.commitIntent, CommitIntent.noop);
      });
    });

    group('loaded factory', () {
      test('initialises with stored value, canClear true, not dirty', () {
        final s = SliderEditState.loaded(value: 75);
        expect(s.currentValue, 75.0);
        expect(s.initialValue, 75.0);
        expect(s.isDirty, isFalse);
        expect(s.canClear, isTrue);
        expect(s.semanticIsUnset, isFalse);
        expect(s.commitIntent, CommitIntent.noop);
      });
    });

    group('onDragEnd from pristine', () {
      test('marks touched, sets currentValue, becomes dirty with commitIntent set', () {
        final s = SliderEditState.pristine(midpoint: 50).onDragEnd(60);
        expect(s.touched, isTrue);
        expect(s.currentValue, 60.0);
        expect(s.isDirty, isTrue);
        expect(s.canClear, isTrue);
        expect(s.semanticIsUnset, isFalse);
        expect(s.commitIntent, CommitIntent.set);
      });
    });

    group('onDragEnd ending at midpoint with no initialValue', () {
      test('touched is true and isDirty is true (50 != null)', () {
        final s = SliderEditState.pristine(midpoint: 50).onDragEnd(60).onDragEnd(50);
        expect(s.touched, isTrue);
        expect(s.currentValue, 50.0);
        expect(s.initialValue, isNull);
        expect(s.isDirty, isTrue);
        expect(s.commitIntent, CommitIntent.set);
      });
    });

    group('onDragEnd on loaded value without change', () {
      test('touched but no net change means not dirty, noop intent', () {
        final s = SliderEditState.loaded(value: 75).onDragEnd(75);
        expect(s.touched, isTrue);
        expect(s.currentValue, 75.0);
        expect(s.initialValue, 75.0);
        expect(s.isDirty, isFalse);
        expect(s.commitIntent, CommitIntent.noop);
      });
    });

    group('onClear on loaded value', () {
      test('sets clearedPending, resets touched, dirty and delete intent', () {
        final s = SliderEditState.loaded(value: 75).onClear();
        expect(s.touched, isFalse);
        expect(s.clearedPending, isTrue);
        expect(s.currentValue, 75.0);
        expect(s.isDirty, isTrue);
        expect(s.canClear, isTrue);
        expect(s.semanticIsUnset, isTrue);
        expect(s.commitIntent, CommitIntent.delete);
      });
    });

    group('onClear on pristine (no initialValue)', () {
      test('clearedPending true but isDirty false, noop intent', () {
        final s = SliderEditState.pristine(midpoint: 50).onClear();
        expect(s.clearedPending, isTrue);
        expect(s.initialValue, isNull);
        expect(s.isDirty, isFalse);
        expect(s.commitIntent, CommitIntent.noop);
      });
    });

    group('onClear then onDragEnd', () {
      test('drag cancels pending clear, becomes set intent', () {
        final s = SliderEditState.loaded(value: 75).onClear().onDragEnd(20);
        expect(s.clearedPending, isFalse);
        expect(s.touched, isTrue);
        expect(s.currentValue, 20.0);
        expect(s.commitIntent, CommitIntent.set);
      });
    });

    group('onDragEnd then onClear', () {
      test('clear cancels drag, becomes delete intent', () {
        final s = SliderEditState.loaded(value: 75).onDragEnd(20).onClear();
        expect(s.touched, isFalse);
        expect(s.clearedPending, isTrue);
        expect(s.commitIntent, CommitIntent.delete);
        expect(s.semanticIsUnset, isTrue);
      });
    });

    group('onCommitSuccess after delete', () {
      test('resets to pristine with midpoint', () {
        final s = SliderEditState.loaded(value: 75)
            .onClear()
            .onCommitSuccess(intent: CommitIntent.delete, midpoint: 50);
        expect(s.currentValue, 50.0);
        expect(s.initialValue, isNull);
        expect(s.touched, isFalse);
        expect(s.clearedPending, isFalse);
      });
    });

    group('onCommitSuccess after set', () {
      test('promotes currentValue to initialValue, clears flags', () {
        final s = SliderEditState.pristine(midpoint: 50)
            .onDragEnd(60)
            .onCommitSuccess(intent: CommitIntent.set, midpoint: 50);
        expect(s.currentValue, 60.0);
        expect(s.initialValue, 60.0);
        expect(s.touched, isFalse);
        expect(s.clearedPending, isFalse);
        expect(s.isDirty, isFalse);
      });
    });

    group('onExternalReload with new value', () {
      test('external reload wins over pending clear', () {
        final s = SliderEditState.loaded(value: 75)
            .onClear()
            .onExternalReload(newValue: 30, midpoint: 50);
        expect(s.currentValue, 30.0);
        expect(s.initialValue, 30.0);
        expect(s.clearedPending, isFalse);
        expect(s.touched, isFalse);
      });
    });

    group('onExternalReload with null value', () {
      test('resets to pristine', () {
        final s = SliderEditState.loaded(value: 75)
            .onClear()
            .onExternalReload(newValue: null, midpoint: 50);
        expect(s.currentValue, 50.0);
        expect(s.initialValue, isNull);
      });
    });

    group('onDrag without release', () {
      test('updates currentValue but does not touch or make dirty', () {
        final s = SliderEditState.pristine(midpoint: 50).onDrag(70);
        expect(s.currentValue, 70.0);
        expect(s.touched, isFalse);
        expect(s.isDirty, isFalse);
        expect(s.commitIntent, CommitIntent.noop);
      });
    });

    group('equality', () {
      test('identical fields are equal', () {
        const a = SliderEditState(currentValue: 50, initialValue: 75, touched: true);
        const b = SliderEditState(currentValue: 50, initialValue: 75, touched: true);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('differing field makes them unequal', () {
        const a = SliderEditState(currentValue: 50);
        const b = SliderEditState(currentValue: 60);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
