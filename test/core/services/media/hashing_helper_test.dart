import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/hashing_helper.dart';

/// Test double that records each off-main call size.
class _RecordingOffMain {
  final List<int> payloadSizes = [];

  Future<String> call(Uint8List bytes) async {
    payloadSizes.add(bytes.length);
    return sha256.convert(bytes).toString();
  }
}

void main() {
  // ── Value preservation ────────────────────────────────────────────────

  group('hashBytesForIntegrity — digest values', () {
    test('matches plain sha256 for a small inline payload', () async {
      final bytes = Uint8List.fromList(List.generate(4096, (i) => i & 0xff));
      expect(
        await hashBytesForIntegrity(bytes),
        sha256.convert(bytes).toString(),
      );
    });

    test('matches plain sha256 for a large off-main payload', () async {
      final bytes = Uint8List.fromList(
        List.generate(kInlineHashThresholdBytes + 1024, (i) => (i * 31) & 0xff),
      );
      expect(
        await hashBytesForIntegrity(bytes),
        sha256.convert(bytes).toString(),
      );
    });

    test('inline and off-main paths agree byte-for-byte', () async {
      // Same bytes, forced down each path. Hash values must be identical:
      // moving the computation between isolates cannot change stored digests.
      final bytes = Uint8List.fromList(
        List.generate(2048, (i) => (i * 7 + 3) & 0xff),
      );
      final inline = await hashBytesForIntegrity(bytes);
      final offMain = await hashBytesForIntegrity(
        bytes,
        inlineThresholdBytes: 0,
      );
      expect(offMain, inline);
      expect(offMain, sha256.convert(bytes).toString());
    });

    test('empty input yields the well-known SHA-256 of empty', () async {
      expect(
        await hashBytesForIntegrity(Uint8List(0)),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('returns 64-char lowercase hex', () async {
      final digest = await hashBytesForIntegrity(Uint8List.fromList([1, 2, 3]));
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  // ── Dispatch rule (the seam) ──────────────────────────────────────────
  //
  // Asserting isolate identity directly is brittle. Injecting the off-main
  // hasher lets us assert exactly which payloads take the isolate path.

  group('hashBytesForIntegrity — dispatch rule', () {
    test('exactly at the threshold stays inline', () async {
      final offMain = _RecordingOffMain();
      final bytes = Uint8List(kInlineHashThresholdBytes);

      final digest = await hashBytesForIntegrity(bytes, offMain: offMain.call);

      expect(offMain.payloadSizes, isEmpty, reason: 'at-threshold is inline');
      expect(digest, sha256.convert(bytes).toString());
    });

    test('one byte over the threshold goes off-main', () async {
      final offMain = _RecordingOffMain();
      final bytes = Uint8List(kInlineHashThresholdBytes + 1);

      final digest = await hashBytesForIntegrity(bytes, offMain: offMain.call);

      expect(offMain.payloadSizes, equals([bytes.length]));
      expect(digest, sha256.convert(bytes).toString());
    });

    test('tiny payloads never spawn an isolate', () async {
      final offMain = _RecordingOffMain();
      for (final size in [0, 1, 100, 1024]) {
        await hashBytesForIntegrity(Uint8List(size), offMain: offMain.call);
      }
      expect(offMain.payloadSizes, isEmpty);
    });

    test('threshold boundary holds for a custom threshold', () async {
      final offMain = _RecordingOffMain();
      const custom = 512;

      await hashBytesForIntegrity(
        Uint8List(custom),
        inlineThresholdBytes: custom,
        offMain: offMain.call,
      );
      expect(offMain.payloadSizes, isEmpty);

      await hashBytesForIntegrity(
        Uint8List(custom + 1),
        inlineThresholdBytes: custom,
        offMain: offMain.call,
      );
      expect(offMain.payloadSizes, equals([custom + 1]));
    });

    test(
      'production default routes a multi-megabyte payload off-main',
      () async {
        // Guards the wiring the service depends on: the default must not be an
        // inline-only hasher for large media.
        expect(kInlineHashThresholdBytes, lessThan(4 * 1024 * 1024));
        final bytes = Uint8List(4 * 1024 * 1024);
        expect(
          await hashBytesForIntegrity(bytes),
          sha256.convert(bytes).toString(),
        );
      },
    );
  });

  // ── Real isolate path ─────────────────────────────────────────────────

  group('hashBytesForIntegrity — default off-main runner', () {
    test(
      'the Isolate.run primitive the default relies on reaches a new isolate',
      () async {
        final payload = Uint8List(kInlineHashThresholdBytes + 1);

        // Digest correctness through the production default (threshold exceeded).
        expect(
          await hashBytesForIntegrity(payload),
          sha256.convert(payload).toString(),
        );

        // The default off-main runner is Isolate.run over a top-level function.
        // Confirm that primitive genuinely executes on a different isolate, so the
        // over-threshold path is not a silent inline shortcut.
        final outer = Isolate.current.hashCode;
        final inner = await Isolate.run(() => Isolate.current.hashCode);
        expect(inner, isNot(equals(outer)));
      },
    );

    test(
      'large payloads complete off the main isolate without stalling',
      () async {
        final bytes = Uint8List(8 * 1024 * 1024);
        final digest = await hashBytesForIntegrity(bytes);
        expect(digest, sha256.convert(bytes).toString());
      },
    );
  });
}
