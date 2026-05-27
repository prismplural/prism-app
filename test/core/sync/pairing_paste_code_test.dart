import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/pairing_paste_code.dart';

/// Builds a structurally-valid encoded `RendezvousToken` body: version byte
/// 0x01, 16 B rendezvous_id, 32 B commitment, 2 B big-endian url_len, then
/// `urlLen` bytes of URL. The parser's shape check requires this layout.
Uint8List _sampleTokenBytes({int urlLen = 45}) {
  final body = Uint8List(kPairingTokenMinBytes + urlLen);
  body[0] = 0x01; // version
  for (var i = 1; i < 49; i++) {
    // 16 B rendezvous_id (1..16) + 32 B commitment (17..48). Content is
    // arbitrary; only the length matters for the parser.
    body[i] = i & 0xff;
  }
  body[49] = (urlLen >> 8) & 0xff;
  body[50] = urlLen & 0xff;
  for (var i = 51; i < body.length; i++) {
    body[i] = i & 0xff;
  }
  return body;
}

void main() {
  group('parsePastedPairingCode', () {
    test('decodes a cleanly-pasted base64 token', () {
      final original = _sampleTokenBytes();
      final encoded = base64Encode(original);

      expect(parsePastedPairingCode(encoded), original);
    });

    test('tolerates surrounding whitespace and line breaks', () {
      final original = _sampleTokenBytes();
      final encoded = base64Encode(original);

      expect(parsePastedPairingCode('  \n$encoded\n  '), original);
    });

    test('reconstitutes a string fractured by email word-wrapping', () {
      final original = _sampleTokenBytes();
      final encoded = base64Encode(original);
      // Insert a CRLF every 32 characters, as a wrapping client might.
      final wrapped = StringBuffer();
      for (var i = 0; i < encoded.length; i += 32) {
        final end = (i + 32).clamp(0, encoded.length);
        wrapped.write(encoded.substring(i, end));
        if (end < encoded.length) wrapped.write('\r\n');
      }

      expect(parsePastedPairingCode(wrapped.toString()), original);
    });

    test('extracts the code from surrounding chat context', () {
      final original = _sampleTokenBytes();
      final encoded = base64Encode(original);
      final chat = "Hi! Here's the pairing code: $encoded — let me know!";

      expect(parsePastedPairingCode(chat), original);
    });

    test('prefers the long candidate over short letter runs nearby', () {
      // Surrounding words form short base64-shaped runs; the encoded token
      // is the only one that decodes to a plausible length.
      final original = _sampleTokenBytes();
      final encoded = base64Encode(original);
      final input = 'Pairing code from Prism: $encoded thanks!';

      expect(parsePastedPairingCode(input), original);
    });

    test(
      'does not fuse adjacent words onto the token when only spaces separate them',
      () {
        // Regression for the "word <token>" shape with no punctuation
        // (e.g. "the code <pairing-code>"). The whitespace-stripped pass
        // would otherwise produce one longer base64-shaped run that
        // decodes to plausibly-sized but shifted bytes, which the FFI
        // would reject. The whitespace-as-separator pass must win.
        final original = _sampleTokenBytes();
        final encoded = base64Encode(original);

        expect(parsePastedPairingCode('code $encoded'), original);
        expect(parsePastedPairingCode('$encoded thanks'), original);
        expect(parsePastedPairingCode('the code $encoded thanks'), original);
      },
    );

    test(
      'rejects long base64-shaped neighbor that decodes to non-token bytes',
      () {
        // Adversarial: a whitespace-separated word that is itself a long
        // base64-shaped run (e.g. an all-A run, a hex hash, random caps)
        // and is longer than the encoded token. Without structural
        // validation, Strategy 1's longest-first ordering would return
        // the neighbor's decoded bytes — the user pairs against garbage
        // and the relay returns a confusing error. The version-byte +
        // url_len structural check rejects the impostor and finds the
        // real token.
        final original = _sampleTokenBytes();
        final encoded = base64Encode(original);
        final longNoise = 'A' * (encoded.length + 16);

        expect(parsePastedPairingCode('$longNoise $encoded'), original);
        expect(parsePastedPairingCode('$encoded $longNoise'), original);
      },
    );

    test(
      'rejects a PGP-style block adjacent to the token',
      () {
        // A user with a PGP signature in their email may paste both. The
        // signature is base64 and substantially longer than a pairing
        // token; without structural validation it would beat the token
        // in length sorting and decode to non-token bytes.
        final original = _sampleTokenBytes();
        final encoded = base64Encode(original);
        // 256 base64 chars of arbitrary structure that decodes to 192 B
        // — none of which is 0x01 at byte 0 with a consistent url_len.
        final pgpLikeBlock = base64Encode(
          Uint8List.fromList(List<int>.generate(192, (i) => (i * 31 + 7) & 0xff)),
        );

        final pasted =
            '-----BEGIN PGP SIGNATURE-----\n$pgpLikeBlock\n-----END PGP SIGNATURE-----\n\n'
            'Pairing code: $encoded';

        expect(parsePastedPairingCode(pasted), original);
      },
    );

    test('rejects structurally-shaped bytes with the wrong version', () {
      // Bytes that pass length validation but have version byte != 0x01
      // must be rejected. Mirrors the Rust `from_bytes` rejection rule.
      final bytes = _sampleTokenBytes();
      bytes[0] = 0x02; // bogus version

      expect(parsePastedPairingCode(base64Encode(bytes)), isNull);
    });

    test('rejects structurally-shaped bytes with inconsistent url_len', () {
      // url_len at offset 49..51 must equal `bytes.length - 51` exactly,
      // matching the Rust no-trailing-bytes rule.
      final bytes = _sampleTokenBytes(urlLen: 45);
      bytes[49] = 0;
      bytes[50] = 99; // claims 99 bytes of URL when only 45 are present

      expect(parsePastedPairingCode(base64Encode(bytes)), isNull);
    });

    test('returns null on empty input', () {
      expect(parsePastedPairingCode(''), isNull);
      expect(parsePastedPairingCode('   \n\t   '), isNull);
    });

    test('returns null on pure-junk input', () {
      expect(parsePastedPairingCode('!!! @@@ ### \$\$\$'), isNull);
    });

    test('returns null when the longest base64 run is too short', () {
      // "AAAA" decodes to 3 bytes — far below the 51-byte minimum.
      expect(parsePastedPairingCode('AAAA'), isNull);
    });

    test('returns null on a truncated token', () {
      final original = _sampleTokenBytes();
      final encoded = base64Encode(original);
      // Drop most of the encoded string, leaving a short base64-shaped run.
      final truncated = encoded.substring(0, 20);

      expect(parsePastedPairingCode(truncated), isNull);
    });

    test('returns null when input has no base64-shaped characters', () {
      expect(parsePastedPairingCode('-_-_-_-_'), isNull);
    });
  });
}
