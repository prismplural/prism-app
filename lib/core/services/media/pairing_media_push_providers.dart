import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/media/media_heal_providers.dart'
    show kResupplyTtlSecs;
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/media/pairing_media_push.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';

/// Builds the inviter's pairing-push candidate list from the referenced media:
/// every attachment's thumbnail first (small → fast, crisp previews of the
/// whole history), then every full blob. Deduping + the cap happen in
/// [PairingMediaPush.run].
Future<List<PairingMediaRef>> _pairingCandidates(Ref ref) async {
  final attachments = await ref.read(databaseProvider).mediaAttachmentsDao.getAll();
  final thumbs = <PairingMediaRef>[];
  final fulls = <PairingMediaRef>[];
  for (final a in attachments) {
    if (a.thumbnailMediaId.isNotEmpty && a.thumbnailContentHash.isNotEmpty) {
      thumbs.add(
        PairingMediaRef(mediaId: a.thumbnailMediaId, contentHash: a.thumbnailContentHash),
      );
    }
    if (a.mediaId.isNotEmpty && a.contentHash.isNotEmpty) {
      fulls.add(PairingMediaRef(mediaId: a.mediaId, contentHash: a.contentHash));
    }
  }
  return [...thumbs, ...fulls];
}

/// The optimistic pairing push, wired to the live cache + relay. Re-uploads
/// the inviter's held, referenced, relay-absent blobs on the pairing-push lane
/// so a freshly-paired device finds them present instead of healing each.
final pairingMediaPushProvider = Provider<PairingMediaPush>((ref) {
  final downloadManager = ref.watch(downloadManagerProvider);
  return PairingMediaPush(
    candidates: () => _pairingCandidates(ref),
    holdsCiphertext: downloadManager.readCachedCiphertext,
    batchExists: (ids) {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        throw StateError('sync handle unavailable for batch-exists');
      }
      return ffi.mediaExists(handle: handle, mediaIds: ids);
    },
    upload: (mediaId, contentHash, data) async {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) return false;
      final outcome = await ffi.uploadMedia(
        handle: handle,
        mediaId: mediaId,
        contentHash: contentHash,
        data: data,
        ttlSecs: BigInt.from(kResupplyTtlSecs),
        pairingPush: true,
      );
      return outcome.committed;
    },
  );
});

/// Fire-and-forget the optimistic pairing push after a device pairs in.
/// Best-effort: never throws into the caller (the pairing ceremony has already
/// succeeded; a failed push just falls back to on-demand media heal).
Future<void> runPairingMediaPush(WidgetRef ref) async {
  try {
    await ref.read(pairingMediaPushProvider).run();
  } catch (_) {}
}
