import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/pairing_sas_display.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum PairingStep {
  // User is ready to request admission from an existing device.
  enterUrl,
  // Joiner's rendezvous QR is displayed, waiting for initiator to scan
  showingRequest,
  // Waiting for initiator to scan QR and derive SAS
  waitingForSas,
  // Displaying SAS words for user verification
  showingSas,
  // User enters the sync PIN
  enterPin,
  // Connecting to the relay / performing the join
  connecting,
  // Successfully joined
  success,
  // An error occurred
  error,
  // Snapshot bootstrap failed after successful ceremony; the joiner is
  // registered on the relay and can retry without re-running the ceremony.
  // Offers Retry + Cancel (deregister) actions.
  snapshotFailure,
}

/// Classifies a [PairingStep.error] so the UI can offer error-specific
/// recovery instead of a blanket "Try Again".
enum PairingErrorKind {
  generic,

  /// Leftover encrypted `prism_sync.db` from a previous install couldn't be
  /// opened with the new pairing key. Recoverable by erasing the stale DB.
  staleSyncDatabase,

  /// The [staleSyncDatabase] erase recovery itself failed (e.g. locked file on
  /// Windows). Distinct so the UI stops re-offering Erase.
  staleSyncEraseFailed,
}

/// Substring of the Rust FFI error (prism-sync-ffi `api.rs`) for an existing
/// encrypted sync DB that won't open. Substring, not equality: the FFI appends
/// the sqlite detail and the message may be wrapped before reaching Dart.
const String kStaleSyncDatabaseErrorMarker =
    'existing sync database could not be opened with the configured '
    'encryption key';

/// Internal sentinel placed in [PairingState.errorMessage] when the erase
/// recovery fails; the UI maps it to a localized message.
const String kStaleSyncDatabaseEraseFailedMarker =
    'prism.pairing.stale_sync_db_erase_failed';

/// Classify a raw pairing error message into a [PairingErrorKind].
PairingErrorKind classifyPairingError(String? errorMessage) {
  if (errorMessage == null) {
    return PairingErrorKind.generic;
  }
  if (errorMessage == kStaleSyncDatabaseEraseFailedMarker) {
    return PairingErrorKind.staleSyncEraseFailed;
  }
  if (errorMessage.contains(kStaleSyncDatabaseErrorMarker)) {
    return PairingErrorKind.staleSyncDatabase;
  }
  return PairingErrorKind.generic;
}

class PairingState {
  final PairingStep step;
  final String? errorMessage;
  final String? errorCode;
  final SyncCounts? counts;

  /// QR payload bytes for the joiner's rendezvous token (joiner-initiated flow).
  final List<int>? requestQrPayload;

  /// The joiner's device ID from startJoinerCeremony.
  final String? requestDeviceId;

  /// SAS verification words displayed during relay-based pairing.
  final List<String>? sasWords;

  /// When true, the initial data sync timed out and some data may still be
  /// arriving in the background. The pairing itself succeeded, but the user
  /// should be informed that not all data may be visible yet.
  final bool syncIncomplete;

  const PairingState({
    this.step = PairingStep.enterUrl,
    this.errorMessage,
    this.errorCode,
    this.counts,
    this.requestQrPayload,
    this.requestDeviceId,
    this.sasWords,
    this.syncIncomplete = false,
  });

  /// Derived on demand from [errorMessage]; only meaningful when [step] is
  /// [PairingStep.error].
  PairingErrorKind get errorKind => classifyPairingError(errorMessage);

  PairingState copyWith({
    PairingStep? step,
    Object? errorMessage = _sentinel,
    Object? errorCode = _sentinel,
    Object? counts = _sentinel,
    Object? requestQrPayload = _sentinel,
    Object? requestDeviceId = _sentinel,
    Object? sasWords = _sentinel,
    bool? syncIncomplete,
  }) {
    return PairingState(
      step: step ?? this.step,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
      errorCode: errorCode == _sentinel ? this.errorCode : errorCode as String?,
      counts: counts == _sentinel ? this.counts : counts as SyncCounts?,
      requestQrPayload: requestQrPayload == _sentinel
          ? this.requestQrPayload
          : requestQrPayload as List<int>?,
      requestDeviceId: requestDeviceId == _sentinel
          ? this.requestDeviceId
          : requestDeviceId as String?,
      sasWords: sasWords == _sentinel
          ? this.sasWords
          : sasWords as List<String>?,
      syncIncomplete: syncIncomplete ?? this.syncIncomplete,
    );
  }
}

class SyncCounts {
  final int members;
  final int frontingSessions;
  final int conversations;
  final int messages;
  final int habits;

  const SyncCounts({
    this.members = 0,
    this.frontingSessions = 0,
    this.conversations = 0,
    this.messages = 0,
    this.habits = 0,
  });
}

const _sentinel = Object();
const _epochVerificationFailureCodes = {'epoch_mismatch', 'epoch_key_mismatch'};

bool _isEpochVerificationFailure(PrismSyncStructuredError? error) {
  final code = error?.code;
  return code != null && _epochVerificationFailureCodes.contains(code);
}

String _epochVerificationFailureMessage({required bool credentialsDurable}) {
  if (credentialsDurable) {
    return 'Pairing cannot be safely completed because this device could not '
        'verify the latest sync epoch. Cancel and re-pair this device from an '
        'existing device.';
  }
  return 'Pairing cannot be safely completed because this device could not '
      'verify the latest sync epoch. Please start pairing again.';
}

/// Whether the pairing snapshot ACK-delete may fire.
///
/// The first condition gates the ACK on the post-bootstrap consumer-delivery
/// drain having emptied the journal — never ACK (and let the relay discard the
/// snapshot) until every snapshot row is durably in Drift, so a crash between
/// the Rust import-commit and the Dart apply re-derives losslessly.
///
/// The catch-up-success condition is a CONJUNCTION, NOT a replacement: the
/// joiner must also have caught up past the snapshot (pulled and applied the
/// tail the initiator pushed after cutting the snapshot) before the relay is
/// allowed to discard its only bootstrap source. If catch-up failed or timed
/// out, the snapshot stays on the relay (its TTL covers cleanup) and a one-shot
/// retry re-runs catch-up + ACK on the next successful syncNow.
///
/// `catchUpSucceeded` defaults to `true` so call sites that only reason about
/// the journal-drain dimension (the journal-drain wiring tests) stay meaningful.
bool shouldAckSnapshotApplied({
  required bool journalDrained,
  bool catchUpSucceeded = true,
}) {
  return journalDrained && catchUpSucceeded;
}

@visibleForTesting
typedef TakeUndeliveredChangesFn =
    Future<String> Function({
      required ffi.PrismSyncHandle handle,
      required int limit,
    });

@visibleForTesting
typedef AckConsumerDeliveriesFn =
    Future<void> Function({
      required ffi.PrismSyncHandle handle,
      required int upToId,
    });

/// Clears duplicate bootstrap journal rows after strict snapshot apply commits.
@visibleForTesting
Future<int> ackBootstrapConsumerDeliveryJournal({
  required ffi.PrismSyncHandle handle,
  TakeUndeliveredChangesFn? take,
  AckConsumerDeliveriesFn? ack,
  int chunkSize = 1000,
  int maxChunks = 10000,
}) async {
  final takeFn = take ?? ffi.takeUndeliveredChanges;
  final ackFn = ack ?? ffi.ackConsumerDeliveries;

  for (var chunksAcked = 0; chunksAcked < maxChunks; chunksAcked++) {
    final raw = await takeFn(handle: handle, limit: chunkSize);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final deliveries = (decoded['deliveries'] as List?) ?? const [];
    final maxId = (decoded['max_id'] as num?)?.toInt() ?? 0;
    if (deliveries.isEmpty || maxId <= 0) {
      return chunksAcked;
    }
    // Strict snapshot apply already committed these rows.
    await ackFn(handle: handle, upToId: maxId);
  }

  throw StateError(
    'Bootstrap consumer-delivery journal did not empty after $maxChunks chunks',
  );
}

class DevicePairingNotifier extends Notifier<PairingState> {
  /// Monotonically increasing generation counter. Each new pairing attempt
  /// increments the counter and captures the value; async continuations bail
  /// out if the counter has moved on (i.e. a cancel or a new attempt started).
  int _generation = 0;

  /// PIN to store as app lock PIN after successful pairing. Set by
  /// [completeJoinerWithPin] so that [_bootstrapAfterJoin] can persist it
  /// once all credentials are in place.
  String? _pendingPin;

  /// Relay URL used for the current pairing attempt. Captured up front so
  /// fresh-install onboarding can pair against a custom relay before any
  /// sync settings exist in platform storage.
  String? _pairingRelayUrl;

  /// Set once the post-bootstrap consumer-delivery drain has emptied the
  /// journal. The pairing snapshot ACK-delete gates on this drain having
  /// completed, in CONJUNCTION with the catch-up-success condition. Reset at the
  /// start of each snapshot-bootstrap attempt.
  bool _bootstrapJournalDrained = false;

  /// Live subscription for the one-shot pending-snapshot-ACK retry. When
  /// the initial post-bootstrap catch-up fails, the relay keeps the snapshot
  /// (TTL covers cleanup) and this listener re-runs catch-up + ACK on the next
  /// successful syncNow, then closes itself. Non-null only while a retry is
  /// armed; cleared on fire, on a new pairing attempt, and on reset.
  ProviderSubscription<AsyncValue<SyncEvent>>? _pendingSnapshotAckRetrySub;

  /// Guards re-entrancy while the armed retry is mid-flight so overlapping
  /// `SyncCompleted` events can't launch the catch-up + ACK twice.
  bool _pendingSnapshotAckRetryRunning = false;

  /// Handle backing the currently active relay pairing ceremony. This can be
  /// available before prismSyncHandleProvider has published its AsyncValue.
  ffi.PrismSyncHandle? _activeCeremonyHandle;

  /// Test-only override for [drainRustStore]. When non-null, the notifier
  /// invokes this in place of the real top-level function. Used by unit
  /// tests to assert ordering between credential persistence and the
  /// `ceremonyCompleted` flag without standing up a real FFI handle +
  /// platform keychain. Always reset to `null` in test teardown.
  @visibleForTesting
  static Future<void> Function(ffi.PrismSyncHandle handle)?
  drainRustStoreOverride;

  /// Test-only override for [drainRustStoreWithSnapshotRollback]. Mirrors
  /// [drainRustStoreOverride] but captures the caller-owned snapshot so
  /// joiner-ceremony tests can assert what was passed in. Falls back to
  /// [drainRustStoreOverride] if only the legacy override is wired.
  @visibleForTesting
  static Future<void> Function(
    ffi.PrismSyncHandle handle, {
    required Map<String, String> rollbackSnapshot,
  })?
  drainRustStoreWithSnapshotRollbackOverride;

  Future<void> _drainRustStore(ffi.PrismSyncHandle handle) {
    final override = drainRustStoreOverride;
    if (override != null) return override(handle);
    return drainRustStore(handle);
  }

  Future<void> _drainRustStoreWithSnapshot(
    ffi.PrismSyncHandle handle, {
    required Map<String, String> rollbackSnapshot,
  }) {
    final snapshotOverride = drainRustStoreWithSnapshotRollbackOverride;
    if (snapshotOverride != null) {
      return snapshotOverride(handle, rollbackSnapshot: rollbackSnapshot);
    }
    // Fall back to the legacy override if a test only wired the no-snapshot
    // seam — it's still useful for ordering tests that don't care about
    // rollback semantics.
    final legacyOverride = drainRustStoreOverride;
    if (legacyOverride != null) return legacyOverride(handle);
    return drainRustStoreWithSnapshotRollback(
      handle,
      rollbackSnapshot: rollbackSnapshot,
    );
  }

  /// Snapshot the `prism_sync.*` namespace minus the protected DB-key
  /// slots. Used by the joiner-ceremony drain to capture an authoritative
  /// pre-state so a partial keychain mirror after `completeJoinerCeremony`
  /// can be rolled back exactly.
  ///
  /// Returns `null` if the underlying keychain scan throws — callers MUST
  /// treat that as "I don't know what's in the keychain" and fall back to
  /// the non-rollback drain path. Returning `{}` here would let a
  /// subsequent rollback delete real pre-existing entries thinking they
  /// were never there.
  Future<Map<String, String>?> _snapshotPrismSyncKeychain() {
    return snapshotPrismSyncKeychain();
  }

  @override
  PairingState build() {
    _generation++;
    return const PairingState();
  }

  void reset() {
    final shouldCancelCeremony = _shouldCancelActiveCeremony(state);
    final activeCeremonyHandle = _activeCeremonyHandle;
    _generation++;
    if (shouldCancelCeremony) {
      unawaited(_cancelActiveCeremony(activeCeremonyHandle));
    }
    _disposePendingSnapshotAckRetry();
    _pendingPin = null;
    _pairingRelayUrl = null;
    _activeCeremonyHandle = null;
    ref.read(syncSetupProgressProvider.notifier).reset();
    state = const PairingState();
  }

  /// Recovery for [PairingErrorKind.staleSyncDatabase]: delete only the stale
  /// `prism_sync.db` (+ sidecars) and restart pairing. Deliberately narrow —
  /// never touches `prism.db`, the keychain, or prefs (unlike the broader
  /// sync-reset / full-reset helpers).
  ///
  /// No-op unless currently in the stale-sync-DB error state. If the main DB
  /// can't be removed (e.g. locked on Windows) it surfaces a
  /// [PairingErrorKind.staleSyncEraseFailed] error rather than resetting back
  /// into the same dead-end.
  Future<void> eraseStaleSyncDatabaseAndRetry() async {
    if (state.step != PairingStep.error ||
        state.errorKind != PairingErrorKind.staleSyncDatabase) {
      return;
    }

    // Dispose any handle holding the stale DB open before unlinking.
    // Best-effort: a failed dispose must not block the erase.
    try {
      _activeCeremonyHandle?.dispose();
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Disposing ceremony handle before stale sync DB erase failed '
        '(non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
    _activeCeremonyHandle = null;
    try {
      ref.read(prismSyncHandleProvider).value?.dispose();
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Disposing active sync handle before stale sync DB erase failed '
        '(non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    try {
      await deleteStaleSyncDatabaseFiles();
    } catch (e, st) {
      // The stale DB is still on disk — resetting would loop the user
      // straight back into the same dead-end with no indication of failure.
      // Surface an actionable error instead.
      ErrorReportingService.instance.report(
        'Erasing stale sync DB during pairing recovery failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: kStaleSyncDatabaseEraseFailedMarker,
        errorCode: null,
      );
      return;
    }

    // Back to the join prompt with a clean slate.
    reset();
  }

  /// Delete `prism_sync.db` and its sidecars from the app data dir.
  /// The main DB is load-bearing: if it can't be removed (or lingers after
  /// delete), this throws so the caller won't loop the user back into the
  /// dead-end. Sidecars are best-effort; missing files are fine.
  /// `@visibleForTesting` for the never-touches-`prism.db` guarantee.
  @visibleForTesting
  Future<void> deleteStaleSyncDatabaseFiles({Directory? directory}) async {
    final dir = directory ?? await getAppDataDir();
    final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);

    final mainFile = File(dbPath);
    if (await mainFile.exists()) {
      await mainFile.delete();
      // A delete can "succeed" against a handle that keeps the file alive;
      // re-check so a lingering file surfaces as failure, not a silent no-op.
      if (await mainFile.exists()) {
        throw FileSystemException(
          'Stale sync database still present after delete',
          dbPath,
        );
      }
    }

    // Sidecars — best-effort. A locked/absent sidecar must not abort the
    // erase once the main DB is gone.
    for (final suffix in const <String>['-wal', '-shm', '-journal']) {
      final file = File('$dbPath$suffix');
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'Failed to delete stale sync DB sidecar $dbPath$suffix '
          '(non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
    }
  }

  /// Cancel any in-flight pairing attempt. Safe to call from UI when the
  /// user navigates away (e.g. leaveSyncDeviceFlow).
  void cancel() {
    final shouldCancelCeremony = _shouldCancelActiveCeremony(state);
    final activeCeremonyHandle = _activeCeremonyHandle;
    _generation++;
    if (shouldCancelCeremony) {
      unawaited(_cancelActiveCeremony(activeCeremonyHandle));
    }
    _pendingPin = null;
    _pairingRelayUrl = null;
    _activeCeremonyHandle = null;
    if (state.step != PairingStep.enterUrl) {
      state = const PairingState();
    }
  }

  bool _shouldCancelActiveCeremony(PairingState state) {
    return switch (state.step) {
      PairingStep.showingRequest ||
      PairingStep.waitingForSas ||
      PairingStep.showingSas ||
      PairingStep.enterPin ||
      PairingStep.connecting => true,
      PairingStep.error =>
        state.requestQrPayload != null ||
            state.requestDeviceId != null ||
            state.sasWords != null,
      PairingStep.enterUrl ||
      PairingStep.success ||
      PairingStep.snapshotFailure => false,
    };
  }

  Future<void> _cancelActiveCeremony([
    ffi.PrismSyncHandle? activeHandle,
  ]) async {
    final handle =
        activeHandle ??
        _activeCeremonyHandle ??
        ref.read(prismSyncHandleProvider).value;
    if (handle == null) return;

    try {
      await ref
          .read(pairingCeremonyApiProvider)
          .cancelPairingCeremony(handle: handle)
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Pairing ceremony cancel failed: $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
  }

  /// Generate a rendezvous token QR for the joiner-initiated relay ceremony.
  /// The joiner displays this QR for an existing device to scan.
  Future<void> generateRequest({
    String? relayUrl,
    String? registrationToken,
  }) async {
    _generation++;
    final myGeneration = _generation;

    try {
      final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      final effectiveRelayUrl = relayUrl?.trim().isNotEmpty == true
          ? relayUrl!.trim()
          : await ref.read(relayUrlProvider.future) ??
                AppConstants.defaultRelayUrl;
      _pairingRelayUrl = effectiveRelayUrl;

      final handle = await handleNotifier.createHandle(
        relayUrl: effectiveRelayUrl,
      );
      _activeCeremonyHandle = handle;

      final trimmedToken = registrationToken?.trim();
      if (trimmedToken != null && trimmedToken.isNotEmpty) {
        await _seedRegistrationToken(handle, trimmedToken);
      }

      if (_generation != myGeneration) return;

      final jsonString = await pairingApi.startJoinerCeremony(handle: handle);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final tokenBytes = (json['token_bytes'] as List<dynamic>).cast<int>();
      final deviceId = json['device_id'] as String;

      if (_generation != myGeneration) return;

      state = state.copyWith(
        step: PairingStep.showingRequest,
        requestQrPayload: tokenBytes,
        requestDeviceId: deviceId,
        errorMessage: null,
        errorCode: null,
      );

      // Automatically start polling for SAS after showing the QR
      unawaited(_waitForSas(handle, myGeneration));
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      if (_generation != myGeneration) return;
      unawaited(_cancelActiveCeremony());
      state = state.copyWith(
        step: PairingStep.error,
        // A transient secure-storage read at boot (keychainUnavailable) is not
        // a pairing failure — the data is intact and a relaunch usually clears
        // it. Give the calm "try again" copy rather than a raw exception dump.
        errorMessage: e is SyncDbKeychainUnavailableException
            ? "Couldn't reach secure storage just now — your data is safe. "
                  'Close and reopen Prism, then try pairing again.'
            : structuredError?.userMessage ?? e.toString(),
        errorCode: structuredError?.code,
      );
    }
  }

  Future<void> _seedRegistrationToken(
    ffi.PrismSyncHandle handle,
    String registrationToken,
  ) {
    return ffi.seedSecureStore(
      handle: handle,
      entries: {
        'registration_token': Uint8List.fromList(
          utf8.encode(registrationToken),
        ),
      },
    );
  }

  /// Poll for SAS words from the relay after the initiator scans the QR.
  /// Keeps the QR visible (showingRequest) while polling — only transitions
  /// to showingSas once the initiator has actually scanned and posted
  /// PairingInit.
  Future<void> _waitForSas(ffi.PrismSyncHandle handle, int myGeneration) async {
    try {
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      if (_generation != myGeneration) return;

      final sasJsonString = await pairingApi.getJoinerSas(handle: handle);

      if (_generation != myGeneration) return;

      final sasJson = jsonDecode(sasJsonString) as Map<String, dynamic>;
      final sas = PairingSasDisplay.fromJson(sasJson);

      state = state.copyWith(step: PairingStep.showingSas, sasWords: sas.words);
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      if (_generation != myGeneration) return;
      unawaited(_cancelActiveCeremony(handle));
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: structuredError?.userMessage ?? e.toString(),
        errorCode: structuredError?.code,
      );
    }
  }

  /// User confirmed SAS words match — transition to password entry.
  void confirmSas() {
    if (state.step != PairingStep.showingSas) return;
    state = state.copyWith(
      step: PairingStep.enterPin,
      errorMessage: null,
      errorCode: null,
    );
  }

  /// Complete the joiner ceremony with the user's PIN (6-digit).
  ///
  /// Delegates to [completeJoinerWithPassword] — PIN is used as the sync
  /// auth password, matching the onboarding flow where the PIN is the
  /// Argon2id password for key derivation. The PIN is saved so that
  /// [_bootstrapAfterJoin] can store it as the app lock PIN.
  Future<void> completeJoinerWithPin(String pin) {
    _pendingPin = pin;
    return completeJoinerWithPassword(pin);
  }

  /// Complete the joiner ceremony with the user's password.
  Future<void> completeJoinerWithPassword(String password) async {
    if (password.trim().isEmpty) {
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: 'PIN cannot be empty.',
        errorCode: null,
      );
      return;
    }

    _generation++;
    final myGeneration = _generation;
    state = state.copyWith(
      step: PairingStep.connecting,
      errorMessage: null,
      errorCode: null,
    );

    // Tracks whether `completeJoinerCeremony` has returned successfully
    // AND the resulting credentials have been persisted to the platform
    // keychain via `drainRustStore`. Once true, credentials are committed
    // on the relay AND durable on this device; the only sanctioned wipe
    // paths from that point on are explicit user cancel
    // (`cancelAndRemoveDevice`) or a server-confirmed `device_revoked`
    // event. Any unexpected exception after this flips routes to
    // `PairingStep.snapshotFailure` so the user can retry the snapshot
    // phase without losing the joined identity.
    //
    // Critically: the flag is NOT flipped between ceremony returning and
    // drain succeeding. If drain itself throws we are still effectively
    // pre-persistence (credentials live only in Rust's in-memory store
    // and would evaporate on app restart), so we treat that window as a
    // ceremony-phase failure and wipe partial keychain state. The relay
    // device registration becomes orphaned but the relay's TTL-based
    // cleanup for unACKed brand-new registrations will reap it.
    var ceremonyCompleted = false;

    try {
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      final handle =
          _activeCeremonyHandle ?? ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        throw StateError('No sync handle available');
      }

      if (_generation != myGeneration) return;

      // Snapshot the `prism_sync.*` namespace BEFORE the ceremony. The
      // ceremony only mutates Rust's in-memory secure store, so any
      // entries we read here are an authoritative pre-pairing pre-state.
      // The post-ceremony drain is the first moment platform-keychain
      // writes happen on this device, and those writes have no atomicity
      // guarantee — a thrown write mid-mirror would otherwise leave the
      // keychain straddling pre-pairing and post-pairing state. Passing
      // this snapshot into the snapshot-rollback drain lets the mirror
      // restore the pre-state exactly on partial-write failure.
      // Protected DB-key slots are excluded so a rollback can never
      // overwrite the local-storage DEK.
      //
      // `null` here means the keychain scan itself threw — see
      // `_snapshotPrismSyncKeychain`. We still proceed with the
      // ceremony (aborting an in-flight pairing for a transient
      // keystore read failure is more disruptive than the loss of
      // exact rollback), but we use the plain `drainRustStore` path
      // below: without an authoritative pre-state we cannot safely
      // restore on a partial drain failure, so we fall back to the
      // post-config "log and continue" semantics. The capture failure
      // is reported via ErrorReportingService inside the helper.
      final preCeremonyKeychainSnapshot = await _snapshotPrismSyncKeychain();

      // PHASE 1 — Ceremony (45 s hard timeout). Credentials are not yet
      // established, so a timeout here is safe to clean up the keychain.
      Uint8List? passwordBytes;
      try {
        passwordBytes = secretUtf8Bytes(password);
        await pairingApi
            .completeJoinerCeremony(handle: handle, password: passwordBytes)
            .timeout(const Duration(seconds: 45));
        _activeCeremonyHandle = null;
      } on TimeoutException {
        _pendingPin = null;
        await _cleanupKeychainOnFailure();
        if (_generation != myGeneration) return;
        state = state.copyWith(
          step: PairingStep.error,
          errorMessage:
              'Connection timed out. Check your internet connection and try again.',
          errorCode: null,
        );
        return;
      } finally {
        zeroBytesBestEffort(passwordBytes);
      }

      // Ceremony returned — credentials live in Rust's in-memory secure
      // store but are NOT yet on the platform keychain. Persist them now,
      // BEFORE flipping `ceremonyCompleted`, so that "ceremony done" and
      // "credentials durable on this device" are the same moment. If we
      // flipped the flag first and drain fired later (e.g. inside
      // `_bootstrapAfterJoin`), a `configureEngine` / `setAutoSync` throw
      // would route to `snapshotFailure` while:
      //   - retrySnapshotBootstrap re-runs against an unconfigured handle
      //     with no keychain backing
      //   - cancelAndRemoveDevice can't read sync_id/device_id/session_token
      //     to call `deregisterDevice`, orphaning the relay registration
      // Doing the drain here closes that window.
      try {
        if (preCeremonyKeychainSnapshot != null) {
          await _drainRustStoreWithSnapshot(
            handle,
            rollbackSnapshot: preCeremonyKeychainSnapshot,
          );
        } else {
          // Snapshot capture failed — see the comment above. Without an
          // authoritative pre-state we cannot safely run the rollback
          // variant, so fall back to the plain drain and accept the
          // post-config "log and continue" partial-write semantics.
          await _drainRustStore(handle);
        }
      } catch (e, st) {
        // Drain itself failed — we are still pre-persistence, so treat
        // as a ceremony-phase failure. The relay device is registered
        // but unACKed; its TTL-based cleanup will reap it.
        _pendingPin = null;
        // Skip the keychain wipe when the drain rolled itself back to
        // the snapshot: `_cleanupKeychainOnFailure` would otherwise
        // delete the snapshot's pre-existing entries that the rollback
        // just restored. The plain-drain fallback path (no rollback)
        // still wipes, since there is no authoritative pre-state to
        // preserve there.
        if (e is! DrainPartialWriteException) {
          await _cleanupKeychainOnFailure();
        }
        ErrorReportingService.instance.report(
          'Pairing drain after ceremony failed (pre-persistence) — '
          'relay device will be reaped by TTL cleanup: $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
        if (_generation != myGeneration) return;
        final structuredError = PrismSyncStructuredError.tryParse(e);
        state = state.copyWith(
          step: PairingStep.error,
          errorMessage:
              structuredError?.userMessage ??
              "Couldn't save pairing credentials to this device. "
                  'Please try pairing again.',
          errorCode: structuredError?.code,
        );
        return;
      }

      // Ceremony AND credential persistence both succeeded. From this
      // point forward, failures preserve credentials so cancel/retry
      // paths remain functional.
      ceremonyCompleted = true;

      if (_generation != myGeneration) return;

      // PHASE 2+3 — bootstrap + apply. Own timeout boundaries live inside
      // _bootstrapAfterJoin / _runSnapshotBootstrap. Credentials may be
      // established by the time bootstrap starts, so those phases MUST NOT
      // wipe the keychain on timeout — they route to snapshotFailure
      // instead (see _runSnapshotBootstrap).
      await _bootstrapAfterJoin(handle, myGeneration);
    } catch (e, st) {
      _pendingPin = null;
      await _handlePostCeremonyFailure(
        ceremonyCompleted: ceremonyCompleted,
        error: e,
        stackTrace: st,
        myGeneration: myGeneration,
      );
    }
  }

  /// Routes an exception escaping the joiner pipeline to either
  /// [PairingStep.error] (with keychain wipe) when the ceremony hasn't
  /// completed yet, or to [PairingStep.snapshotFailure] (preserving
  /// credentials) when it has.
  ///
  /// Extracted so the credential-lifecycle gate can be exercised by unit
  /// tests without mocking the Rust FFI surface.
  @visibleForTesting
  Future<void> handlePostCeremonyFailureForTest({
    required bool ceremonyCompleted,
    required Object error,
    StackTrace? stackTrace,
  }) {
    return _handlePostCeremonyFailure(
      ceremonyCompleted: ceremonyCompleted,
      error: error,
      stackTrace: stackTrace ?? StackTrace.current,
      myGeneration: _generation,
    );
  }

  Future<void> _handlePostCeremonyFailure({
    required bool ceremonyCompleted,
    required Object error,
    required StackTrace stackTrace,
    required int myGeneration,
  }) async {
    final structuredError = PrismSyncStructuredError.tryParse(error);
    final isEpochVerificationFailure = _isEpochVerificationFailure(
      structuredError,
    );

    if (!ceremonyCompleted) {
      // Failure happened BEFORE credentials were committed — safe to
      // wipe partial keychain state and surface a hard error so the
      // user can restart pairing from scratch.
      await _cleanupKeychainOnFailure();
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: isEpochVerificationFailure
            ? _epochVerificationFailureMessage(credentialsDurable: false)
            : structuredError?.userMessage ?? error.toString(),
        errorCode: structuredError?.code,
      );
      return;
    }

    // Ceremony already succeeded. Preserve credentials and route to
    // `snapshotFailure` so the user sees Retry + Cancel actions instead
    // of being orphaned on the relay with a wiped local keychain.
    ErrorReportingService.instance.report(
      'Pairing bootstrap failed after ceremony (preserving creds): $error',
      severity: ErrorSeverity.error,
      stackTrace: stackTrace,
    );
    if (_generation != myGeneration) return;
    state = state.copyWith(
      step: PairingStep.snapshotFailure,
      errorMessage: isEpochVerificationFailure
          ? _epochVerificationFailureMessage(credentialsDurable: true)
          : structuredError?.userMessage ??
                'Pairing succeeded but setup failed. You can retry without '
                    're-running the pairing handshake.',
      errorCode: structuredError?.code,
      syncIncomplete: true,
    );
  }

  /// Shared bootstrap logic after the relay ceremony succeeds.
  Future<void> _bootstrapAfterJoin(
    ffi.PrismSyncHandle handle,
    int myGeneration,
  ) async {
    // Capture the progress notifier before the first await so it remains
    // safe to call across async boundaries.
    final progressNotifier = ref.read(syncSetupProgressProvider.notifier);

    await ffi.configureEngine(handle: handle);
    // BOUNDARY 1: engine configured — we have a connection, begin downloading.
    if (_generation == myGeneration) {
      progressNotifier.setPhase(PairingProgressPhase.downloading);
    }

    if (_generation != myGeneration) return;

    await _runSnapshotBootstrap(handle, myGeneration, progressNotifier);
  }

  Future<void> _enableAutoSync(ffi.PrismSyncHandle handle) {
    return ffi.setAutoSync(
      handle: handle,
      enabled: true,
      debounceMs: BigInt.from(300),
      retryDelayMs: BigInt.from(30000),
      maxRetries: 3,
    );
  }

  Future<void> _runPostBootstrapCatchUp(
    ffi.PrismSyncHandle handle, {
    Future<String> Function({required ffi.PrismSyncHandle handle})? syncNow,
    Future<void> Function(ffi.PrismSyncHandle handle)? drain,
    Duration eventTimeout = const Duration(seconds: 60),
  }) async {
    final syncNowFn = syncNow ?? ffi.syncNow;
    final drainFn = drain ?? _drainRustStore;

    Object? streamError;
    StackTrace? streamStackTrace;
    final terminalEventSeen = Completer<void>();
    final subscription = ref.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (_, next) {
        next.when(
          data: (event) {
            if ((event.isSyncCompleted || event.isError) &&
                !terminalEventSeen.isCompleted) {
              terminalEventSeen.complete();
            }
          },
          error: (error, stackTrace) {
            streamError = error;
            streamStackTrace = stackTrace;
            if (!terminalEventSeen.isCompleted) {
              terminalEventSeen.complete();
            }
          },
          loading: () {},
        );
      },
    );

    try {
      // Give StreamProvider one microtask to attach before syncNow emits events.
      await Future<void>.delayed(Duration.zero);

      final resultJson = await syncNowFn(handle: handle);
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      final error = result['error'];
      if (error is String && error.isNotEmpty) {
        throw StateError(error);
      }

      final pulled = _syncResultPulledCount(result);
      if (pulled > 0) {
        await terminalEventSeen.future.timeout(
          eventTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Timed out waiting for post-pairing sync events',
              eventTimeout,
            );
          },
        );
      }

      if (streamError != null) {
        Error.throwWithStackTrace(
          streamError!,
          streamStackTrace ?? StackTrace.current,
        );
      }

      // syncNow performs missed-epoch recovery before pull. Persist any
      // recovered epoch keys, refreshed session tokens, or other secure-store
      // state before the user leaves the pairing flow.
      await drainFn(handle);
    } finally {
      subscription.close();
    }
  }

  int _syncResultPulledCount(Map<String, dynamic> result) {
    final pulled = result['pulled'];
    if (pulled is int) return pulled;
    if (pulled is num) return pulled.toInt();
    if (pulled is String) return int.tryParse(pulled) ?? 0;
    return 0;
  }

  @visibleForTesting
  Future<void> runPostBootstrapCatchUpForTest({
    required ffi.PrismSyncHandle handle,
    required Future<String> Function({required ffi.PrismSyncHandle handle})
    syncNow,
    required Future<void> Function(ffi.PrismSyncHandle handle) drain,
    Duration eventTimeout = const Duration(seconds: 60),
  }) {
    return _runPostBootstrapCatchUp(
      handle,
      syncNow: syncNow,
      drain: drain,
      eventTimeout: eventTimeout,
    );
  }

  /// Arm the one-shot pending-snapshot-ACK retry. Called when the initial
  /// post-pairing catch-up did not succeed (or the journal had not drained) so
  /// the snapshot ACK-delete was withheld and the relay still holds the
  /// joiner's bootstrap source. The next successful `syncNow` re-runs catch-up
  /// and, if it now succeeds, ACK-deletes the snapshot — after which the
  /// listener closes itself. Idempotent: re-arming while already armed is a
  /// no-op, so a per-attempt single retry is installed.
  void _armPendingSnapshotAckRetry(ffi.PrismSyncHandle handle) {
    if (_pendingSnapshotAckRetrySub != null) return;
    final myGeneration = _generation;
    _pendingSnapshotAckRetrySub = ref.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (_, next) {
        next.whenData((event) {
          // Only a clean SyncCompleted (no structured error) means the cursor
          // advanced — an errored cycle hasn't caught us up, so keep waiting.
          if (!event.isSyncCompleted || event.errorKind != null) return;
          if (_generation != myGeneration) {
            _disposePendingSnapshotAckRetry();
            return;
          }
          if (_pendingSnapshotAckRetryRunning) return;
          _pendingSnapshotAckRetryRunning = true;
          unawaited(
            _runPendingSnapshotAckRetry(handle, myGeneration).whenComplete(() {
              _pendingSnapshotAckRetryRunning = false;
            }),
          );
        });
      },
    );
  }

  /// Re-run catch-up and, if it now succeeds with a drained journal, ACK-delete
  /// the retained snapshot. Disposes the armed listener whether or not the ACK
  /// fires this round: this is a single-shot retry (a still-failing catch-up
  /// stays covered by the relay's snapshot TTL), so it never loops on every
  /// completion. `catchUp`/`ack` are injectable for tests; production uses the
  /// real FFI.
  Future<void> _runPendingSnapshotAckRetry(
    ffi.PrismSyncHandle handle,
    int myGeneration, {
    Future<void> Function(ffi.PrismSyncHandle handle)? catchUp,
    Future<void> Function({required ffi.PrismSyncHandle handle})? ack,
  }) async {
    // Tear down the listener up front so this retry fires exactly once.
    _disposePendingSnapshotAckRetry();

    final catchUpFn = catchUp ?? _runPostBootstrapCatchUp;
    final ackFn = ack ?? ffi.acknowledgeSnapshotApplied;

    var catchUpSucceeded = true;
    try {
      await catchUpFn(handle);
    } catch (e, st) {
      catchUpSucceeded = false;
      ErrorReportingService.instance.report(
        'Pending snapshot-ACK retry catch-up failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    if (_generation != myGeneration) return;

    if (shouldAckSnapshotApplied(
      journalDrained: _bootstrapJournalDrained,
      catchUpSucceeded: catchUpSucceeded,
    )) {
      try {
        await ackFn(handle: handle);
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'acknowledgeSnapshotApplied retry failed (non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
    }
  }

  void _disposePendingSnapshotAckRetry() {
    _pendingSnapshotAckRetrySub?.close();
    _pendingSnapshotAckRetrySub = null;
  }

  /// Test seam: drive the armed-retry runner directly (the production trigger is
  /// the next successful `SyncCompleted` on [syncEventStreamProvider]). The
  /// `catchUp`/`ack` closures stand in for the real FFI so the gate logic can be
  /// asserted without a live engine.
  @visibleForTesting
  Future<void> runPendingSnapshotAckRetryForTest(
    ffi.PrismSyncHandle handle, {
    required Future<void> Function(ffi.PrismSyncHandle handle) catchUp,
    required Future<void> Function({required ffi.PrismSyncHandle handle}) ack,
  }) {
    return _runPendingSnapshotAckRetry(
      handle,
      _generation,
      catchUp: catchUp,
      ack: ack,
    );
  }

  /// Test seam: whether a pending-snapshot-ACK retry is currently armed.
  @visibleForTesting
  bool get pendingSnapshotAckRetryArmed => _pendingSnapshotAckRetrySub != null;

  /// Test seam: arm the retry without running the full bootstrap flow.
  @visibleForTesting
  void armPendingSnapshotAckRetryForTest(ffi.PrismSyncHandle handle) {
    _armPendingSnapshotAckRetry(handle);
  }

  /// Test seam: set the journal-drained flag so retry tests can compose the
  /// ACK conjunction without standing up the full bootstrap drain.
  @visibleForTesting
  // ignore: avoid_setters_without_getters
  set bootstrapJournalDrainedForTest(bool value) {
    _bootstrapJournalDrained = value;
  }

  /// Run the snapshot-download + apply phase. Extracted so the retry path can
  /// re-invoke just this chunk (the relay-side ceremony state is already
  /// committed by [completeJoinerCeremony]).
  Future<void> _runSnapshotBootstrap(
    ffi.PrismSyncHandle handle,
    int myGeneration,
    SyncSetupProgressNotifier progressNotifier,
  ) async {
    // Activate the sync event stream BEFORE bootstrap so RemoteChanges
    // events from bootstrapFromSnapshot are consumed as they arrive.
    // Without this, the bootstrap emits entities to Rust's broadcast
    // channel but nothing on the Dart side processes them into Drift.
    if (kDebugMode) {
      debugPrint('[PAIRING] Activating syncEventStreamProvider...');
    }
    final syncAdapter = ref.read(driftSyncAdapterProvider);
    final strictCoordinator = ref.read(strictApplyCoordinatorProvider);

    // Enter strict-apply mode + begin the sync batch BEFORE kicking off
    // bootstrap so the pre-registered latch honours signal ordering
    // regardless of when the await is scheduled. First writer wins:
    // either strict-apply fails (signalFailure) or the batch finishes
    // (signalBatchComplete).
    final outcomeFuture = strictCoordinator.enterStrictMode();
    // Latch-only arm: the bootstrap resolves through the strict coordinator's
    // signalBatchComplete, never completeSyncBatch, so a full beginSyncBatch
    // here would leak the deferred-replay depth and starve PK group-entry
    // replay for the rest of the session (the snapshot apply's own begin/
    // complete batches manage the replay depth).
    syncAdapter.armBatchCompletionLatch();
    _bootstrapJournalDrained = false;
    // A retry armed by a previous attempt no longer applies to this fresh
    // bootstrap; tear it down so it can't ACK against the wrong attempt.
    _disposePendingSnapshotAckRetry();

    var fatalSnapshotError = false;
    String? fatalSnapshotMessage;
    String? fatalSnapshotCode;
    var bootstrapRestored = BigInt.zero;

    try {
      // PHASE 2 — snapshot download + Rust import. 10-minute hard ceiling
      // covers a realistic large-system ingest on slow mobile links while
      // still bounding worst-case hang. Credentials may be established
      // inside the FFI call, so a timeout here routes to snapshotFailure
      // (retry-safe) rather than wiping the keychain.
      try {
        bootstrapRestored = await ffi
            .bootstrapFromSnapshot(handle: handle)
            .timeout(const Duration(minutes: 10));
        if (kDebugMode) {
          debugPrint(
            '[PAIRING] bootstrapFromSnapshot returned $bootstrapRestored',
          );
        }
      } on TimeoutException catch (e, stackTrace) {
        fatalSnapshotError = true;
        fatalSnapshotMessage =
            'Timed out downloading your system from the pairing device. '
            'Please try again.';
        if (_generation == myGeneration) {
          progressNotifier.markTimedOut();
        }
        ErrorReportingService.instance.report(
          'Snapshot bootstrap timed out (fatal): $e',
          severity: ErrorSeverity.error,
          stackTrace: stackTrace,
        );
      } catch (e, stackTrace) {
        fatalSnapshotError = true;
        final structuredError = PrismSyncStructuredError.tryParse(e);
        fatalSnapshotMessage = _isEpochVerificationFailure(structuredError)
            ? _epochVerificationFailureMessage(credentialsDurable: true)
            : structuredError?.userMessage ?? e.toString();
        fatalSnapshotCode = structuredError?.code;
        if (kDebugMode) {
          debugPrint('[PAIRING] bootstrapFromSnapshot threw: $e');
        }
        ErrorReportingService.instance.report(
          'Snapshot bootstrap failed (fatal): $e',
          severity: ErrorSeverity.error,
          stackTrace: stackTrace,
        );
      }

      if (!fatalSnapshotError && bootstrapRestored == BigInt.zero) {
        fatalSnapshotError = true;
        fatalSnapshotMessage =
            "Couldn't load your system from the pairing device. "
            'Please try again.';
      }

      // BOUNDARY 2: snapshot bootstrap resolved — now applying remote
      // changes to the local database (restoring phase).
      if (_generation == myGeneration) {
        progressNotifier.setPhase(PairingProgressPhase.restoring);
      }

      if (!fatalSnapshotError) {
        // PHASE 3 — Dart-side apply. The watchdog fails only after 60 s with
        // no strict-apply progress or batch completion.
        final applyOutcome = await _awaitApplyOutcomeWithWatchdog(
          handle: handle,
          outcomeFuture: outcomeFuture,
          idleTimeout: const Duration(seconds: 60),
        );

        switch (applyOutcome) {
          case ApplyOutcomeSuccess():
            try {
              await ackBootstrapConsumerDeliveryJournal(handle: handle);
              _bootstrapJournalDrained = true;
            } catch (e, st) {
              fatalSnapshotError = true;
              fatalSnapshotMessage =
                  'Failed to finish applying your system. Please try again.';
              ErrorReportingService.instance.report(
                'Post-bootstrap consumer-delivery journal ACK failed: $e',
                severity: ErrorSeverity.error,
                stackTrace: st,
              );
            }
            break;
          case ApplyOutcomeFailure(:final failure, :final stackTrace):
            fatalSnapshotError = true;
            final isTimeout = failure.message.startsWith('TIMEOUT:');
            if (isTimeout) {
              fatalSnapshotMessage =
                  'Timed out applying your system. Please try again.';
              if (_generation == myGeneration) {
                progressNotifier.markTimedOut();
              }
            } else {
              fatalSnapshotMessage =
                  'Failed to apply your system to this device '
                  '(${failure.table ?? 'unknown'}). Please try again.';
            }
            ErrorReportingService.instance.report(
              'Snapshot apply failed (fatal): $failure',
              severity: ErrorSeverity.error,
              stackTrace: stackTrace ?? StackTrace.current,
            );
            break;
        }
      }
    } finally {
      strictCoordinator.exitStrictMode();
    }

    if (_generation != myGeneration) return;

    if (fatalSnapshotError) {
      // Defensive re-drain: credentials were already persisted to the
      // keychain immediately after the ceremony returned, so this is
      // expected to be a no-op (drainRustStore is idempotent — it reads
      // current Rust state and writes the same keys). Kept as a belt-and-
      // braces guarantee that retry + cancel paths can read sync_id /
      // device_id / session_token from the keychain without needing the
      // Rust handle to survive.
      try {
        await _drainRustStore(handle);
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'drainRustStore after snapshot failure failed (non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
      state = state.copyWith(
        step: PairingStep.snapshotFailure,
        errorMessage: fatalSnapshotMessage,
        errorCode: fatalSnapshotCode,
        syncIncomplete: true,
      );
      return;
    }

    try {
      await _writeSnapshotApplyCompleteMarker();
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Snapshot apply completed but recovery marker write failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.snapshotFailure,
        errorMessage:
            'Pairing restored your system, but setup could not be saved '
            'durably. Please try again.',
        errorCode: null,
        syncIncomplete: true,
      );
      return;
    }

    // BOUNDARY 3: syncBatchComplete resolved — entering finishing phase.
    if (_generation == myGeneration) {
      progressNotifier.setPhase(PairingProgressPhase.finishing);
    }

    if (_generation != myGeneration) return;

    // Credentials were already drained to the keychain immediately after
    // `completeJoinerCeremony` returned — see `completeJoinerWithPassword`
    // for the rationale. We intentionally do NOT re-drain just for snapshot
    // bootstrap: the ceremony-time drain captures the same Rust secure-store
    // state (sync_id, device_id, session_token, wrapped_dek, etc.) that would
    // have been written at this point, and `configureEngine` /
    // `bootstrapFromSnapshot` do not mint new credentials that need
    // persisting. The post-bootstrap catch-up below does drain again because
    // `syncNow` can recover a missed epoch key or refresh secure-store state.
    //
    // From here on, the snapshot has been imported and applied locally. These
    // finishing steps improve startup/sync continuity, but they must not turn
    // a restored device back into snapshotFailure and strand it in onboarding.
    var syncIncomplete = false;

    // Defensively ensure relay_url and sync_id are written under the keys
    // that relayUrlProvider / syncIdProvider read from. The post-ceremony
    // drainRustStore should already cover these; these writes are a
    // final fallback for older code paths.
    final syncId = (await safeSecureRead(kSyncIdKey)).value;
    final storedRelay = (await safeSecureRead(kSyncRelayUrlKey)).value;
    final relayUrl = _pairingRelayUrl ?? AppConstants.defaultRelayUrl;
    if (storedRelay == null || storedRelay.isEmpty) {
      final relayWrite = await safeSecureWrite(
        kSyncRelayUrlKey,
        base64Encode(utf8.encode(relayUrl)),
      );
      if (!relayWrite.ok) {
        syncIncomplete = true;
        ErrorReportingService.instance.report(
          'Fallback relay_url secure-storage write failed after pairing '
          '(failure=${relayWrite.failure?.name ?? 'unknown'}, '
          'code=${relayWrite.code}, message=${relayWrite.message})',
          severity: ErrorSeverity.warning,
        );
      }
    }
    if (syncId == null || syncId.isEmpty) {
      // sync_id wasn't populated by drainRustStore — this shouldn't
      // normally happen but is guarded against defensively.
    }

    ref.invalidate(relayUrlProvider);
    ref.invalidate(syncIdProvider);
    ref.invalidate(syncDeviceIdProvider);
    ref.invalidate(syncDeviceSecretPresentProvider);
    ref.invalidate(syncWrappedDekPresentProvider);

    // Cache a device-bound wrapped DEK so launches bypass Argon2id. Non-fatal:
    // if the cache write fails, the next launch can still recover through the
    // mnemonic + PIN unlock sheet because wrapped credentials are durable.
    try {
      await cacheRuntimeKeys(handle, ref.read(databaseProvider));
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'cacheRuntimeKeys after pairing failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    // Store Device 1's PIN as this device's app lock PIN so the user
    // has one PIN across all devices. Non-fatal: credentials are already
    // persisted, so a failure here shouldn't wipe the successful pairing.
    if (_pendingPin != null) {
      try {
        final pinService = ref.read(pinLockServiceProvider);
        await pinService.storePin(_pendingPin!);
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'Failed to store app-lock PIN after pairing (non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      } finally {
        _pendingPin = null;
      }
    }

    if (_generation != myGeneration) return;

    // Enable notification-driven incremental sync only after the pairing
    // snapshot has been imported and applied. The initiator rotates to the
    // next epoch immediately after credentials are exchanged; starting the
    // auto-sync driver before bootstrap can race that epoch catch-up sync
    // against the snapshot apply path.
    try {
      await _enableAutoSync(handle);
    } catch (e, st) {
      syncIncomplete = true;
      ErrorReportingService.instance.report(
        'setAutoSync after pairing failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    if (_generation != myGeneration) return;

    // setAutoSync wires the auto-sync driver but does not emit an initial
    // trigger. Run one explicit catch-up now so the joiner recovers the
    // initiator's post-pairing epoch rotation and applies any rows that landed
    // after the snapshot was cut.
    var catchUpSucceeded = true;
    try {
      await _runPostBootstrapCatchUp(handle);
    } on TimeoutException catch (e, st) {
      syncIncomplete = true;
      catchUpSucceeded = false;
      if (_generation == myGeneration) {
        progressNotifier.markTimedOut();
      }
      ErrorReportingService.instance.report(
        'Post-pairing catch-up timed out after snapshot apply '
        '(non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    } catch (e, st) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      if (_isEpochVerificationFailure(structuredError)) {
        Error.throwWithStackTrace(e, st);
      }
      syncIncomplete = true;
      catchUpSucceeded = false;
      ErrorReportingService.instance.report(
        'Post-pairing catch-up failed after snapshot apply '
        '(non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    if (_generation != myGeneration) return;

    // ACK-delete the relay's retained bootstrap snapshot only once it is safe to
    // do so — composing TWO conditions:
    //   1. the post-bootstrap consumer-delivery drain emptied the journal, so a
    //      crash between the Rust import-commit and the Dart apply re-derives
    //      losslessly; and
    //   2. catch-up succeeded, so the joiner has pulled and applied the tail the
    //      initiator pushed after cutting the snapshot.
    // If catch-up failed/timed out, the snapshot is the joiner's only bootstrap
    // source for that tail, so we must NOT discard it: leave it on the relay (its
    // 24h TTL covers cleanup) and arm a one-shot retry that re-runs catch-up and
    // ACK on the next successful syncNow. Best-effort: a failed ACK doesn't undo a
    // good pairing, and older relays respond 405, which the FFI folds to Ok.
    if (shouldAckSnapshotApplied(
      journalDrained: _bootstrapJournalDrained,
      catchUpSucceeded: catchUpSucceeded,
    )) {
      try {
        await ffi.acknowledgeSnapshotApplied(handle: handle);
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'acknowledgeSnapshotApplied failed (non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
    } else {
      final reason = !_bootstrapJournalDrained
          ? 'consumer-delivery journal not yet drained'
          : 'post-pairing catch-up did not succeed';
      ErrorReportingService.instance.report(
        'Skipping snapshot ACK-delete ($reason); snapshot retained on the relay '
        '(TTL covers cleanup), retry armed for the next successful syncNow',
        severity: ErrorSeverity.warning,
      );
      _armPendingSnapshotAckRetry(handle);
    }

    if (_generation != myGeneration) return;

    final counts = await _countLocalData();
    if (kDebugMode) {
      debugPrint(
        '[PAIRING] Local data counts: members=${counts.members}, sessions=${counts.frontingSessions}, convos=${counts.conversations}, messages=${counts.messages}, habits=${counts.habits}',
      );
    }
    state = state.copyWith(
      step: PairingStep.success,
      counts: counts,
      syncIncomplete: syncIncomplete,
    );
  }

  Future<void> _writeSnapshotApplyCompleteMarker() async {
    // Reads use the classified wrapper — cipher failure here resolves to
    // null and triggers the same StateError as a clean miss. The pairing
    // flow has no recovery path if sync_id/device_id are unreadable so a
    // typed error to the user-facing catch is the right escalation.
    final syncId = (await safeSecureRead(kSyncIdKey)).value;
    final deviceId = (await safeSecureRead(kSyncDeviceIdKey)).value;
    if (syncId == null ||
        syncId.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      throw StateError(
        'Cannot mark snapshot apply complete without sync_id and device_id',
      );
    }

    // Critical write: if the marker doesn't land, the next launch cannot
    // distinguish "snapshot applied" from "pairing interrupted mid-apply".
    // Surface platform failures to the caller (the pairing flow) so it
    // routes to the failure path. The classified wrapper returns a
    // structured result; we re-throw as a PlatformException for the caller's
    // existing catch.
    final write = await safeSecureWrite(
      kSnapshotApplyCompleteKey,
      snapshotApplyCompleteMarkerValue(syncId: syncId, deviceId: deviceId),
    );
    if (!write.ok) {
      throw PlatformException(
        code: write.code ?? 'snapshot_apply_marker_write_failed',
        message:
            write.message ?? 'Failed to write snapshot apply complete marker',
      );
    }

    // This joiner now has persisted sync-group credentials, so subsequent
    // live edits enqueue durably into the outbox. (Boot's `createHandle` also
    // sets this from the keychain; setting it here closes the window between
    // ceremony completion and the next handle creation.)
    syncCredentialsPersisted.value = true;
  }

  @visibleForTesting
  Future<void> writeSnapshotApplyCompleteMarkerForTest() {
    return _writeSnapshotApplyCompleteMarker();
  }

  /// Wait for strict apply while enforcing an idle watchdog. Strict-apply row
  /// progress resets the timer; downstream `RemoteChanges` is only a fallback
  /// heartbeat because it arrives after the batch applies.
  ///
  /// `SyncCompleted` and `WebSocketStateChanged` are ignored because they can
  /// come from unrelated auto-sync or reconnect churn.
  ///
  /// On timeout this writes a failure into the pre-registered strict-apply
  /// latch (message prefixed `TIMEOUT:` so the caller can distinguish) and
  /// returns the resulting [ApplyOutcomeFailure]. Credentials are NOT wiped
  /// on timeout — the caller routes to `snapshotFailure` so the user can
  /// retry or explicitly cancel.
  Future<ApplyOutcome> _awaitApplyOutcomeWithWatchdog({
    required ffi.PrismSyncHandle handle,
    required Future<ApplyOutcome> outcomeFuture,
    required Duration idleTimeout,
  }) async {
    final coordinator = ref.read(strictApplyCoordinatorProvider);
    Timer? watchdog;

    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(idleTimeout, () {
        if (kDebugMode) {
          debugPrint(
            '[PAIRING] Apply watchdog fired after ${idleTimeout.inSeconds}s of inactivity',
          );
        }
        coordinator.signalFailure(
          StrictApplyFailure(
            message: 'TIMEOUT: no apply activity for ${idleTimeout.inSeconds}s',
            failedTables: const [],
          ),
        );
      });
    }

    // Start the watchdog immediately — if bootstrap already wrote rows to
    // Rust but the Dart stream never starts applying, we still want a deadline.
    resetWatchdog();

    final progressSubscription = coordinator.progressStream.listen((_) {
      resetWatchdog();
    });

    // Keep downstream RemoteChanges as a secondary heartbeat for event paths
    // that bypass strict progress.
    final subscription = ref.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (_, next) {
        next.whenData((event) {
          if (event.isRemoteChanges) {
            resetWatchdog();
          }
        });
      },
    );

    try {
      return await outcomeFuture;
    } finally {
      watchdog?.cancel();
      await progressSubscription.cancel();
      subscription.close();
    }
  }

  /// Test-only wrapper around the private apply-outcome watchdog so unit
  /// tests can verify the idle-reset policy (Finding B regression).
  @visibleForTesting
  Future<ApplyOutcome> awaitApplyOutcomeWithWatchdogForTest({
    required ffi.PrismSyncHandle handle,
    required Future<ApplyOutcome> outcomeFuture,
    required Duration idleTimeout,
  }) {
    return _awaitApplyOutcomeWithWatchdog(
      handle: handle,
      outcomeFuture: outcomeFuture,
      idleTimeout: idleTimeout,
    );
  }

  /// Retry the snapshot bootstrap after a [PairingStep.snapshotFailure].
  ///
  /// The joiner is already registered on the relay at this point, so we
  /// re-run only the snapshot download + apply. Keychain credentials
  /// (sync_id, device_id, session_token) are already persisted from the
  /// failure path's drain, so the existing handle can pick up where it
  /// left off. Idempotent: re-applying snapshot rows is safe under LWW.
  Future<void> retrySnapshotBootstrap() async {
    if (state.step != PairingStep.snapshotFailure) return;
    _generation++;
    final myGeneration = _generation;

    state = state.copyWith(
      step: PairingStep.connecting,
      errorMessage: null,
      errorCode: null,
      syncIncomplete: false,
    );

    try {
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        throw StateError('No sync handle available for retry');
      }
      final progressNotifier = ref.read(syncSetupProgressProvider.notifier);
      // Reset progress so the UI doesn't show a stale "finishing" phase.
      progressNotifier.reset();
      progressNotifier.setPhase(PairingProgressPhase.downloading);
      await _runSnapshotBootstrap(handle, myGeneration, progressNotifier);
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.snapshotFailure,
        errorMessage: _isEpochVerificationFailure(structuredError)
            ? _epochVerificationFailureMessage(credentialsDurable: true)
            : structuredError?.userMessage ?? e.toString(),
        errorCode: structuredError?.code,
      );
    }
  }

  /// Cancel pairing explicitly after a snapshot failure, removing this
  /// device from the relay and wiping the joiner's local keychain.
  ///
  /// Distinct from dismissing the sheet: dismissal preserves creds so the
  /// user can retry later (e.g. if they minimized the app mid-pair).
  /// This path runs only when the user clicks "Cancel and remove this
  /// device" in the snapshot-failure view.
  Future<void> cancelAndRemoveDevice() async {
    _generation++;
    const prefix = 'prism_sync.';

    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle != null) {
      try {
        final syncId = await _readDecodedSecureValue('${prefix}sync_id');
        final deviceId = await _readDecodedSecureValue('${prefix}device_id');
        final sessionToken = await _readDecodedSecureValue(
          '${prefix}session_token',
        );
        if (syncId != null && deviceId != null && sessionToken != null) {
          try {
            await ffi.deregisterDevice(
              handle: handle,
              syncId: syncId,
              deviceId: deviceId,
              sessionToken: sessionToken,
            );
          } catch (e, st) {
            ErrorReportingService.instance.report(
              'deregisterDevice during cancel failed (non-fatal): $e',
              severity: ErrorSeverity.warning,
              stackTrace: st,
            );
          }
        }
      } catch (e, st) {
        ErrorReportingService.instance.report(
          'Cancel deregister prep failed (non-fatal): $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
    }

    await _cleanupKeychainOnFailure();
    _pendingPin = null;
    _pairingRelayUrl = null;
    ref.invalidate(relayUrlProvider);
    ref.invalidate(syncIdProvider);
    ref.invalidate(syncDeviceIdProvider);
    ref.invalidate(syncDeviceSecretPresentProvider);
    ref.invalidate(syncWrappedDekPresentProvider);
    ref.read(syncSetupProgressProvider.notifier).reset();
    state = const PairingState();
  }

  Future<String?> _readDecodedSecureValue(String key) async {
    // Classified read — cipher / transient / unknown failures resolve to
    // null. The caller (cancel-and-remove-device flow) interprets null as
    // "credential unavailable, skip deregister" rather than crashing.
    final raw = (await safeSecureRead(key)).value;
    if (raw == null || raw.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(raw));
    } catch (_) {
      return raw; // legacy plain-text fallback
    }
  }

  /// Remove any keychain keys that may have been written during a failed
  /// pairing attempt (via drainRustStore / cacheRuntimeKeys) so that
  /// partial credentials don't linger and confuse future startup logic.
  ///
  /// Delegates to the shared [wipeSyncKeychainNamespace] helper so that
  /// every transient `prism_sync.*` key (including dynamic families like
  /// `epoch_key_*` / `runtime_keys_*` / `pending_*` / `setup_rollback_marker`
  /// that older static lists silently drifted past) gets wiped. The
  /// `kProtectedFromReset` DB-encryption slots are preserved by the helper —
  /// they are local-storage Signal-model keys that must survive a failed
  /// pairing attempt or the encrypted local DB becomes unreadable.
  ///
  /// Pass `includeRuntimeDekWrappingKey: false`: the AndroidKeystore-backed
  /// wrapping key is a per-device construct that must survive a failed
  /// pairing attempt so the user's existing wrapped runtime DEK can still
  /// be unwrapped on the next launch.
  ///
  /// **Callers MUST skip this when `drainRustStoreWithSnapshotRollback`
  /// has already rolled back to a caller-owned snapshot** — the drain's
  /// rollback restored the pre-pairing keychain state, and a follow-up
  /// wipe here would then delete the snapshot's pre-existing entries.
  /// The joiner failure path detects this by checking `is
  /// DrainPartialWriteException` on the caught error.
  Future<void> _cleanupKeychainOnFailure() async {
    await wipeSyncKeychainNamespace(
      // Funnel readAll + deleteKey through the classified wrappers so a
      // cipher failure during cleanup cannot escape past this helper. The
      // wipe is by-prefix best-effort; individual delete failures are
      // already accepted by the helper.
      readAll: () async {
        final result = await safeSecureReadAll();
        if (!result.ok) {
          throw StateError(
            'secure storage readAll failed during pairing cleanup '
            '(failure=${result.failure?.name ?? 'unknown'}, '
            'code=${result.code}, message=${result.message})',
          );
        }
        return result.entries;
      },
      deleteKey: (key) async {
        final result = await safeSecureDelete(key);
        if (!result.ok) {
          throw StateError(
            'secure storage delete failed during pairing cleanup for $key '
            '(failure=${result.failure?.name ?? 'unknown'}, '
            'code=${result.code}, message=${result.message})',
          );
        }
      },
      includeRuntimeDekWrappingKey: false,
      log: (message) {
        // Best-effort cleanup — surface as a debug log, don't propagate.
        if (kDebugMode) {
          debugPrint('[PAIRING] $message');
        }
      },
    );
  }

  /// Mark onboarding as complete after sync pairing.
  ///
  /// Unlike the normal onboarding flow (which applies system name,
  /// terminology, etc. via OnboardingCommitService), synced data should
  /// already contain those settings. We just need to ensure
  /// hasCompletedOnboarding is set so the user isn't sent back here.
  /// If the sync pulled settings, they'll already be in the DB and we
  /// preserve them. If not, defaults are fine — the user can customize
  /// from Settings later.
  Future<void> completeOnboarding() async {
    final settingsRepo = ref.read(systemSettingsRepositoryProvider);
    final current = await settingsRepo.getSettings();
    if (!current.hasCompletedOnboarding) {
      await settingsRepo.updateSettings(
        current.copyWith(hasCompletedOnboarding: true),
      );
    }
    try {
      await ref.read(syncDisconnectMarkerStoreProvider).delete();
      ref.invalidate(syncDisconnectMarkerProvider);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Sync disconnect marker cleanup failed after pairing: $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }
  }

  Future<SyncCounts> _countLocalData() async {
    final db = ref.read(databaseProvider);
    final members = await db
        .customSelect('SELECT COUNT(*) AS c FROM members WHERE is_deleted = 0')
        .getSingle();
    final sessions = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM fronting_sessions '
          'WHERE is_deleted = 0 AND session_type = 0',
        )
        .getSingle();
    final convos = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM conversations WHERE is_deleted = 0',
        )
        .getSingle();
    final msgs = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM chat_messages WHERE is_deleted = 0',
        )
        .getSingle();
    final habits = await db
        .customSelect('SELECT COUNT(*) AS c FROM habits WHERE is_deleted = 0')
        .getSingle();

    return SyncCounts(
      members: members.read<int>('c'),
      frontingSessions: sessions.read<int>('c'),
      conversations: convos.read<int>('c'),
      messages: msgs.read<int>('c'),
      habits: habits.read<int>('c'),
    );
  }
}

final devicePairingProvider =
    NotifierProvider<DevicePairingNotifier, PairingState>(
      DevicePairingNotifier.new,
    );
