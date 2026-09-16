import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Computes a SHA-256 hex digest for [bytes].
///
/// Used to inject a hashing strategy in tests. Production uses
/// [hashBytesForIntegrity].
typedef HashBytesFn = Future<String> Function(Uint8List bytes);

/// Payload sizes at or below this are hashed on the calling isolate.
///
/// Hashing media is pure CPU work, so large payloads must not run on the UI
/// isolate — a multi-megabyte SHA-256 is tens of milliseconds of blocking, which
/// is exactly the kind of main-thread stall that gets an Android app killed for
/// being unresponsive. Spawning an isolate and copying the payload into it is
/// not free either, so the two costs are traded off at a fixed size.
///
/// Measured baseline on Apple Silicon, release-equivalent AOT (`dart compile
/// exe`): isolate spawn plus tiny-payload transfer is ~27us, a 64 KiB digest is
/// ~370us inline, and an 8 MiB digest is ~53ms inline (~150 MiB/s). Payloads at
/// or below this threshold finish well inside a frame budget, so they stay
/// inline; only payloads large enough to visibly stall a frame pay for an
/// isolate.
///
/// This is a size rule rather than a heuristic so the dispatch decision is
/// identical for identical input.
const int kInlineHashThresholdBytes = 64 * 1024;

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

Future<String> _sha256HexOffMain(Uint8List bytes) {
  // Isolate.run copies `bytes` into the helper isolate once and returns only the
  // 64-character digest, so the total transfer cost is a single payload copy.
  return Isolate.run(() => _sha256Hex(bytes));
}

/// Hashes [bytes] to the lowercase hex SHA-256 digest used for media integrity.
///
/// Payloads larger than [inlineThresholdBytes] are hashed on a short-lived
/// helper isolate via [offMain]; smaller payloads are hashed inline so callers
/// do not pay isolate spawn plus payload-copy overhead for work that finishes
/// well under a frame.
///
/// The digest is byte-identical either way: [sha256] is a pure function of its
/// input, so shifting the computation between isolates cannot change stored hash
/// values or hash-mismatch comparisons.
///
/// [offMain] exists so tests can assert the dispatch rule without timing or
/// isolate introspection. Production must leave it at the default, which uses
/// [Isolate.run].
///
/// Scope note: this must only ever hash plain bytes. The flutter_rust_bridge
/// encrypt/decrypt calls used alongside it manage their own Dart isolate and
/// fail from an isolate they did not spawn (see `DownloadManager`), so those
/// calls stay on the caller's isolate. A plain Dart isolate created here has no
/// such restriction.
Future<String> hashBytesForIntegrity(
  Uint8List bytes, {
  int inlineThresholdBytes = kInlineHashThresholdBytes,
  HashBytesFn offMain = _sha256HexOffMain,
}) async {
  assert(
    inlineThresholdBytes >= 0,
    'inlineThresholdBytes must not be negative',
  );
  if (bytes.length <= inlineThresholdBytes) {
    return _sha256Hex(bytes);
  }
  return offMain(bytes);
}
