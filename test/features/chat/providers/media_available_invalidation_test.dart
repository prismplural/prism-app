// The load-bearing repaint: when background hydration lands a blob, an image
// that already rendered a placeholder (mediaFileProvider resolved to null)
// must re-resolve and surface the bytes — without the user touching anything.
//
// This is the wiring added in media_state_providers.dart: mediaFileProvider
// listens to mediaAvailableProvider and invalidates itself on a matching
// MediaAvailableEvent. Proven here at the provider layer (no FFI): a fake
// download manager returns null first (not on the relay yet), then bytes; an
// event for the matching media id flips the provider from null to the bytes.

import 'dart:async';

import 'package:drift/drift.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/services/media/download_manager.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/core/services/media/media_hydrator.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_available_provider.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';

class _NoopEncryption extends MediaEncryptionService {}

/// Returns null for the first [missesBefore] getMedia calls (blob not on the
/// relay yet), then the real bytes — modelling "placeholder, then hydrated".
class _NullThenBytesDownloadManager extends DownloadManager {
  _NullThenBytesDownloadManager({this.missesBefore = 1})
      : super(handle: null, encryption: _NoopEncryption());

  final int missesBefore;
  int calls = 0;

  @override
  Future<bool> isCached(String mediaId, {String fileExtension = ''}) async =>
      false;

  @override
  Future<MediaFetchResult> getMedia({
    required String mediaId,
    required Uint8List encryptionKey,
    required String ciphertextHash,
    required String plaintextHash,
    String fileExtension = '',
  }) async {
    calls += 1;
    if (calls <= missesBefore) {
      return const MediaFetchFailure(ffi.MediaFetchErrorKind.other);
    }
    return MediaFetchOk(Uint8List.fromList([7, 7, 7]));
  }
}

void main() {
  test(
    'mediaFileProvider re-resolves from null to bytes when a matching '
    'MediaAvailableEvent fires',
    () async {
      final downloads = _NullThenBytesDownloadManager(missesBefore: 1);
      final events = StreamController<MediaAvailableEvent>.broadcast();
      addTearDown(events.close);

      final container = ProviderContainer(
        overrides: [
          downloadManagerProvider.overrideWithValue(downloads),
          // Drive the "blob landed" signal directly, standing in for the
          // hydrator's event stream.
          mediaAvailableProvider.overrideWith((ref) => events.stream),
        ],
      );
      addTearDown(container.dispose);

      const params = (
        mediaId: 'mfp-invalidate-1',
        encryptionKeyB64: 'a2V5',
        ciphertextHash: 'ch',
        plaintextHash: 'ph',
      );

      // Keep the provider subscribed (as a visible widget would), so a later
      // invalidateSelf eagerly rebuilds it.
      container.listen(mediaFileProvider(params), (_, _) {});

      final first = await container.read(mediaFileProvider(params).future);
      expect(first, isNull, reason: 'blob not on the relay yet → placeholder');
      expect(downloads.calls, 1);

      // Hydration lands the blob for THIS media id.
      events.add(const MediaAvailableEvent('mfp-invalidate-1'));

      // The listener invalidates the provider, which re-runs getMedia.
      await pumpEventQueue();

      final second = await container.read(mediaFileProvider(params).future);
      expect(second, isNotNull,
          reason: 'a matching MediaAvailableEvent must trigger a re-resolve');
      expect(second, equals(Uint8List.fromList([7, 7, 7])));
      expect(downloads.calls, 2);
    },
  );

  test('an event for a DIFFERENT media id does not invalidate', () async {
    final downloads = _NullThenBytesDownloadManager(missesBefore: 1);
    final events = StreamController<MediaAvailableEvent>.broadcast();
    addTearDown(events.close);

    final container = ProviderContainer(
      overrides: [
        downloadManagerProvider.overrideWithValue(downloads),
        mediaAvailableProvider.overrideWith((ref) => events.stream),
      ],
    );
    addTearDown(container.dispose);

    const params = (
      mediaId: 'mfp-target',
      encryptionKeyB64: 'a2V5',
      ciphertextHash: 'ch',
      plaintextHash: 'ph',
    );
    container.listen(mediaFileProvider(params), (_, _) {});

    await container.read(mediaFileProvider(params).future);
    expect(downloads.calls, 1);

    // Unrelated blob landed — must NOT re-run getMedia for our params.
    events.add(const MediaAvailableEvent('some-other-media'));
    await pumpEventQueue();

    expect(downloads.calls, 1,
        reason: 'only a matching media id should invalidate the provider');
  });
}
