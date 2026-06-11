import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';

/// Returns the subset of `mediaIds` the relay currently holds and can serve
/// (the batch-exists query). MUST throw against an old relay without the
/// endpoint (404/405) so the caller can treat "feature absent" as a no-op
/// rather than "all blobs absent".
typedef BatchExistsFn = Future<List<String>> Function(List<String> mediaIds);

/// Broadcasts a `media_request` for `mediaId` over the ephemeral lane.
typedef SendMediaRequestFn =
    Future<void> Function(String mediaId, {required bool forceRepair});

/// The demand-driven heal's **requester** (media heal).
///
/// When a referenced blob misses the local cache and the relay confirms it
/// absent, the requester records it in the missing-media set and broadcasts a
/// `media_request` so a peer that holds it re-supplies it (short-TTL) via the
/// relay. A bounded [runCadence] re-checks the whole set on resume / each sync
/// pull — one coalesced (chunked) batch-exists, dropping any that healed and
/// re-requesting the still-absent due ones with a per-media cooldown + backoff,
/// promoting long-unavailable entries to terminal.
///
/// The heal gate is **batch-exists, not the download error alone**: a relay/
/// proxy that 5xxs (rather than 404s) for a missing blob can't silently defeat
/// it, and a present result never triggers a request. A batch-exists call that
/// fails (old relay / transient) is always a no-op — never a request storm, and
/// never "all blobs absent".
class MediaHealRequester {
  MediaHealRequester({
    required this.dao,
    required this.batchExists,
    required this.sendMediaRequest,
    int Function()? clockMs,
    this.profileCooldown = const Duration(minutes: 2),
    this.chatCooldown = const Duration(minutes: 5),
    this.maxCooldown = const Duration(hours: 1),
    this.terminalAfter = const Duration(days: 14),
    this.batchChunkSize = 1024,
  }) : _clockMs = clockMs ?? _systemClockMs;

  final MissingMediaDao dao;
  final BatchExistsFn batchExists;
  final SendMediaRequestFn sendMediaRequest;
  final int Function() _clockMs;

  /// Base cooldown for profile/member images (tighter — they heal first).
  final Duration profileCooldown;

  /// Base cooldown for chat-history images.
  final Duration chatCooldown;

  /// Upper bound the exponential backoff is clamped to.
  final Duration maxCooldown;

  /// A blob unavailable for longer than this becomes terminal (revivable).
  final Duration terminalAfter;

  /// Max media ids per batch-exists call (batch-exists caps at 1024).
  final int batchChunkSize;

  static int _systemClockMs() => DateTime.now().millisecondsSinceEpoch;

  /// Called when a referenced blob `mediaId` missed the local cache and the
  /// download reported it absent (`notFound`) or persistently failed. Confirms
  /// via batch-exists; if the relay holds it, a no-op (a download retry should
  /// succeed). If confirmed absent, records it missing and — when due —
  /// broadcasts a request immediately. A repeat call while the entry is still in
  /// cooldown does NOT re-request (the cadence handles that), so repeated views
  /// of a missing image can't storm the lane.
  Future<void> onReferencedAbsent(
    String mediaId, {
    required int priority,
    bool fromNotFound = false,
  }) async {
    final now = _clockMs();
    if (!fromNotFound) {
      // Transient give-up: gate on batch-exists — if the relay still holds it
      // (or we can't confirm), a download retry should succeed, so don't
      // request.
      final List<String> present;
      try {
        present = await batchExists([mediaId]);
      } catch (_) {
        return; // feature absent / transient → no-op, never a storm
      }
      if (present.contains(mediaId))
        return; // relay holds it; not really missing
    }
    // Else: a relay-confirmed 404. Even a "servable" batch-exists row whose
    // file is missing — the committed-but-fileless repair case — can't be fixed
    // by a download retry, so request a re-supply anyway: a holder re-uploads
    // and the relay's repair path restores the file. Cooldown-gated below, so
    // this still can't storm the lane.

    await dao.markMissing(
      mediaId: mediaId,
      priority: priority,
      nowMs: now,
      forceRepair: fromNotFound,
    );
    final entry = await dao.getById(mediaId);
    if (entry == null || !MissingMediaDao.isPendingState(entry.state)) return;
    if (entry.nextEligibleAt > now)
      return; // already in cooldown; cadence covers it
    await _request(
      mediaId: entry.mediaId,
      attempts: entry.attempts,
      priority: entry.priority,
      now: now,
      forceRepair: MissingMediaDao.isRepairState(entry.state),
    );
  }

  /// The blob for [mediaId] is now present locally — drop it from the
  /// missing-media set (idempotent; a no-op when nothing is tracked). Called on
  /// an on-view load that succeeds, which (unlike the hydrator) emits no
  /// `MediaAvailableEvent`, so without this an entry created by a prior on-view
  /// miss would linger and re-broadcast after each re-supply lapse.
  Future<void> markResolved(String mediaId) => dao.remove(mediaId);

  /// The bounded cadence (run on app resume / each sync-pull). Re-checks the
  /// whole pending set with one coalesced (chunked) batch-exists, drops any that
  /// healed, then for the still-absent due entries either re-requests (with
  /// backoff) or — past the terminal window — marks them terminal.
  ///
  /// Returns the media ids found back on the relay (removed from the set) so the
  /// caller can re-download them (heal-completion). Empty on a no-op tick
  /// (nothing pending, or a batch-exists failure).
  Future<List<String>> runCadence() async {
    final now = _clockMs();
    final pending = await dao.pendingMediaIds();
    if (pending.isEmpty) return const [];

    final present = <String>{};
    try {
      for (var i = 0; i < pending.length; i += batchChunkSize) {
        final end = (i + batchChunkSize < pending.length)
            ? i + batchChunkSize
            : pending.length;
        present.addAll(await batchExists(pending.sublist(i, end)));
      }
    } catch (_) {
      return const []; // feature absent / transient → no-op (no drop, no request)
    }

    // Healed (back on the relay) → return for re-download, but do NOT remove
    // the set entry here: the short-TTL re-supply can expire before the
    // re-download lands, and removing + re-adding would reset the entry's
    // terminal clock and backoff (a flapping blob would re-request at the base
    // cooldown forever). The entry is removed only once the blob actually
    // caches — the reactor drops it on a MediaAvailableEvent. A re-download that
    // fails finds the entry still present, so `markMissing` updates it in place
    // (clock/attempts preserved).
    final healed = <String>[];
    for (final id in pending) {
      if (present.contains(id)) {
        healed.add(id);
      }
    }

    // Still-absent + due → request with backoff, or terminal past the window.
    final terminalMs = terminalAfter.inMilliseconds;
    for (final d in await dao.dueForRequest(now)) {
      if (present.contains(d.mediaId)) continue; // already removed
      if (now - d.firstMissingAt > terminalMs) {
        await dao.markTerminal(d.mediaId);
      } else {
        await _request(
          mediaId: d.mediaId,
          attempts: d.attempts,
          priority: d.priority,
          now: now,
          forceRepair: d.forceRepair,
        );
      }
    }
    return healed;
  }

  Future<void> _request({
    required String mediaId,
    required int attempts,
    required int priority,
    required int now,
    required bool forceRepair,
  }) async {
    // A send failure (handle flipped to null, old relay lacking ephemeral lane) must not
    // throw out of here (it's `unawaited`d) and must still arm the cooldown —
    // otherwise the entry stays immediately-due and re-fires every tick,
    // bypassing the per-media bound. Arm backoff regardless; the cadence retries
    // the send next window.
    try {
      await sendMediaRequest(mediaId, forceRepair: forceRepair);
    } catch (_) {}
    final nextAttempts = attempts + 1;
    await dao.recordRequested(
      mediaId: mediaId,
      attempts: nextAttempts,
      nextEligibleAtMs: now + _backoffMs(nextAttempts, priority),
      nowMs: now,
    );
  }

  /// Exponential backoff from the per-priority base cooldown, clamped to
  /// [maxCooldown]. `attempts` is the new attempt count (1 ⇒ one base cooldown).
  int _backoffMs(int attempts, int priority) {
    final base = priority == MissingMediaDao.priorityProfile
        ? profileCooldown.inMilliseconds
        : chatCooldown.inMilliseconds;
    final shift = (attempts - 1).clamp(0, 20);
    final ms = base * (1 << shift);
    final cap = maxCooldown.inMilliseconds;
    return ms < cap ? ms : cap;
  }
}
