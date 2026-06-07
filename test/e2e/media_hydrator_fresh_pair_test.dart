// Eager-hydration fresh-pair E2E: does MediaHydrator actually pull a newly
// paired device's media into the local cache on its own — WITHOUT the UI ever
// rendering the image? This is the direct test for the "I paired a new device
// and all my media is missing" incident.
//
// No mocks below the hydrator: real FFI, a real spawned relay, the real pairing
// ceremony + snapshot bootstrap, and the real DownloadManager (real FFI download
// + real XChaCha decrypt). The only thing we stand in for is the sync-adapter
// write of the media_attachments row into device B's Drift DB — we insert it
// directly, since the transport/reference correctness (the row surviving the
// pairing snapshot) is already covered by media_fresh_pair_test.dart. This test
// owns the layer above that: given the reference row + a working handle + an
// EMPTY local cache, the hydrator must fetch + decrypt + cache the blob in the
// background, and announce it via a MediaAvailableEvent.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test(
    'hydrator pulls a freshly-paired device\'s media into the local cache '
    'with no UI render',
    skip: e2eSkip(),
    () async {
      final relay = await spawnRelay();
      E2EDevice? a, b;
      AppDatabase? dbB;
      Directory? cacheB;
      try {
        a = await createDevice(relay);

        // A "sends" a media object exactly like a chat/bio image: encrypt the
        // bytes (real XChaCha via FFI), upload the *ciphertext* to the relay,
        // and capture the key + hashes that the media_attachments row carries.
        final encryption = MediaEncryptionService();
        final plaintext = Uint8List.fromList(
          List<int>.generate(8192, (i) => (i * 37 + 11) & 0xff),
        );
        final media = await encryption.encryptMedia(plaintext);
        const mediaId = 'media-hydrate-e2e-0001'; // <=36 chars, alnum + hyphen

        await ffi.uploadMedia(
          handle: a.handle,
          mediaId: mediaId,
          contentHash: media.ciphertextHash,
          data: media.ciphertext,
        );

        // B is a BRAND-NEW device: real pairing ceremony + snapshot bootstrap,
        // landing in A's sync group so it's authorized to fetch A's blobs.
        b = await pairNewDevice(relay, a);

        // Stand in for the sync adapter: the media_attachments reference is now
        // a committed row in B's local Drift DB (its arrival via the snapshot is
        // covered by media_fresh_pair_test.dart). B's media cache is EMPTY.
        dbB = AppDatabase(NativeDatabase.memory());
        await dbB.into(dbB.mediaAttachments).insert(
              MediaAttachmentsCompanion(
                id: const Value('att-hydrate-e2e-1'),
                messageId: const Value('msg-1'),
                mediaId: const Value(mediaId),
                mediaType: const Value('image'),
                encryptionKeyB64: Value(base64Encode(media.key)),
                contentHash: Value(media.ciphertextHash),
                plaintextHash: Value(media.plaintextHash),
                mimeType: const Value('image/png'),
                sizeBytes: Value(plaintext.length),
              ),
            );

        cacheB = await Directory.systemTemp.createTemp('media-hydrate-cache-');
        final downloads = DownloadManager(
          handle: b.handle,
          encryption: encryption,
          cacheDirOverride: cacheB,
        );

        // Precondition: nothing in B's cache yet — the bug's symptom.
        final encFile = File(p.join(cacheB.path, '$mediaId.enc'));
        expect(encFile.existsSync(), isFalse,
            reason: 'fresh device starts with an empty media cache');
        expect(await downloads.isCached(mediaId), isFalse);

        final hydrator = MediaHydrator(
          attachmentsDao: dbB.mediaAttachmentsDao,
          downloadManager: downloads,
          log: (_) {},
        );

        // Capture the "it landed" announcement the UI would repaint on.
        final landed = Completer<String>();
        final sub = hydrator.events.listen((e) {
          if (!landed.isCompleted) landed.complete(e.mediaId);
        });

        // The whole point: background hydration, no UI/getMedia-for-render call.
        await hydrator.enqueuePending();

        final landedId = await landed.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () =>
              throw StateError('hydrator never reported $mediaId landing'),
        );
        await sub.cancel();

        // (1) The hydrator announced the blob.
        expect(landedId, equals(mediaId));

        // (2) The ciphertext is now in B's local cache — fetched purely by the
        //     background hydrator, with the UI never touched.
        expect(encFile.existsSync(), isTrue,
            reason: 'hydrator must write the .enc blob into the local cache');
        expect(await downloads.isCached(mediaId), isTrue);

        // (3) And it's the *right*, usable blob: the cached ciphertext decrypts
        //     back to the original bytes A sent.
        final cachedCiphertext = await encFile.readAsBytes();
        final roundTripped = await encryption.decryptMedia(
          ciphertext: cachedCiphertext,
          key: media.key,
          expectedCiphertextHash: media.ciphertextHash,
          expectedPlaintextHash: media.plaintextHash,
        );
        expect(roundTripped, equals(plaintext),
            reason: 'hydrated blob must decrypt to the original media');

        hydrator.dispose();
      } finally {
        await dbB?.close();
        if (cacheB != null && cacheB.existsSync()) {
          await cacheB.delete(recursive: true);
        }
        a?.dispose();
        b?.dispose();
        relay.stop();
      }
    },
  );

  // The on-demand fallback: even with NO eager hydration, opening any view that
  // renders a not-yet-local image fetches it. Every image surface (chat, bio,
  // notes, custom fields, library, …) resolves bytes through `mediaFileProvider`
  // — so proving that one provider fetches on miss proves the behavior is
  // universal. Here we read it on a freshly-paired device with an empty cache
  // and assert it returns the decrypted bytes pulled live from the relay.
  test(
    'mediaFileProvider (the universal UI fetch hook) downloads an uncached '
    'blob on demand on a freshly-paired device',
    skip: e2eSkip(),
    () async {
      final relay = await spawnRelay();
      E2EDevice? a, b;
      AppDatabase? dbB;
      Directory? cacheB;
      ProviderContainer? container;
      try {
        a = await createDevice(relay);

        final encryption = MediaEncryptionService();
        final plaintext = Uint8List.fromList(
          List<int>.generate(6144, (i) => (i * 53 + 17) & 0xff),
        );
        final media = await encryption.encryptMedia(plaintext);
        const mediaId = 'media-ondemand-e2e-0001';

        await ffi.uploadMedia(
          handle: a.handle,
          mediaId: mediaId,
          contentHash: media.ciphertextHash,
          data: media.ciphertext,
        );

        b = await pairNewDevice(relay, a);

        dbB = AppDatabase(NativeDatabase.memory());
        await dbB.into(dbB.mediaAttachments).insert(
              MediaAttachmentsCompanion(
                id: const Value('att-ondemand-1'),
                messageId: const Value('msg-1'),
                mediaId: const Value(mediaId),
                mediaType: const Value('image'),
                encryptionKeyB64: Value(base64Encode(media.key)),
                contentHash: Value(media.ciphertextHash),
                plaintextHash: Value(media.plaintextHash),
              ),
            );

        cacheB = await Directory.systemTemp.createTemp('media-ondemand-cache-');
        final downloads = DownloadManager(
          handle: b.handle,
          encryption: encryption,
          cacheDirOverride: cacheB,
        );

        // Wire a container exactly like the app: the download manager is bound
        // to device B's handle, the DB holds the synced reference. No eager
        // hydration runs here — only the act of "viewing" drives the fetch.
        container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(dbB),
            downloadManagerProvider.overrideWithValue(downloads),
          ],
        );

        expect(await downloads.isCached(mediaId), isFalse,
            reason: 'precondition: blob is not local before the view renders');

        // This is the exact call every image widget makes to resolve its bytes.
        final params = (
          mediaId: mediaId,
          encryptionKeyB64: base64Encode(media.key),
          ciphertextHash: media.ciphertextHash,
          plaintextHash: media.plaintextHash,
        );
        final bytes = await container
            .read(mediaFileProvider(params).future)
            .timeout(const Duration(seconds: 20));

        // The hook returned the real, decrypted image — fetched on demand —
        // and cached it for next time.
        expect(bytes, isNotNull,
            reason: 'viewing an uncached image must fetch it from the relay');
        expect(bytes, equals(plaintext));
        expect(await downloads.isCached(mediaId), isTrue);
      } finally {
        container?.dispose();
        await dbB?.close();
        if (cacheB != null && cacheB.existsSync()) {
          await cacheB.delete(recursive: true);
        }
        a?.dispose();
        b?.dispose();
        relay.stop();
      }
    },
  );
}
