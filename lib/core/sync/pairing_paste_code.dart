import 'dart:convert';
import 'dart:typed_data';

/// Layout of an encoded `RendezvousToken` (see
/// prism-sync-core/src/bootstrap/pairing_models.rs):
///   [1B version=0x01][16B rendezvous_id][32B commitment][2B url_len BE][url]
const int kPairingTokenMinBytes = 51;
const int kPairingTokenMaxBytes = 4096;

/// Mirrors `RENDEZVOUS_TOKEN_VERSION`; update in lockstep with the Rust
/// constant.
const int _kPairingTokenVersion = 0x01;
const int _kUrlLenOffset = 49; // 1 + 16 + 32

final RegExp _base64Run = RegExp(r'[A-Za-z0-9+/=]+');
final RegExp _whitespace = RegExp(r'\s+');

/// Extracts a base64-encoded `RendezvousToken` from clipboard or messaging
/// surrounds and returns its raw bytes, or `null` if no valid token is found.
/// Tolerates leading/trailing text, line breaks, and email word-wrapping.
Uint8List? parsePastedPairingCode(String input) {
  if (input.isEmpty) return null;

  // Try whitespace-as-separator first; falling back to whitespace-stripped
  // would otherwise fuse adjacent chat words onto the token and decode to
  // shifted bytes that pass length checks.
  final separated = _bytesOfLongestDecoding(_base64Run.allMatches(input));
  if (separated != null) return separated;

  // Fallback: reassemble tokens fractured by transport word-wrapping.
  final stripped = input.replaceAll(_whitespace, '');
  return _bytesOfLongestDecoding(_base64Run.allMatches(stripped));
}

Uint8List? _bytesOfLongestDecoding(Iterable<RegExpMatch> matches) {
  final candidates = matches.map((m) => m.group(0)!).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final candidate in candidates) {
    if (candidate.length > _kBase64MaxChars) continue;
    final Uint8List bytes;
    try {
      bytes = base64Decode(candidate);
    } on FormatException {
      continue;
    }
    if (!_looksLikeRendezvousToken(bytes)) continue;
    return bytes;
  }
  return null;
}

/// Mirrors `RendezvousToken::from_bytes`. Pure-length validation isn't
/// enough: a long base64-shaped neighbor (PGP signature, hex hash) can
/// decode to a plausibly-sized buffer and outrank the real token.
bool _looksLikeRendezvousToken(Uint8List bytes) {
  if (bytes.length < kPairingTokenMinBytes) return false;
  if (bytes.length > kPairingTokenMaxBytes) return false;
  if (bytes[0] != _kPairingTokenVersion) return false;
  final urlLen = (bytes[_kUrlLenOffset] << 8) | bytes[_kUrlLenOffset + 1];
  return bytes.length == kPairingTokenMinBytes + urlLen;
}

// ceil(kPairingTokenMaxBytes * 4 / 3), padded for "=".
const int _kBase64MaxChars = ((kPairingTokenMaxBytes + 2) ~/ 3) * 4;
