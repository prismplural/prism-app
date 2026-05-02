import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/pairing_sas_display.dart';

void main() {
  group('PairingSasDisplay', () {
    test('current version is SAS v3', () {
      expect(PairingSasDisplay.currentVersion, 3);
    });

    test('parses versioned five-word array', () {
      final sas = PairingSasDisplay.fromJson({
        'sas_version': PairingSasDisplay.currentVersion,
        'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
      });

      expect(sas.words, ['alpha', 'bravo', 'charlie', 'delta', 'echo']);
    });

    test('accepts hyphen-delimited words from JSON strings', () {
      final sas = PairingSasDisplay.fromJson({
        'sas_version': '${PairingSasDisplay.currentVersion}',
        'sas_words': 'alpha-bravo-charlie-delta-echo',
      });

      expect(sas.words, ['alpha', 'bravo', 'charlie', 'delta', 'echo']);
    });

    test('prefers production word list over display phrase', () {
      final sas = PairingSasDisplay.fromJson({
        'sas_version': PairingSasDisplay.currentVersion,
        'sas_words': 'wrong wrong wrong wrong wrong',
        'sas_word_list': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
      });

      expect(sas.words, ['alpha', 'bravo', 'charlie', 'delta', 'echo']);
    });

    test('rejects legacy unversioned three-word SAS data', () {
      expect(
        () => PairingSasDisplay.fromJson({
          'sas_words': 'alpha bravo charlie',
          'sas_decimal': '123456',
        }),
        throwsFormatException,
      );
    });

    test('rejects unsupported SAS version', () {
      expect(
        () => PairingSasDisplay.fromJson({
          'sas_version': 2,
          'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
        }),
        throwsFormatException,
      );
    });

    test('rejects the wrong number of words', () {
      expect(
        () => PairingSasDisplay.fromJson({
          'sas_version': PairingSasDisplay.currentVersion,
          'sas_words': ['alpha', 'bravo', 'charlie', 'delta'],
        }),
        throwsFormatException,
      );
    });

    test('rejects non-string word list entries', () {
      expect(
        () => PairingSasDisplay.fromJson({
          'sas_version': PairingSasDisplay.currentVersion,
          'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 42],
        }),
        throwsFormatException,
      );
    });
  });
}
