import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

// ── Test doubles ──────────────────────────────────────────────────────────────

/// Pure-Dart fake encryption service — no FRB/FFI calls.
///
/// Encryption: XOR each byte with key[0] (deterministic and reversible).
/// The real [MediaEncryptionService] calls FRB, which cannot run in unit tests.
class FakeMediaEncryptionService extends MediaEncryptionService {
  @override
  Future<EncryptedMedia> encryptMedia(Uint8List plaintext) async {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    return encryptMediaWithKey(plaintext, key);
  }

  @override
  Future<EncryptedMedia> encryptMediaWithKey(
    Uint8List plaintext,
    Uint8List key,
  ) async {
    final ciphertext = Uint8List.fromList(
      plaintext.map((b) => b ^ key[0]).toList(),
    );
    final plaintextHash = sha256.convert(plaintext).toString();
    final ciphertextHash = sha256.convert(ciphertext).toString();
    return EncryptedMedia(
      ciphertext: ciphertext,
      key: key,
      plaintextHash: plaintextHash,
      ciphertextHash: ciphertextHash,
    );
  }

  @override
  Future<Uint8List> decryptMedia({
    required Uint8List ciphertext,
    required Uint8List key,
    required String expectedCiphertextHash,
    required String expectedPlaintextHash,
  }) async {
    // Verify hashes
    final actualCiphertextHash = sha256.convert(ciphertext).toString();
    if (actualCiphertextHash != expectedCiphertextHash) {
      throw StateError('Ciphertext hash mismatch');
    }
    // XOR decrypt (same as encrypt)
    final plaintext = Uint8List.fromList(
      ciphertext.map((b) => b ^ key[0]).toList(),
    );
    final actualPlaintextHash = sha256.convert(plaintext).toString();
    if (actualPlaintextHash != expectedPlaintextHash) {
      throw StateError('Plaintext hash mismatch');
    }
    return plaintext;
  }
}

/// Builds a [DownloadManager] that never calls path_provider or FFI.
///
/// - [cacheDir]: temporary directory to use as the media cache
/// - [downloadFn]: controls what "downloaded ciphertext" looks like
DownloadManager _makeTestManager(
  Directory cacheDir, {
  DownloadMediaFn? downloadFn,
  FakeMediaEncryptionService? encryption,
}) {
  return DownloadManager(
    handle: null,
    encryption: encryption ?? FakeMediaEncryptionService(),
    cacheDirOverride: cacheDir,
    downloadMediaFn: downloadFn,
  );
}

/// Produces deterministic fake ciphertext and corresponding hashes for
/// [plaintext] using the [FakeMediaEncryptionService] XOR scheme.
({
  Uint8List plaintext,
  Uint8List ciphertext,
  Uint8List key,
  String plaintextHash,
  String ciphertextHash,
})
_fakeMedia(List<int> plaintextBytes) {
  final plaintext = Uint8List.fromList(plaintextBytes);
  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final ciphertext = Uint8List.fromList(
    plaintext.map((b) => b ^ key[0]).toList(),
  );
  return (
    plaintext: plaintext,
    ciphertext: ciphertext,
    key: key,
    plaintextHash: sha256.convert(plaintext).toString(),
    ciphertextHash: sha256.convert(ciphertext).toString(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late MediaEncryptionService encryption;

  setUp(() {
    encryption = MediaEncryptionService();
  });

  // ── DownloadProgress constructor ───────────────────────────────────────

  group('DownloadProgress', () {
    test('stores mediaId, state, and optional error', () {
      const p = DownloadProgress(mediaId: 'abc', state: DownloadState.idle);
      expect(p.mediaId, 'abc');
      expect(p.state, DownloadState.idle);
      expect(p.error, isNull);

      const pErr = DownloadProgress(
        mediaId: 'abc',
        state: DownloadState.failed,
        error: 'network error',
      );
      expect(pErr.error, 'network error');
    });
  });

  // ── DownloadState enum ─────────────────────────────────────────────────

  group('DownloadState', () {
    test('has all expected values', () {
      expect(
        DownloadState.values,
        containsAll([
          DownloadState.idle,
          DownloadState.downloading,
          DownloadState.decrypting,
          DownloadState.completed,
          DownloadState.failed,
        ]),
      );
      expect(DownloadState.values.length, 5);
    });
  });

  // ── progressStream ─────────────────────────────────────────────────────

  group('progressStream', () {
    test('returns a broadcast stream', () {
      final manager = DownloadManager(handle: null, encryption: encryption);
      addTearDown(manager.dispose);

      final stream = manager.progressStream('test-id');
      expect(stream.isBroadcast, isTrue);
    });

    test('reuses the same controller for the same mediaId', () {
      final manager = DownloadManager(handle: null, encryption: encryption);
      addTearDown(manager.dispose);

      // Subscribe to the same mediaId twice. Both subscriptions should
      // receive events from the same underlying broadcast controller.
      final events1 = <DownloadProgress>[];
      final events2 = <DownloadProgress>[];
      final sub1 = manager.progressStream('shared').listen(events1.add);
      final sub2 = manager.progressStream('shared').listen(events2.add);

      // Both listeners are active on the same broadcast controller.
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);

      sub1.cancel();
      sub2.cancel();
    });

    test('returns different streams for different mediaIds', () {
      final manager = DownloadManager(handle: null, encryption: encryption);
      addTearDown(manager.dispose);

      final events1 = <DownloadProgress>[];
      final events2 = <DownloadProgress>[];
      final sub1 = manager.progressStream('id-a').listen(events1.add);
      final sub2 = manager.progressStream('id-b').listen(events2.add);

      expect(events1, isEmpty);
      expect(events2, isEmpty);

      sub1.cancel();
      sub2.cancel();
    });

    test('supports multiple listeners (broadcast)', () async {
      final manager = DownloadManager(handle: null, encryption: encryption);
      addTearDown(manager.dispose);

      final stream = manager.progressStream('multi');
      final events1 = <DownloadProgress>[];
      final events2 = <DownloadProgress>[];

      final sub1 = stream.listen(events1.add);
      final sub2 = stream.listen(events2.add);
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      // We can't easily trigger events without calling getMedia (which hits
      // path_provider), but we can verify both subscriptions are active.
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
    });
  });

  // ── dispose ────────────────────────────────────────────────────────────

  group('dispose', () {
    test('closes all progress stream controllers', () async {
      final manager = DownloadManager(handle: null, encryption: encryption);

      final stream1 = manager.progressStream('d1');
      final stream2 = manager.progressStream('d2');

      var s1Done = false;
      var s2Done = false;
      final sub1 = stream1.listen(null, onDone: () => s1Done = true);
      final sub2 = stream2.listen(null, onDone: () => s2Done = true);

      manager.dispose();

      await Future<void>.delayed(Duration.zero);

      expect(s1Done, isTrue);
      expect(s2Done, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('calling dispose twice does not throw', () {
      final manager = DownloadManager(handle: null, encryption: encryption);
      manager.progressStream('x');
      manager.dispose();
      // Second call: controllers already cleared, no-op.
      manager.dispose();
    });
  });

  // ── getMedia ───────────────────────────────────────────────────────────
  //
  // Note: getMedia calls path_provider (_cacheFileFor) before the try/catch
  // block, so we cannot test it without a platform plugin. The null-handle
  // check and concurrency limiter are unreachable in unit tests. These
  // paths are covered by integration tests instead.

  // ── ciphertext caching (.enc) ──────────────────────────────────────────
  //
  // These tests use [cacheDirOverride] to avoid path_provider and
  // [downloadMediaFn] to avoid FRB/FFI. The fake encryption service uses a
  // pure-Dart XOR cipher so no native code is invoked.

  group('getMedia — ciphertext caching', () {
    late Directory cacheDir;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('dm_test_');
    });

    tearDown(() async {
      if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
    });

    test('stores ciphertext with .enc suffix, not plaintext', () async {
      final media = _fakeMedia([1, 2, 3, 4, 5]);
      final manager = _makeTestManager(cacheDir);
      addTearDown(manager.dispose);

      // Pre-seed the .enc cache to simulate what a previous download writes.
      // Unit tests cannot construct a real [ffi.PrismSyncHandle], so we verify
      // the cache-read path (step 1 of getMedia) directly.
      final encFile = File('${cacheDir.path}/img-1.enc');
      await encFile.writeAsBytes(media.ciphertext);

      // getMedia must read the .enc file and decrypt — no download occurs.
      final result = await manager.getMedia(
        mediaId: 'img-1',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );

      expect(result, isNotNull);
      expect(result, equals(media.plaintext));
      // Plaintext file must NOT exist on disk — only the .enc file should.
      expect(File('${cacheDir.path}/img-1').existsSync(), isFalse);
    });

    test('second call hits .enc cache without re-downloading', () async {
      final media = _fakeMedia([10, 20, 30]);

      var downloadCount = 0;
      final manager = _makeTestManager(
        cacheDir,
        downloadFn:
            ({
              required ffi.PrismSyncHandle handle,
              required String mediaId,
            }) async {
              downloadCount++;
              return media.ciphertext;
            },
      );
      addTearDown(manager.dispose);

      // Pre-seed the .enc cache.
      final encFile = File('${cacheDir.path}/img-2.enc');
      await encFile.writeAsBytes(media.ciphertext);

      // First call — reads from .enc file, no download.
      final result1 = await manager.getMedia(
        mediaId: 'img-2',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );
      expect(downloadCount, 0, reason: 'should read from .enc cache');
      expect(result1, equals(media.plaintext));

      // Second call — same result, still no download.
      final result2 = await manager.getMedia(
        mediaId: 'img-2',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );
      expect(downloadCount, 0, reason: 'still should not re-download');
      expect(result2, equals(media.plaintext));
    });

    test('old plaintext file is deleted and not served', () async {
      final media = _fakeMedia([5, 6, 7, 8]);

      // Write an old-style plaintext cache file (no .enc suffix).
      final plainFile = File('${cacheDir.path}/img-3');
      await plainFile.writeAsBytes(media.plaintext);

      final manager = _makeTestManager(cacheDir);
      addTearDown(manager.dispose);

      // Call getMedia — old plaintext file should be deleted before the
      // download attempt. Since handle == null, getMedia returns null (the
      // StateError is caught internally), but the plaintext file deletion
      // must still have happened first.
      final result = await manager.getMedia(
        mediaId: 'img-3',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );

      // Result is null because handle == null causes a StateError.
      expect(result, isNull);

      // The old plaintext file MUST have been deleted before the download
      // attempt — security invariant.
      expect(
        plainFile.existsSync(),
        isFalse,
        reason: 'old plaintext cache file must be deleted',
      );
    });

    test('_cacheFileFor with encrypted=true appends .enc suffix', () async {
      final media = _fakeMedia([1]);
      final manager = _makeTestManager(cacheDir);
      addTearDown(manager.dispose);

      // Seed an .enc file and verify getMedia finds and reads it.
      final encFile = File('${cacheDir.path}/test-id.enc');
      await encFile.writeAsBytes(media.ciphertext);

      final result = await manager.getMedia(
        mediaId: 'test-id',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );

      expect(result, equals(media.plaintext));
    });

    test(
      '_cacheFileFor with encrypted=true and extension appends ext then .enc',
      () async {
        final media = _fakeMedia([42, 43]);
        final manager = _makeTestManager(cacheDir);
        addTearDown(manager.dispose);

        // Audio variant: cache file should be <mediaId>.m4a.enc
        final encFile = File('${cacheDir.path}/audio-1.m4a.enc');
        await encFile.writeAsBytes(media.ciphertext);

        final result = await manager.getMedia(
          mediaId: 'audio-1',
          encryptionKey: media.key,
          ciphertextHash: media.ciphertextHash,
          plaintextHash: media.plaintextHash,
          fileExtension: '.m4a',
        );

        expect(result, equals(media.plaintext));
      },
    );
  });

  // ── getMediaFile — temp plaintext file ────────────────────────────────

  group('getMediaFile — temp plaintext file', () {
    late Directory cacheDir;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('dm_file_test_');
    });

    tearDown(() async {
      if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
    });

    test('returns a temp file with decrypted bytes', () async {
      final media = _fakeMedia([0xDE, 0xAD, 0xBE, 0xEF]);
      final manager = _makeTestManager(cacheDir);
      addTearDown(manager.dispose);

      final encFile = File('${cacheDir.path}/audio-2.enc');
      await encFile.writeAsBytes(media.ciphertext);

      final file = await manager.getMediaFile(
        mediaId: 'audio-2',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );

      expect(file, isNotNull);
      expect(file!.path.split(Platform.pathSeparator).last, 'audio-2');
      expect(await file.readAsBytes(), equals(media.plaintext));
    });

    test('uses the requested extension when provided', () async {
      final media = _fakeMedia([0x0A, 0x0B, 0x0C]);
      final manager = _makeTestManager(cacheDir);
      addTearDown(manager.dispose);

      final encFile = File('${cacheDir.path}/audio-2.ogg.enc');
      await encFile.writeAsBytes(media.ciphertext);

      final file = await manager.getMediaFile(
        mediaId: 'audio-2',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
        fileExtension: '.ogg',
      );

      expect(file, isNotNull);
      expect(file!.path.split(Platform.pathSeparator).last, 'audio-2.ogg');
      expect(await file.readAsBytes(), equals(media.plaintext));
    });

    test(
      'temp file lives outside the persistent .enc cache (in a tmp subdir)',
      () async {
        final media = _fakeMedia([1, 2]);
        final manager = _makeTestManager(cacheDir);
        addTearDown(manager.dispose);

        final encFile = File('${cacheDir.path}/audio-3.enc');
        await encFile.writeAsBytes(media.ciphertext);

        final file = await manager.getMediaFile(
          mediaId: 'audio-3',
          encryptionKey: media.key,
          ciphertextHash: media.ciphertextHash,
          plaintextHash: media.plaintextHash,
        );

        expect(file, isNotNull);
        // The temp file path must NOT be the same path as the .enc cache file.
        expect(
          file!.path,
          isNot(equals(encFile.path)),
          reason:
              'temp plaintext file must be separate from the .enc cache file',
        );
        // In production the temp dir is getTemporaryDirectory(); in tests with
        // cacheDirOverride it is a /tmp subdirectory — either way it is not the
        // same location as the persistent .enc cache file.
        expect(
          file.path,
          isNot(endsWith('.enc')),
          reason: 'temp file must not have .enc suffix — it is plaintext',
        );
      },
    );

    test('.enc ciphertext file is preserved after getMediaFile', () async {
      final media = _fakeMedia([9, 8, 7]);
      final manager = _makeTestManager(cacheDir);
      addTearDown(manager.dispose);

      final encFile = File('${cacheDir.path}/audio-4.enc');
      await encFile.writeAsBytes(media.ciphertext);

      await manager.getMediaFile(
        mediaId: 'audio-4',
        encryptionKey: media.key,
        ciphertextHash: media.ciphertextHash,
        plaintextHash: media.plaintextHash,
      );

      // The .enc ciphertext cache must still exist after getMediaFile.
      expect(
        encFile.existsSync(),
        isTrue,
        reason:
            '.enc ciphertext cache should be preserved after playback setup',
      );
    });
  });
}
