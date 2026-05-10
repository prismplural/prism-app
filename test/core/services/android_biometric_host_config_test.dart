import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android host activity satisfies local_auth biometric requirements', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/prismplural/prism/MainActivity.kt',
    ).readAsStringSync();
    final styles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final nightStyles = File(
      'android/app/src/main/res/values-night/styles.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.USE_BIOMETRIC'),
      reason:
          'Android biometric prompts require USE_BIOMETRIC in the merged '
          'manifest. Keep it explicit in the app manifest so local_auth and '
          'flutter_secure_storage biometric flows do not depend on transitive '
          'plugin manifest merging.',
    );
    expect(
      activity,
      contains('FlutterFragmentActivity'),
      reason:
          'local_auth_android returns NOT_FRAGMENT_ACTIVITY unless the '
          'foreground activity is a FragmentActivity. MainActivity must extend '
          'FlutterFragmentActivity for Android biometric unlock.',
    );
    expect(
      styles,
      contains('Theme.AppCompat.DayNight'),
      reason:
          'local_auth_android requires an AppCompat launch theme to avoid '
          'biometric prompt crashes on older supported Android versions.',
    );
    expect(
      nightStyles,
      contains('Theme.AppCompat.DayNight'),
      reason:
          'The night launch theme must stay AppCompat-backed for the same '
          'local_auth_android biometric prompt requirement.',
    );
  });
}
