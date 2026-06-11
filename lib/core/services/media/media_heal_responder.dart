import 'dart:math';

import 'package:prism_plurality/core/services/media/media_heal_requester.dart'
    show BatchExistsFn;

/// Outcome of a short-TTL re-supply upload (mirrors the relay's
/// `MediaUploadOutcome`): only a `committed` upload may announce `media_uploaded`
/// — an `inProgress` (HTTP 202: another responder holds the reserve) must back
/// off silently, and a `failed` upload announces nothing.
enum ReUploadResult { committed, inProgress, failed }

/// True if this device holds the blob's encrypted bytes locally (cached `.enc`)
/// and can therefore re-supply it.
typedef HoldsBlobFn = Future<bool> Function(String mediaId);

/// Re-upload the held blob to the relay with the short re-supply TTL, returning
/// the upload outcome. Throws only on a transient failure the caller should
/// swallow.
typedef ReUploadFn = Future<ReUploadResult> Function(String mediaId);

/// Broadcast a `media_uploaded` for `mediaId` over the ephemeral lane.
typedef SendMediaUploadedFn = Future<void> Function(String mediaId);

/// A bounded random delay (default 0–8 s) before responding, so concurrent
/// holders don't stampede the same blob.
typedef JitterFn = Future<void> Function();

/// The demand-driven heal's **responder** (media heal).
///
/// On a peer's `media_request{X}`, a device that holds `X.enc` waits a random
/// jitter, re-checks batch-exists (someone else — or the relay — may already
/// hold it), and if still absent re-uploads `X` with a short TTL via the
/// re-supply class, then announces `media_uploaded{X}` so requesters can fetch
/// it. The idempotent upsert makes concurrent responders safe: the first
/// commits and announces; the rest get `inProgress` (202) and stay silent.
///
/// Every gate is fail-safe: not holding the blob, the relay already holding it,
/// a batch-exists/transient error, or a non-committed upload all end in a quiet
/// no-op — never a blind re-upload storm.
class MediaHealResponder {
  MediaHealResponder({
    required this.holdsBlob,
    required this.batchExists,
    required this.reUpload,
    required this.sendMediaUploaded,
    JitterFn? jitter,
    Duration maxJitter = const Duration(seconds: 8),
    this.maxReUploadsPerWindow = 20,
    this.rateWindow = const Duration(minutes: 1),
    int Function()? clockMs,
    Random? random,
  })  : _jitter = jitter ?? _defaultJitter(maxJitter, random ?? Random()),
        _clockMs = clockMs ?? _systemClockMs;

  final HoldsBlobFn holdsBlob;
  final BatchExistsFn batchExists;
  final ReUploadFn reUpload;
  final SendMediaUploadedFn sendMediaUploaded;
  final JitterFn _jitter;

  /// Self-rate-limit: at most this many re-supply uploads per [rateWindow]
  /// (spec "Abuse resistance": responders self-rate-limit so a request flood
  /// can't make this device storm the relay). Independent of the relay's
  /// re-supply limiter.
  final int maxReUploadsPerWindow;
  final Duration rateWindow;
  final int Function() _clockMs;
  final List<int> _recentUploads = [];

  static int _systemClockMs() => DateTime.now().millisecondsSinceEpoch;

  bool _selfRateLimited(int now) {
    final cutoff = now - rateWindow.inMilliseconds;
    _recentUploads.removeWhere((t) => t <= cutoff);
    return _recentUploads.length >= maxReUploadsPerWindow;
  }

  static JitterFn _defaultJitter(Duration maxJitter, Random random) {
    return () => Future<void>.delayed(
      Duration(milliseconds: random.nextInt(maxJitter.inMilliseconds + 1)),
    );
  }

  /// Handle a peer's request for `mediaId`. Safe to call for any request — it
  /// returns immediately if this device can't help.
  Future<void> onMediaRequest(String mediaId) async {
    if (!await holdsBlob(mediaId)) return; // we don't hold it → can't supply

    await _jitter();

    final List<String> present;
    try {
      present = await batchExists([mediaId]);
    } catch (_) {
      return; // transient / feature-absent → skip; the requester re-issues
    }
    if (present.contains(mediaId)) return; // already re-supplied or relay holds it

    // Self-rate-limit: cap re-supply uploads per window so a request flood
    // can't make this device storm the relay. Gate before the upload…
    final now = _clockMs();
    if (_selfRateLimited(now)) return;

    final ReUploadResult result;
    try {
      result = await reUpload(mediaId);
    } catch (_) {
      return; // transient upload failure → skip
    }

    // …but only spend a slot when an upload actually reached the relay
    // (committed or in-progress). A `failed` result includes pre-network
    // misses — a raced-out-of-cache blob, an unresolved content hash — which
    // must NOT consume the window, or a burst of un-uploadable requests would
    // starve legitimate re-supplies.
    if (result == ReUploadResult.failed) return;
    _recentUploads.add(now);

    // Only a committed upload announces. inProgress (another responder is
    // mid-upload) stays silent.
    if (result == ReUploadResult.committed) {
      await sendMediaUploaded(mediaId);
    }
  }
}
