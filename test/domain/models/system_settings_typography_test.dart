import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

void main() {
  test('font scale can go smaller across all font families', () {
    for (final family in FontFamily.values) {
      expect(family.minimumScale, 0.7);
    }
  });
}
