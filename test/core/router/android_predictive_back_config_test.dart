import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest opts into predictive back callbacks', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:enableOnBackInvokedCallback="true"'),
      reason:
          'Flutter predictive back support requires the Android app to opt '
          'into OnBackInvokedCallback so system back gestures can preview '
          'their destination on supported Android versions.',
    );
  });
}
