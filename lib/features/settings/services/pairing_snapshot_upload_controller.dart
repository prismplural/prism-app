import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

/// Pair-time snapshot TTL handed to the split ceremony's upload half.
///
/// Matches the pre-split `uploadPairingSnapshot(ttlSecs: 86400)` call.
final BigInt pairingSnapshotTtlSeconds = BigInt.from(86400);

/// Phase of the post-SAS split initiator ceremony.
///
/// The ceremony is three ordered core calls:
/// `verifyInitiatorConfirmationResumable` → `uploadPairingSnapshotResumable` →
/// `completeInitiatorResumableCeremony`. [verifying], [uploading] and
/// [finalizing] map to those three; the rest are terminal.
enum PairingCeremonyPhase {
  /// No run yet.
  idle,

  /// Waiting for and verifying the joiner's confirmation (core-owned wait).
  verifying,

  /// Producing and uploading the encrypted snapshot.
  uploading,

  /// Snapshot published; releasing credentials and waiting for the joiner's
  /// terminal bundle (core-owned wait).
  finalizing,

  /// Credentials released. The caller continues its existing post-pair UX.
  completed,

  /// A step failed. No credentials were released.
  failed,

  /// The ceremony was cancelled. Late completion or errors from the abandoned
  /// run are ignored.
  cancelled,
}

/// Progress snapshot for the upload phase.
///
/// Byte counts come from the app's existing `SnapshotUploadProgress` event
/// stream. [resumableTransfer] is the only signal that may be used to promise
/// slow-link survival: a single-`PUT` downgrade is ordinary pairing behavior.
@immutable
class PairingProgressUpdate {
  const PairingProgressUpdate({
    required this.bytesSent,
    required this.bytesTotal,
    required this.showByteProgress,
    required this.resumableTransfer,
  });

  /// Bytes reported so far, when the relay reported any.
  final int? bytesSent;

  /// Total envelope bytes, when known.
  final int? bytesTotal;

  /// Whether byte counts describe this transfer. False only while no total has
  /// been reported (or after cancellation); a resolved single-`PUT` downgrade
  /// keeps whatever the progress stream already reported.
  final bool showByteProgress;

  /// Whether this transfer is resumable: the ceremony negotiated the pairing
  /// lease and the upload is using (or is expected to use) the resumable
  /// transport.
  final bool resumableTransfer;

  @override
  bool operator ==(Object other) =>
      other is PairingProgressUpdate &&
      other.bytesSent == bytesSent &&
      other.bytesTotal == bytesTotal &&
      other.showByteProgress == showByteProgress &&
      other.resumableTransfer == resumableTransfer;

  @override
  int get hashCode =>
      Object.hash(bytesSent, bytesTotal, showByteProgress, resumableTransfer);
}

/// Coerces a sync-event integer payload (`int`, `BigInt`, `num` or `String`).
int? pairingEventInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is BigInt) return raw.toInt();
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

/// Drives the split initiator ceremony for the setup-device sheet.
///
/// Responsibilities:
///
/// - Enforce the structural ordering: verify → upload → complete. Step 3 is
///   reachable only after step 2 returned successfully **and** while the run is
///   still current, so credentials are never released for a failed, cancelled
///   or superseded upload.
/// - Surface upload progress from the app's existing sync event stream
///   (`SnapshotUploadProgress`) rather than from the upload future.
/// - Add **no** Dart deadline to any of the three core calls. Core owns those
///   waits: a legacy single-`PUT` upload can run to its 300s budget and a
///   lease-aware ceremony can run to its four-hour cap, so any shorter wrapper
///   would preempt core.
/// - Make cancellation immediate. [cancel] bumps a generation token and emits
///   the cancelled phase synchronously, then calls `cancelPairingCeremony`
///   without awaiting the in-flight upload future, which can take up to five
///   minutes to unwind. A late completion or error from the abandoned run is
///   dropped instead of mutating disposed or cancelled UI, and cannot reach
///   step 3.
/// - Keep the PIN lifecycle in the caller's hands. [run] takes an already
///   drained, parent-owned byte buffer so the sheet can capture the PIN
///   synchronously — before any `setState` unmounts the view that owns it — and
///   zero that same buffer in its own `finally` once step 3 has returned. This
///   controller never retains the buffer past the run.
///
/// The controller reads the handle held by the current sheet. `cancel` is
/// handle-independent, which is what keeps the immediate cancel path working
/// during `dispose`.
class PairingSnapshotUploadController {
  PairingSnapshotUploadController({
    required this.handle,
    required PairingCeremonyApi api,
    this.onPhaseChanged,
    this.onProgress,
    this.onUploadResolved,
    this.onUploadFailed,
  }) : _api = api;

  final ffi.PrismSyncHandle handle;
  final PairingCeremonyApi _api;

  /// Phase transitions, delivered in order on the current run only.
  final void Function(PairingCeremonyPhase phase)? onPhaseChanged;

  /// Upload progress / hint updates, delivered on the current run only.
  final void Function(PairingProgressUpdate update)? onProgress;

  /// Called with the upload result once step 2 succeeds, so the caller can
  /// present transport-appropriate messaging.
  final void Function(ffi.ResumableSnapshotUploadResult result)?
  onUploadResolved;

  /// Called when step 2 fails, so the caller can show the upload retry card.
  ///
  /// Carries no error text: FFI/relay messages can include session
  /// identifiers, so the caller renders its own localized copy.
  final void Function()? onUploadFailed;

  /// Monotonic run token. [cancel], [run] and [dispose] advance it, which makes
  /// every in-flight continuation stale.
  int _generation = 0;
  bool _disposed = false;
  bool _runStarted = false;

  PairingCeremonyPhase _phase = PairingCeremonyPhase.idle;

  // UX state. None of this changes which core call is made.
  bool _leaseActive = false;
  bool? _resumableExpected;
  bool? _uploadResumable;
  int? _bytesSent;
  int? _bytesTotal;
  PairingProgressUpdate? _lastUpdate;

  /// Current phase.
  PairingCeremonyPhase get phase => _phase;

  /// Whether a verified ceremony negotiated the pairing lease.
  bool get leaseActive => _leaseActive;

  /// Whether step 2 published the snapshot for the current run.
  bool get uploadPublished => _uploadResumable != null;

  /// Whether the current run was cancelled or the controller was disposed.
  bool get isCancelled => _disposed || _phase == PairingCeremonyPhase.cancelled;

  /// Whether byte progress should be rendered.
  ///
  /// One consistent policy for both transports: as soon as the progress stream
  /// has reported a total, the bar stays determinate for the rest of the run.
  /// Core emits `SnapshotUploadProgress` for whichever transport it picks and
  /// reports a total before the first chunk lands, so a later single-`PUT`
  /// resolution must not tear the determinate bar away and snap it back to
  /// indeterminate. Only [resumableTransfer] gates the slow-link promise.
  bool get showByteProgress => _bytesTotal != null;

  /// Whether slow-link survival may be promised for this run.
  bool get resumableTransfer => _leaseActive && _uploadResumable == true;

  /// Capability-probe hint, or `null` when the probe has not resolved.
  ///
  /// Hint only: it never affects the transfer the app performs or the promise
  /// it shows the user (see [resumableTransfer]).
  bool? get resumableExpectedHint => _resumableExpected;

  /// Runs verify → upload → complete for one ceremony.
  ///
  /// [pinBytes] is **parent-owned and already drained**: the caller must copy the
  /// PIN into a mutable buffer *synchronously*, before any `setState` or `await`,
  /// because the view that owns the source buffer is disposed as soon as the
  /// sheet moves to its confirming step, and its `dispose()` zeroes that buffer.
  /// The parent keeps ownership: it must overwrite/clear the buffer in its own
  /// `finally` after step 3 (or after any error), and this controller never
  /// retains it past the run. [mnemonic] is copied into a zeroable buffer here.
  ///
  /// Returns `true` only when credentials were released. Returns `false` for
  /// failure and for cancellation — including a cancellation that lands while a
  /// step is still in flight, in which case the caller has already moved on.
  Future<bool> run({
    required List<int> pinBytes,
    required String mnemonic,
  }) async {
    if (_disposed) return false;
    final mnemonicBytes = secretUtf8Bytes(mnemonic);
    // Fresh state for this run: a previous attempt (including a cancelled one)
    // must not leak progress, transport or lease hints into the retry.
    _resetRunState();

    final generation = ++_generation;
    _runStarted = true;

    try {
      // Step 1: verify the joiner's confirmation. Core owns the wait.
      _emitPhase(PairingCeremonyPhase.verifying);
      final leaseActive = await _api.verifyInitiatorConfirmationResumable(
        handle: handle,
      );
      if (!_isCurrent(generation)) return false;
      _leaseActive = leaseActive;

      // UX only, and deliberately not awaited: the app never picks the
      // transport from this. Core downgrades to the single PUT by itself.
      unawaited(_probeCapability(generation));

      // Step 2: produce + upload the snapshot. The future is detached so a
      // later cancel never awaits it.
      _emitPhase(PairingCeremonyPhase.uploading);
      final upload = _startUpload();
      ffi.ResumableSnapshotUploadResult result;
      try {
        result = await upload.future;
      } catch (error) {
        // Upload failed: credentials are never released. Report the failure as
        // its own event so the caller can show the upload retry card rather than
        // a generic pairing error.
        if (!_isCurrent(generation)) return false;
        debugPrint(
          '[SYNC] Pairing snapshot upload failed: ${_safeErrorLabel(error)}',
        );
        onUploadFailed?.call();
        _emitPhase(PairingCeremonyPhase.failed);
        return false;
      }
      if (!_isCurrent(generation)) return false;

      _applyUploadResult(generation, result);

      // Step 3: only now, and only for a still-current successful upload.
      _emitPhase(PairingCeremonyPhase.finalizing);
      final completion = await _api.completeInitiatorResumableCeremony(
        handle: handle,
        password: pinBytes,
        mnemonic: mnemonicBytes,
      );
      if (!_isCurrent(generation)) return false;
      if (!completion.completed) {
        debugPrint('[SYNC] Pairing credential release did not complete.');
        _emitPhase(PairingCeremonyPhase.failed);
        return false;
      }

      _leaseActive = completion.leaseActive;
      _emitPhase(PairingCeremonyPhase.completed);
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      debugPrint(
        '[SYNC] Pairing initiator flow failed: ${_safeErrorLabel(error)}',
      );
      _emitPhase(PairingCeremonyPhase.failed);
      return false;
    } finally {
      // The PIN buffer stays parent-owned: the caller zeroes it in its own
      // finally, after step 3 (or after any error on the way there). This
      // controller must not retain it, so only the run-owned mnemonic copy is
      // zeroed here.
      zeroBytesBestEffort(mnemonicBytes);
    }
  }

  /// Cancels the ceremony immediately.
  ///
  /// Emits [PairingCeremonyPhase.cancelled] synchronously so the caller can
  /// drive UI and navigation from it, bumps the generation token so any late
  /// upload completion or error is ignored, and only then issues
  /// `cancelPairingCeremony` — whose future the caller may await, but which this
  /// method never blocks the UI on, and which is deliberately not wrapped in a
  /// Dart deadline.
  Future<void> cancel() {
    if (_disposed) return Future<void>.value();
    _generation++;
    _emitPhase(PairingCeremonyPhase.cancelled);
    return _api.cancelPairingCeremony(handle: handle);
  }

  /// Drops all further callbacks and invalidates any in-flight continuation.
  void dispose() {
    _disposed = true;
    _generation++;
  }

  /// Feed one event from the app's sync event stream.
  ///
  /// Called from the same place the app already polls events. Progress is
  /// clamped monotonic in both directions so a duplicated or slightly reordered
  /// acknowledgement cannot make the bar go backwards.
  void handleSyncEvent(SyncEvent event) {
    if (_disposed || !_runStarted) return;
    switch (event.type) {
      case 'SnapshotUploadProgress':
        final sent = pairingEventInt(event.data['bytes_sent']);
        final total = pairingEventInt(event.data['bytes_total']);
        if (sent == null || total == null) return;
        _bytesSent = _monotonicMax(_bytesSent, sent);
        _bytesTotal = _monotonicMax(_bytesTotal, total);
        _emitProgress();
      case 'SnapshotUploadFailed':
        // Core reports the same failure through the upload future, which is the
        // authoritative path; never surface the relay's raw reason text.
        debugPrint('[SYNC] Relay rejected the pairing snapshot upload.');
    }
  }

  /// Starts the upload and returns a detached completer for it.
  ///
  /// Errors are delivered through the completer (and also observed internally)
  /// so an abandoned run can never produce an unhandled async error after the
  /// UI has gone away.
  Completer<ffi.ResumableSnapshotUploadResult> _startUpload() {
    final upload = Completer<ffi.ResumableSnapshotUploadResult>();
    _api
        .uploadPairingSnapshotResumable(
          handle: handle,
          ttlSecs: pairingSnapshotTtlSeconds,
        )
        .then(
          (result) {
            if (!upload.isCompleted) upload.complete(result);
          },
          onError: (Object error) {
            if (!upload.isCompleted) upload.completeError(error);
          },
        );
    // Observe the completer's terminal states even when the run has been
    // abandoned, so nothing is reported as an unhandled async error.
    upload.future.then((_) {}, onError: (Object _) {});
    return upload;
  }

  /// UX-only capability probe. A failure or a missing route changes nothing:
  /// core still picks the transport and downgrades on its own.
  Future<void> _probeCapability(int generation) async {
    try {
      final info = await _api.snapshotUploadCapability(handle: handle);
      if (!_isCurrent(generation)) return;
      _resumableExpected =
          info.state == ffi.SnapshotUploadCapabilityState.available;
    } catch (error) {
      if (!_isCurrent(generation)) return;
      debugPrint(
        '[SYNC] Snapshot upload capability probe unavailable: '
        '${_safeErrorLabel(error)}',
      );
    }
    _emitProgress();
  }

  void _applyUploadResult(
    int generation,
    ffi.ResumableSnapshotUploadResult result,
  ) {
    // Core owns the transport decision. Never infer the protocol beyond what
    // the result reports.
    final resumable = result.transport == ffi.SnapshotTransportUsed.resumable;
    _uploadResumable = resumable;

    // Terminal byte fields are only defined for the resumable transport. For a
    // single-`PUT` downgrade the result's committed/total bytes are not a
    // meaningful offset, so they are ignored; the streamed
    // `SnapshotUploadProgress` events already collected are the only
    // trustworthy source and they keep driving the determinate bar.
    if (resumable) {
      _bytesSent = _monotonicMax(
        _bytesSent,
        pairingEventInt(result.committedBytes),
      );
      _bytesTotal = _monotonicMax(
        _bytesTotal,
        pairingEventInt(result.totalBytes),
      );
    }
    // A lease that step 1 did not negotiate must never be resurrected by a
    // resumable upload result.
    _leaseActive = result.leaseActive && _leaseActive;

    onUploadResolved?.call(result);
    _emitProgress(generation);
  }

  void _emitPhase(PairingCeremonyPhase phase) {
    _phase = phase;
    onPhaseChanged?.call(phase);
  }

  void _emitProgress([int? generation]) {
    if (_disposed || !_runStarted) return;
    if (generation != null && !_isCurrent(generation)) return;

    // `_resumableExpected` is a capability *hint* only. It never feeds the
    // rendered transfer description: the app must not promise slow-link
    // survival for a transport core has not actually used.
    final update = PairingProgressUpdate(
      bytesSent: _bytesSent,
      bytesTotal: _bytesTotal,
      showByteProgress: showByteProgress,
      resumableTransfer: resumableTransfer,
    );
    if (update == _lastUpdate) return;
    _lastUpdate = update;
    onProgress?.call(update);
  }

  /// Resets everything a previous attempt could have left behind.
  void _resetRunState() {
    _phase = PairingCeremonyPhase.idle;
    _leaseActive = false;
    _resumableExpected = null;
    _uploadResumable = null;
    _bytesSent = null;
    _bytesTotal = null;
    _lastUpdate = null;
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  static int? _monotonicMax(int? previous, int? next) {
    if (next == null) return previous;
    if (previous == null) return next;
    return next > previous ? next : previous;
  }

  /// Never logs raw error text: FFI/relay messages can carry session
  /// identifiers. Only the error's type name is emitted.
  static String _safeErrorLabel(Object error) =>
      error is Error ? error.runtimeType.toString() : 'operation_failed';
}
