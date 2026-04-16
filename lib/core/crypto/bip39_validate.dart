// BIP39 mnemonic validation for UI-layer input.
//
// The authoritative BIP39 derivation lives in Rust (prism-sync-crypto) and is
// covered by cross-language test vectors. This Dart validator only exists to
// give the recovery-phrase UI local checksum validation and autocomplete.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'package:prism_plurality/core/crypto/bip39_english_wordlist.dart';

const Set<int> _validWordCounts = {12, 15, 18, 21, 24};

/// Returns true if [phrase] is a valid BIP39 English mnemonic: its word count
/// is one of 12/15/18/21/24, every word is in the wordlist, and the embedded
/// checksum matches the SHA-256 of the decoded entropy.
///
/// Whitespace/case normalization is the caller's responsibility — pass a
/// pre-normalized lowercase string (use [PrismMnemonicField.normalize] or
/// similar).
bool validateBip39Mnemonic(String phrase) {
  if (phrase.isEmpty) return false;
  final words = phrase.split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  final count = words.length;
  if (!_validWordCounts.contains(count)) return false;

  // Look up each word; bail on any miss.
  final indices = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final idx = bip39EnglishWordlistSet.contains(words[i])
        ? bip39EnglishWordlist.indexOf(words[i])
        : -1;
    if (idx < 0) return false;
    indices[i] = idx;
  }

  // BIP39 splits the total bits (count * 11) into ENT:CS at a 32:1 ratio —
  // i.e. entropy takes ENT = count * 11 * 32 / 33 bits, checksum takes the
  // rest. For 12 words: 128 ENT + 4 CS. For 24 words: 256 ENT + 8 CS.
  final totalBits = count * 11;
  final entropyBits = totalBits * 32 ~/ 33;
  final checksumBits = totalBits - entropyBits;
  final entropyBytes = entropyBits ~/ 8;

  // Pack the word indices (11 bits each, big-endian) into a single bit buffer
  // and split into entropy + checksum halves.
  final buffer = Uint8List(entropyBytes + 1);
  var bitPos = 0;
  for (final idx in indices) {
    for (var b = 10; b >= 0; b--) {
      if ((idx >> b) & 1 == 1) {
        buffer[bitPos ~/ 8] |= 1 << (7 - (bitPos % 8));
      }
      bitPos++;
    }
  }

  final entropy = Uint8List.sublistView(buffer, 0, entropyBytes);
  final expectedChecksum = _readBits(buffer, entropyBits, checksumBits);

  // Checksum is the first checksumBits of SHA-256(entropy).
  final digest = sha256.convert(entropy).bytes;
  final digestBuf = Uint8List.fromList(digest);
  final actualChecksum = _readBits(digestBuf, 0, checksumBits);

  return expectedChecksum == actualChecksum;
}

/// Returns up to [limit] wordlist entries that start with [prefix].
/// Case-sensitive; the caller should lowercase. Empty prefix returns [].
List<String> bip39SuggestionsFor(String prefix, {int limit = 5}) {
  if (prefix.isEmpty) return const [];
  final hits = <String>[];
  for (final w in bip39EnglishWordlist) {
    if (w.startsWith(prefix)) {
      hits.add(w);
      if (hits.length >= limit) break;
    }
  }
  return hits;
}

/// Reads [count] bits starting at [startBit] from [source] as a big-endian
/// unsigned integer. Caller guarantees count <= 32.
int _readBits(Uint8List source, int startBit, int count) {
  var result = 0;
  for (var i = 0; i < count; i++) {
    final pos = startBit + i;
    final bit = (source[pos ~/ 8] >> (7 - (pos % 8))) & 1;
    result = (result << 1) | bit;
  }
  return result;
}
