import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/pairing_sas_display.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
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
    _pendingPin = null;
    _pairingRelayUrl = null;
    _activeCeremonyHandle = null;
    ref.read(syncSetupProgressProvider.notifier).reset();
    state = const PairingState();
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
        errorMessage: structuredError?.userMessage ?? e.toString(),
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
    syncAdapter.beginSyncBatch();

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
        // PHASE 3 — Dart-side apply. Activity watchdog: 60 s of silence
        // is treated as failure, but each RemoteChanges / batch-complete
        // tick resets the timer, so arbitrarily large snapshots still
        // succeed as long as progress is visible. The watchdog writes
        // failure into the strict-apply latch, so the single awaiter
        // below observes whichever event fired first.
        final applyOutcome = await _awaitApplyOutcomeWithWatchdog(
          handle: handle,
          outcomeFuture: outcomeFuture,
          idleTimeout: const Duration(seconds: 60),
        );

        switch (applyOutcome) {
          case ApplyOutcomeSuccess():
            // fall through to post-bootstrap work
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
    try {
      await _runPostBootstrapCatchUp(handle);
    } on TimeoutException catch (e, st) {
      syncIncomplete = true;
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
      ErrorReportingService.instance.report(
        'Post-pairing catch-up failed after snapshot apply '
        '(non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    if (_generation != myGeneration) return;

    // Snapshot apply succeeded. ACK now so the relay can discard the retained
    // bootstrap snapshot; transient catch-up failures above do not need a
    // snapshot retry because the restored baseline is already local.
    // Best-effort: errors here don't undo a good pairing, and older relays
    // respond 405 which the FFI folds to Ok.
    try {
      await ffi.acknowledgeSnapshotApplied(handle: handle);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'acknowledgeSnapshotApplied failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
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
  }

  @visibleForTesting
  Future<void> writeSnapshotApplyCompleteMarkerForTest() {
    return _writeSnapshotApplyCompleteMarker();
  }

  /// Wait for a strict-apply outcome while enforcing an idle (activity)
  /// watchdog. The watchdog only resets on `RemoteChanges` events — the
  /// single sync-event variant that represents actual apply progress.
  /// `SyncCompleted` and `WebSocketStateChanged` are intentionally NOT
  /// treated as progress: they can fire from auto-sync completions or
  /// reconnect churn while an apply handler is stuck inside `asyncMap`,
  /// which would mask a real hang indefinitely.
  ///
  /// Arbitrarily large snapshots still succeed as long as `RemoteChanges`
  /// keeps firing; [idleTimeout] of silence is treated as failure.
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
    // Rust but the Dart stream never fires, we still want a deadline.
    resetWatchdog();

    // Only RemoteChanges events represent actual apply progress. See
    // doc-comment above for why SyncCompleted / WebSocketStateChanged
    // are excluded.
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
