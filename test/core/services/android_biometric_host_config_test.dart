import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/biometric_service.dart';

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
    expect(
      activity,
      contains(
        'FSS_BIOMETRIC_STORAGE_NAMESPACE = '
        '"${BiometricService.androidStorageNamespace}"',
      ),
      reason:
          'The Android reset path must know the biometric secure-storage '
          'namespace so full reset clears it.',
    );
    expect(
      activity,
      contains('FSS_BIOMETRIC_STORAGE_NAMESPACE,'),
      reason:
          'The biometric secure-storage preferences must be included in '
          'native full-reset cleanup.',
    );
    expect(
      activity,
      contains(BiometricService.androidDeleteNamespaceMethod),
      reason:
          'Android biometric cleanup must have a narrow native path that '
          'does not initialize flutter_secure_storage.',
    );
    expect(
      activity,
      contains('"FlutterSecureKeyStorage:\$FSS_BIOMETRIC_STORAGE_NAMESPACE"'),
      reason: 'The narrow cleanup must clear the biometric wrapped-key prefs.',
    );
    expect(
      activity,
      contains(
        '"FlutterSecureStorageConfiguration:'
        '\$FSS_BIOMETRIC_STORAGE_NAMESPACE"',
      ),
      reason: 'The narrow cleanup must clear the biometric config prefs.',
    );
    expect(
      activity,
      contains('legacyDefaultBiometricDekPreferenceKey()'),
      reason:
          'The narrow cleanup must also remove the pre-namespace Android '
          'biometric DEK item from default FSS data prefs.',
    );
  });
}
