import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native FSS commit rewrites preferences with clear before commit', () {
    final source = File(
      'android/app/src/main/kotlin/com/prismplural/prism/MainActivity.kt',
    ).readAsStringSync();

    final method = RegExp(
      r'private fun rewriteSharedPreferencesWithCommit'
      r'\(prefs: SharedPreferences\): Boolean \{([\s\S]*?)\n    \}',
    ).firstMatch(source);

    expect(method, isNotNull);
    final body = method!.group(1)!;
    expect(body, contains('prefs.edit().clear()'));
    expect(body, isNot(contains('snapshot.isEmpty()')));
  });
}
