import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/desktop_breakpoint.dart';

void main() {
  group('shouldBeDesktop', () {
    test('switches to desktop at breakpoint (768)', () {
      expect(
        shouldBeDesktop(768, currentlyDesktop: false),
        isTrue,
      );
    });

    test('stays mobile just below breakpoint', () {
      expect(
        shouldBeDesktop(767, currentlyDesktop: false),
        isFalse,
      );
    });

    test('switches back to mobile at off-breakpoint (720)', () {
      expect(
        shouldBeDesktop(719, currentlyDesktop: true),
        isFalse,
      );
    });

    test('stays desktop just above off-breakpoint', () {
      expect(
        shouldBeDesktop(720, currentlyDesktop: true),
        isTrue,
      );
    });

    group('hysteresis dead zone (720–767)', () {
      test('stays mobile if currently mobile', () {
        expect(
          shouldBeDesktop(740, currentlyDesktop: false),
          isFalse,
        );
      });

      test('stays desktop if currently desktop', () {
        expect(
          shouldBeDesktop(740, currentlyDesktop: true),
          isTrue,
        );
      });

      test('retains state at lower edge of dead zone', () {
        expect(
          shouldBeDesktop(720, currentlyDesktop: false),
          isFalse,
        );
        expect(
          shouldBeDesktop(720, currentlyDesktop: true),
          isTrue,
        );
      });

      test('retains state at upper edge of dead zone', () {
        expect(
          shouldBeDesktop(767, currentlyDesktop: false),
          isFalse,
        );
        expect(
          shouldBeDesktop(767, currentlyDesktop: true),
          isTrue,
        );
      });
    });

    group('well outside the dead zone', () {
      test('narrow phone is always mobile', () {
        expect(shouldBeDesktop(375, currentlyDesktop: false), isFalse);
        expect(shouldBeDesktop(375, currentlyDesktop: true), isFalse);
      });

      test('wide desktop is always desktop', () {
        expect(shouldBeDesktop(1200, currentlyDesktop: false), isTrue);
        expect(shouldBeDesktop(1200, currentlyDesktop: true), isTrue);
      });
    });
  });
}
