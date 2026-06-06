import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font scale can go smaller across all font families', () {
    for (final family in FontFamily.values) {
      expect(family.minimumScale, 0.5);
      expect(family.maximumScale, 1.5);
    }
  });

  test('OpenDyslexic option bundles OpenDyslexic 3 assets', () async {
    expect(FontFamily.openDyslexic.displayName, 'OpenDyslexic');
    expect(FontFamily.openDyslexic.assetFontFamily, 'OpenDyslexic');

    final regular = await rootBundle.load(
      'assets/fonts/OpenDyslexic3-Regular.ttf',
    );
    final bold = await rootBundle.load('assets/fonts/OpenDyslexic3-Bold.ttf');

    expect(
      sha256.convert(regular.buffer.asUint8List()).toString(),
      '54c5c2129fb7ba2c48fa3cb75379f0ea47cfcc24e20f1956a6c080d1efb480a3',
    );
    expect(
      sha256.convert(bold.buffer.asUint8List()).toString(),
      '159a62d2c629cb16867fd2822cbcf64d75e6fb3c915c9d2a14b491e9a6a5f605',
    );
  });

  test('OpenDyslexic italic styles use OpenDyslexic 3 assets', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final openDyslexic = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['family'] == 'OpenDyslexic',
    );
    final fonts = (openDyslexic['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      fonts,
      containsAll([
        containsPair('asset', 'assets/fonts/OpenDyslexic3-Regular.ttf'),
        allOf(
          containsPair('asset', 'assets/fonts/OpenDyslexic3-Regular.ttf'),
          containsPair('style', 'italic'),
        ),
        allOf(
          containsPair('asset', 'assets/fonts/OpenDyslexic3-Bold.ttf'),
          containsPair('weight', 700),
        ),
        allOf(
          containsPair('asset', 'assets/fonts/OpenDyslexic3-Bold.ttf'),
          containsPair('weight', 700),
          containsPair('style', 'italic'),
        ),
      ]),
    );
  });
}
