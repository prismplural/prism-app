import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
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
  final String? sasWords;

  /// SAS decimal code displayed during relay-based pairing.
  final String? sasDecimal;

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
    this.sasDecimal,
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
    Object? sasDecimal = _sentinel,
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
      sasWords: sasWords == _sentinel ? this.sasWords : sasWords as String?,
      sasDecimal: sasDecimal == _sentinel
          ? this.sasDecimal
          : sasDecimal as String?,
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

  @override
  PairingState build() {
    _generation++;
    return const PairingState();
  }

  void reset() {
    _generation++;
    _pendingPin = null;
    _pairingRelayUrl = null;
    ref.read(syncSetupProgressProvider.notifier).reset();
    state = const PairingState();
  }

  /// Cancel any in-flight pairing attempt. Safe to call from UI when the
  /// user navigates away (e.g. leaveSyncDeviceFlow).
  void cancel() {
    _generation++;
    _pendingPin = null;
    _pairingRelayUrl = null;
    if (state.step == PairingStep.connecting) {
      state = const PairingState();
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
      entriesJson: jsonEncode({
        'registration_token': base64Encode(utf8.encode(registrationToken)),
      }),
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
      final sasWords = sasJson['sas_words'] as String;
      final sasDecimal = sasJson['sas_decimal'] as String;

      state = state.copyWith(
        step: PairingStep.showingSas,
        sasWords: sasWords,
        sasDecimal: sasDecimal,
      );
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      if (_generation != myGeneration) return;
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

    try {
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        throw StateError('No sync handle available');
      }

      if (_generation != myGeneration) return;

      // PHASE 1 — Ceremony (45 s hard timeout). Credentials are not yet
      // established, so a timeout here is safe to clean up the keychain.
      try {
        await pairingApi
            .completeJoinerCeremony(handle: handle, password: password)
            .timeout(const Duration(seconds: 45));
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
      }

      if (_generation != myGeneration) return;

      // PHASE 2+3 — bootstrap + apply. Own timeout boundaries live inside
      // _bootstrapAfterJoin / _runSnapshotBootstrap. Credentials may be
      // established by the time bootstrap starts, so those phases MUST NOT
      // wipe the keychain on timeout — they route to snapshotFailure
      // instead (see _runSnapshotBootstrap).
      await _bootstrapAfterJoin(handle, myGeneration);
    } catch (e) {
      _pendingPin = null;
      final structuredError = PrismSyncStructuredError.tryParse(e);
      // Only wipe creds here when we're still in the early ceremony /
      // pre-bootstrap region. Once _runSnapshotBootstrap is responsible
      // for its own credential lifecycle, it lands the user in
      // snapshotFailure rather than throwing back up here, so reaching
      // this catch block implies the failure happened BEFORE creds were
      // established.
      await _cleanupKeychainOnFailure();
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: structuredError?.userMessage ?? e.toString(),
        errorCode: structuredError?.code,
      );
    }
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

    await ffi.setAutoSync(
      handle: handle,
      enabled: true,
      debounceMs: BigInt.from(300),
      retryDelayMs: BigInt.from(30000),
      maxRetries: 3,
    );

    if (_generation != myGeneration) return;

    await _runSnapshotBootstrap(handle, myGeneration, progressNotifier);
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
        fatalSnapshotMessage = structuredError?.userMessage ?? e.toString();
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
      // Drain credentials so retry + cancel paths can read sync_id /
      // device_id / session_token from the keychain without needing the
      // Rust handle to survive. Best-effort; retry will re-enter the
      // bootstrap phase regardless.
      try {
        await drainRustStore(handle);
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

    // Snapshot applied cleanly — ACK so the relay drops it now rather
    // than waiting for TTL. Best-effort: errors here don't undo a good
    // pairing, and older relays respond 405 which the FFI folds to Ok.
    try {
      await ffi.acknowledgeSnapshotApplied(handle: handle);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'acknowledgeSnapshotApplied failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    // BOUNDARY 3: syncBatchComplete resolved — entering finishing phase.
    if (_generation == myGeneration) {
      progressNotifier.setPhase(PairingProgressPhase.finishing);
    }

    if (_generation != myGeneration) return;

    // Drain Rust credentials to platform keychain so they persist
    // across app restarts and the sync handle can auto-create.
    // Deferred until after all validation and cancellation checks so
    // partial credentials are never persisted on cancel.
    await drainRustStore(handle);

    // Also ensure relay_url and sync_id are written under the keys
    // that relayUrlProvider / syncIdProvider read from. drainRustStore
    // should already do this; these writes are a final defensive fallback.
    const storage = secureStorage;
    final syncId = await storage.read(key: kSyncIdKey);
    final storedRelay = await storage.read(key: kSyncRelayUrlKey);
    final relayUrl = _pairingRelayUrl ?? AppConstants.defaultRelayUrl;
    if (storedRelay == null || storedRelay.isEmpty) {
      await storage.write(
        key: kSyncRelayUrlKey,
        value: base64Encode(utf8.encode(relayUrl)),
      );
    }
    if (syncId == null || syncId.isEmpty) {
      // sync_id wasn't populated by drainRustStore — this shouldn't
      // normally happen but is guarded against defensively.
    }

    ref.invalidate(relayUrlProvider);
    ref.invalidate(syncIdProvider);

    // Cache raw DEK so subsequent launches bypass Argon2id (Signal-style)
    await cacheRuntimeKeys(handle, ref.read(databaseProvider));

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

    final counts = await _countLocalData();
    if (kDebugMode) {
      debugPrint(
        '[PAIRING] Local data counts: members=${counts.members}, sessions=${counts.frontingSessions}, convos=${counts.conversations}, messages=${counts.messages}, habits=${counts.habits}',
      );
    }
    state = state.copyWith(
      step: PairingStep.success,
      counts: counts,
      syncIncomplete: false,
    );
  }

  /// Wait for a strict-apply outcome while enforcing an idle (activity)
  /// watchdog. The watchdog resets on every `RemoteChanges` event observed
  /// on the sync event stream and on the coordinator's own batch-complete
  /// signal, so arbitrarily large snapshots can ingest as long as progress
  /// is visible; [idleTimeout] of silence is treated as failure.
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
            message:
                'TIMEOUT: no apply activity for ${idleTimeout.inSeconds}s',
            failedTables: const [],
          ),
        );
      });
    }

    // Start the watchdog immediately — if bootstrap already wrote rows to
    // Rust but the Dart stream never fires, we still want a deadline.
    resetWatchdog();

    // Observe every SyncEvent — RemoteChanges ticks reset the idle timer,
    // and SyncCompleted / WebSocket activity also count as progress.
    final subscription = ref.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (_, next) {
        next.whenData((event) {
          if (event.isRemoteChanges ||
              event.isSyncCompleted ||
              event.isWebSocketStateChanged) {
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
        errorMessage: structuredError?.userMessage ?? e.toString(),
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
    ref.read(syncSetupProgressProvider.notifier).reset();
    state = const PairingState();
  }

  Future<String?> _readDecodedSecureValue(String key) async {
    final raw = await secureStorage.read(key: key);
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
  Future<void> _cleanupKeychainOnFailure() async {
    const prefix = 'prism_sync.';
    // NOTE: database_key is intentionally NOT cleaned up here. It is a
    // local encryption key (Signal model) that must survive failed pairing
    // attempts — deleting it would make the encrypted local DB unreadable.
    const keysToClean = [
      '${prefix}wrapped_dek',
      '${prefix}dek_salt',
      '${prefix}device_secret',
      '${prefix}device_id',
      '${prefix}sync_id',
      '${prefix}session_token',
      '${prefix}epoch',
      '${prefix}relay_url',
      '${prefix}mnemonic',
      '${prefix}runtime_dek',
    ];
    for (final key in keysToClean) {
      try {
        await secureStorage.delete(key: key);
      } catch (_) {
        // Best-effort cleanup — don't propagate errors
      }
    }
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
