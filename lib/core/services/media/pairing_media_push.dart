import 'dart:typed_data';

/// A blob the inviter could re-supply to a freshly-paired device: its relay
/// `mediaId` and the ciphertext hash the upload must present.
class PairingMediaRef {
  const PairingMediaRef({required this.mediaId, required this.contentHash});
  final String mediaId;
  final String contentHash;
}

typedef PairingCandidatesFn = Future<List<PairingMediaRef>> Function();
typedef PairingHoldsCiphertextFn = Future<Uint8List?> Function(String mediaId);
typedef PairingBatchExistsFn = Future<List<String>> Function(List<String> ids);
typedef PairingUploadFn =
    Future<bool> Function(String mediaId, String contentHash, Uint8List data);

/// The pairing push **optimistic pairing push**. When a new device pairs in, the inviting
/// device proactively re-uploads (short-TTL, on the relay's dedicated
/// pairing-push lane) the blobs the joiner will reference — so the joiner can
/// download them straight away instead of discovering each one missing and
/// waiting on the media heal round-trip.
///
/// It only pushes blobs that are (a) referenced, (b) NOT already on the relay
/// (a batch-exists gate — the inviter's own fresh sends are already there at
/// full retention and are skipped), and (c) actually held in the inviter's
/// cache byte-exact (no decrypt/re-encrypt). Candidates are ordered
/// thumbnail-first so the joiner gets crisp previews of everything quickly,
/// then full blobs; the whole push is bounded by [maxBlobs] (and, server-side,
/// by the pairing-push rate lane + the ephemeral byte ceiling — a rejected
/// upload just means the joiner heals that blob on demand later).
class PairingMediaPush {
  PairingMediaPush({
    required this.candidates,
    required this.holdsCiphertext,
    required this.batchExists,
    required this.upload,
    this.maxBlobs = 200,
    this.batchChunkSize = 1024,
  });

  /// Referenced blobs to consider, already ordered by push priority
  /// (thumbnail-first, newest-first). Deduped by mediaId inside [run].
  final PairingCandidatesFn candidates;

  /// The inviter's byte-exact cached ciphertext for a blob, or null if it
  /// doesn't hold it (so it can't re-supply it).
  final PairingHoldsCiphertextFn holdsCiphertext;

  /// batch-exists — the subset of ids the relay already serves. Throwing
  /// (no handle / old relay) means "can't confirm", and that chunk is skipped
  /// rather than blind-pushed.
  final PairingBatchExistsFn batchExists;

  /// Upload one held blob on the pairing-push lane. Returns whether it
  /// committed; never throws into [run].
  final PairingUploadFn upload;

  /// Upper bound on blobs pushed per pairing event (a client-side sanity cap;
  /// the relay lane + ceiling are the real backpressure).
  final int maxBlobs;

  /// Max ids per batch-exists call (batch-exists caps at 1024).
  final int batchChunkSize;

  /// Run the push. Best-effort and self-contained: returns the number of blobs
  /// committed. Never throws.
  Future<int> run() async {
    final List<PairingMediaRef> refs;
    try {
      refs = await candidates();
    } catch (_) {
      return 0;
    }

    // Dedupe by mediaId, preserving priority order, and cap. The cap bounds
    // *candidates considered* (pre batch-exists), so the number actually pushed
    // is ≤ maxBlobs — the conservative direction (never exceeds the cap).
    final byId = <String, PairingMediaRef>{};
    for (final r in refs) {
      if (r.mediaId.isEmpty || r.contentHash.isEmpty) continue;
      byId.putIfAbsent(r.mediaId, () => r);
      if (byId.length >= maxBlobs) break;
    }
    if (byId.isEmpty) return 0;

    // Gate on batch-exists per chunk; only confirmed-absent ids are pushed.
    final ids = byId.keys.toList();
    final toPush = <PairingMediaRef>[];
    for (var i = 0; i < ids.length; i += batchChunkSize) {
      final chunk = ids.sublist(
        i,
        (i + batchChunkSize) > ids.length ? ids.length : i + batchChunkSize,
      );
      final List<String> present;
      try {
        present = await batchExists(chunk);
      } catch (_) {
        continue; // can't confirm → don't blind-push this chunk
      }
      final presentSet = present.toSet();
      for (final id in chunk) {
        if (!presentSet.contains(id)) toPush.add(byId[id]!);
      }
    }

    var pushed = 0;
    for (final ref in toPush) {
      final ciphertext = await holdsCiphertext(ref.mediaId);
      if (ciphertext == null) continue; // not held — can't re-supply it
      try {
        if (await upload(ref.mediaId, ref.contentHash, ciphertext)) pushed++;
      } catch (_) {
        // Transient upload failure (rate-limited / ceiling / transport): the
        // joiner just heals this blob on demand later.
      }
    }
    return pushed;
  }
}
