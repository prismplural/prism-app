// Smoke tests for the i18n infrastructure:
//  1. AppLocalizations resolves correctly under both supported locales.
//  2. DateFormat with locale produces locale-appropriate output.
//
// Run from app/: flutter test test/core/i18n/locale_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // AppLocalizations smoke tests
  // ──────────────────────────────────────────────────────────────────────────

  group('AppLocalizations', () {
    testWidgets('resolves non-null under Locale(en)', (tester) async {
      late AppLocalizations? l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      expect(l10n, isNotNull);
    });

    testWidgets('resolves non-null under Locale(es)', (tester) async {
      late AppLocalizations? l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      expect(l10n, isNotNull);
    });

    testWidgets('cancel string differs between en and es', (tester) async {
      String? enCancel;
      String? esCancel;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('en'),
          home: Builder(builder: (ctx) {
            enCancel = AppLocalizations.of(ctx).cancel;
            return const SizedBox.shrink();
          }),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: Builder(builder: (ctx) {
            esCancel = AppLocalizations.of(ctx).cancel;
            return const SizedBox.shrink();
          }),
        ),
      );
      await tester.pump();

      expect(enCancel, isNotNull);
      expect(esCancel, isNotNull);
      // "Cancel" (en) vs "Cancelar" (es) — must differ
      expect(enCancel, isNot(equals(esCancel)));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // DateFormat locale tests
  // ──────────────────────────────────────────────────────────────────────────

  group('DateFormat with locale', () {
    late DateTime date;

    setUpAll(() {
      date = DateTime(2026, 3, 15);
    });

    test('yMMMd formats differ between en and es', () {
      final enFormatted = DateFormat.yMMMd('en').format(date);
      final esFormatted = DateFormat.yMMMd('es').format(date);

      // The outputs must differ — Spanish uses a different month abbreviation
      expect(esFormatted, isNot(equals(enFormatted)));

      // English output should not contain Spanish month name for March
      // (Spanish: "mar." / "marzo"; English: "Mar")
      expect(enFormatted.toLowerCase(), isNot(contains('mar.')),
          reason: 'English output should not contain Spanish abbreviation');
    });

    test('passing null locale falls back gracefully (no throw)', () {
      // All our extension methods accept nullable locale.
      // Passing null should not throw — ICU picks its default.
      expect(
        () => DateFormat.yMMMd(null).format(date),
        returnsNormally,
      );
    });

    test('regional locale affects date order (en_GB vs en_US)', () {
      // en_GB uses d/M/y order; en_US uses M/d/y — verifies ICU region support.
      final usFormatted = DateFormat.yMd('en_US').format(date);
      final gbFormatted = DateFormat.yMd('en_GB').format(date);
      // March 15: US → 3/15/2026, GB → 15/03/2026
      expect(usFormatted, isNot(equals(gbFormatted)));
    });
  });
}
