import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';

void main() {
  group('AppRoutePaths.sleep', () {
    test('constant is /sleep', () {
      expect(AppRoutePaths.sleep, '/sleep');
    });
  });

  group('AppShellTabId.sleep enum name', () {
    test('name matches route constant prefix', () {
      expect(AppShellTabId.sleep.name, 'sleep');
    });
  });
}
