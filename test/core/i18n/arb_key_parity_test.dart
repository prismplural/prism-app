// CI guard: every key in app_en.arb must have a matching key in app_es.arb.
// Fails the build if a developer adds an English string without a translation.
//
// Run from app/: flutter test test/core/i18n/arb_key_parity_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ARB key parity', () {
    late Map<String, dynamic> enArb;
    late Map<String, dynamic> esArb;

    setUpAll(() {
      enArb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      esArb = jsonDecode(File('lib/l10n/app_es.arb').readAsStringSync())
          as Map<String, dynamic>;
    });

    test('app_es.arb has every translatable key from app_en.arb', () {
      final enKeys =
          enArb.keys.where((k) => !k.startsWith('@')).toSet();
      final esKeys =
          esArb.keys.where((k) => !k.startsWith('@')).toSet();
      final missing = enKeys.difference(esKeys);
      expect(
        missing,
        isEmpty,
        reason:
            'Missing Spanish translations for: ${missing.toList()..sort()}',
      );
    });

    test('app_es.arb has no orphaned keys missing from app_en.arb', () {
      final enKeys =
          enArb.keys.where((k) => !k.startsWith('@')).toSet();
      final esKeys =
          esArb.keys.where((k) => !k.startsWith('@')).toSet();
      final orphaned = esKeys.difference(enKeys);
      expect(
        orphaned,
        isEmpty,
        reason:
            'Orphaned Spanish keys (no EN counterpart): ${orphaned.toList()..sort()}',
      );
    });

    test('both ARB files are valid JSON', () {
      // If setUpAll succeeded without throwing, both files parsed cleanly.
      expect(enArb, isNotEmpty);
      expect(esArb, isNotEmpty);
    });

    test('app_en.arb has @@locale set to en', () {
      expect(enArb['@@locale'], equals('en'));
    });

    test('app_es.arb has @@locale set to es', () {
      expect(esArb['@@locale'], equals('es'));
    });
  });
}
