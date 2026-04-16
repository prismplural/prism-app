import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/crypto/bip39_english_wordlist.dart';
import 'package:prism_plurality/core/crypto/bip39_validate.dart';

// The 24 official Trezor BIP39 English vectors — every entry in the
// "english" list at
//   https://raw.githubusercontent.com/trezor/python-mnemonic/master/vectors.json
// (8 of each length: 12, 18, 24). Only the mnemonic field is asserted here;
// full seed derivation is covered by the Rust cross-language vectors.
const List<String> _trezorEnglishMnemonics = <String>[
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  'legal winner thank year wave sausage worth useful legal winner thank yellow',
  'letter advice cage absurd amount doctor acoustic avoid letter advice cage above',
  'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong',
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent',
  'legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will',
  'letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always',
  'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when',
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art',
  'legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title',
  'letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic bless',
  'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote',
  'ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic',
  'gravity machine north sort system female filter attitude volume fold club stay feature office ecology stable narrow fog',
  'hamster diagram private dutch cause delay private meat slide toddler razor book happy fancy gospel tennis maple dilemma loan word shrug inflict delay length',
  'scheme spot photo card baby mountain device kick cradle pact join borrow',
  'horn tenant knee talent sponsor spell gate clip pulse soap slush warm silver nephew swap uncle crack brave',
  'panda eyebrow bullet gorilla call smoke muffin taste mesh discover soft ostrich alcohol speed nation flash devote level hobby quick inner drive ghost inside',
  'cat swing flag economy stadium alone churn speed unique patch report train',
  'light rule cinnamon wrap drastic word pride squirrel upgrade then income fatal apart sustain crack supply proud access',
  'all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform',
  'vessel ladder alter error federal sibling chat ability sun glass valve picture',
  'scissors invite lock maple supreme raw rapid void congress muscle digital elegant little brisk hair mango congress clump',
  'void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold',
];

void main() {
  group('bip39EnglishWordlist', () {
    test('contains exactly 2048 words', () {
      expect(bip39EnglishWordlist.length, 2048);
      expect(bip39EnglishWordlistSet.length, 2048);
    });

    test('SHA-256 of newline-joined wordlist matches canonical digest', () {
      // Cross-checked against the upstream bitcoin/bips file:
      //   $ curl -sS .../bip-0039/english.txt | shasum -a 256
      // Serves as a regression guard against accidental edits.
      final joined = bip39EnglishWordlist.join('\n');
      final digest = sha256.convert(utf8.encode(joined)).toString();
      expect(
        digest,
        '187db04a869dd9bc7be80d21a86497d692c0db6abd3aa8cb6be5d618ff757fae',
      );
    });

    test('all words are lowercase ASCII', () {
      for (final w in bip39EnglishWordlist) {
        expect(w, equals(w.toLowerCase()));
        expect(RegExp(r'^[a-z]+$').hasMatch(w), isTrue, reason: 'word: $w');
      }
    });
  });

  group('validateBip39Mnemonic — Trezor English vectors', () {
    for (var i = 0; i < _trezorEnglishMnemonics.length; i++) {
      final mnemonic = _trezorEnglishMnemonics[i];
      final wordCount = mnemonic.split(' ').length;
      test('vector $i ($wordCount words) validates', () {
        expect(validateBip39Mnemonic(mnemonic), isTrue);
      });
    }
  });

  group('validateBip39Mnemonic — negative cases', () {
    test('empty string returns false', () {
      expect(validateBip39Mnemonic(''), isFalse);
    });

    test('wrong word count (11 words) returns false', () {
      const eleven =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      expect(eleven.split(' ').length, 11);
      expect(validateBip39Mnemonic(eleven), isFalse);
    });

    test('wrong word count (13 words) returns false', () {
      const thirteen =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about abandon';
      expect(validateBip39Mnemonic(thirteen), isFalse);
    });

    test('word not in the BIP39 list returns false', () {
      // Swap the first word for something definitely not in the list.
      const bad =
          'notaword abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      expect(validateBip39Mnemonic(bad), isFalse);
    });

    test('all valid words but wrong checksum returns false', () {
      // Replace last word ("about" → "abandon"), which is a valid wordlist
      // entry but flips the checksum bits away from the SHA-256 expectation.
      const bad =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
      expect(validateBip39Mnemonic(bad), isFalse);
    });

    test('pre-normalized valid phrase passes', () {
      // The API contract is that callers pass normalized input (lowercase,
      // single-space-delimited). This test documents/locks that contract.
      const valid =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      expect(validateBip39Mnemonic(valid), isTrue);
    });
  });

  group('bip39SuggestionsFor', () {
    test('empty prefix returns empty list', () {
      expect(bip39SuggestionsFor(''), isEmpty);
    });

    test('returns matching words sorted by wordlist order', () {
      final hits = bip39SuggestionsFor('aba');
      // 'abandon' is the first BIP39 word — it must appear first.
      expect(hits, isNotEmpty);
      expect(hits.first, 'abandon');
      for (final w in hits) {
        expect(w.startsWith('aba'), isTrue);
      }
    });

    test('respects the limit', () {
      final hits = bip39SuggestionsFor('a', limit: 3);
      expect(hits.length, 3);
      for (final w in hits) {
        expect(w.startsWith('a'), isTrue);
      }
    });

    test('no matches returns empty list', () {
      expect(bip39SuggestionsFor('qq'), isEmpty);
    });
  });
}
