import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';

void main() {
  group('AppRoutePaths.period', () {
    test('sorts ids and uses repeated query params', () {
      expect(AppRoutePaths.period(['c', 'a', 'b']), '/period?id=a&id=b&id=c');
    });

    test('single id still produces a stable URL', () {
      expect(AppRoutePaths.period(['x']), '/period?id=x');
    });

    test('round-trip: build then parse returns sorted ids', () {
      final url = AppRoutePaths.period(['c', 'a', 'b']);
      expect(parsePeriodIds(Uri.parse(url)), ['a', 'b', 'c']);
    });
  });

  group('parsePeriodIds', () {
    test('returns sorted ids regardless of url order', () {
      expect(parsePeriodIds(Uri.parse('/period?id=c&id=a&id=b')), ['a', 'b', 'c']);
    });

    test('handles missing query string', () {
      expect(parsePeriodIds(Uri.parse('/period')), <String>[]);
    });

    test('handles single id', () {
      expect(parsePeriodIds(Uri.parse('/period?id=alpha')), ['alpha']);
    });
  });
}
