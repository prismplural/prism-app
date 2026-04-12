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
  // User enters the sync password
  enterPassword,
  // Connecting to the relay / performing the join
  connecting,
  // Successfully joined
  success,
  // An error occurred
  error,
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

  @override
  PairingState build() {
    _generation++;
    return const PairingState();
  }

  void reset() {
    _generation++;
    state = const PairingState();
  }

  /// Cancel any in-flight pairing attempt. Safe to call from UI when the
  /// user navigates away (e.g. leaveSyncDeviceFlow).
  void cancel() {
    _generation++;
    if (state.step == PairingStep.connecting) {
      state = const PairingState();
    }
  }

  /// Generate a rendezvous token QR for the joiner-initiated relay ceremony.
  /// The joiner displays this QR for an existing device to scan.
  Future<void> generateRequest() async {
    _generation++;
    final myGeneration = _generation;

    try {
      final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      final relayUrl =
          await ref.read(relayUrlProvider.future) ??
          AppConstants.defaultRelayUrl;
      final handle = await handleNotifier.createHandle(relayUrl: relayUrl);

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
      _waitForSas(handle, myGeneration);
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
      step: PairingStep.enterPassword,
      errorMessage: null,
      errorCode: null,
    );
  }

  /// Complete the joiner ceremony with the user's PIN (6-digit).
  ///
  /// Delegates to [completeJoinerWithPassword] — PIN is used as the sync
  /// auth password, matching the onboarding flow where the PIN is the
  /// Argon2id password for key derivation.
  Future<void> completeJoinerWithPin(String pin) =>
      completeJoinerWithPassword(pin);

  /// Complete the joiner ceremony with the user's password.
  Future<void> completeJoinerWithPassword(String password) async {
    if (password.trim().isEmpty) {
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: 'Password cannot be empty.',
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
      await Future(() async {
        final handle = ref.read(prismSyncHandleProvider).value;
        if (handle == null) {
          throw StateError('No sync handle available');
        }

        if (_generation != myGeneration) return;

        await pairingApi.completeJoinerCeremony(
          handle: handle,
          password: password,
        );

        if (_generation != myGeneration) return;

        await _bootstrapAfterJoin(handle, myGeneration);
      }).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      await _cleanupKeychainOnFailure();
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage:
            'Connection timed out. Check your internet connection and try again.',
        errorCode: null,
      );
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
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
    await ffi.configureEngine(handle: handle);
    await ffi.setAutoSync(
      handle: handle,
      enabled: true,
      debounceMs: BigInt.from(300),
      retryDelayMs: BigInt.from(30000),
      maxRetries: 3,
    );

    if (_generation != myGeneration) return;

    final relayUrl =
        await ref.read(relayUrlProvider.future) ?? AppConstants.defaultRelayUrl;

    // Also ensure relay_url and sync_id are written under the keys
    // that relayUrlProvider / syncIdProvider read from (drainRustStore
    // already writes them with the matching prefix, but we verify).
    const storage = secureStorage;
    final syncId = await storage.read(key: kSyncIdKey);
    final storedRelay = await storage.read(key: kSyncRelayUrlKey);
    // If drainRustStore didn't populate them (edge case), write defaults.
    // Must base64-encode to match what _seedRustStore and relayUrlProvider expect.
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

    // Activate the sync event stream BEFORE bootstrap so RemoteChanges
    // events from bootstrapFromSnapshot are consumed as they arrive.
    // Without this, the bootstrap emits entities to Rust's broadcast
    // channel but nothing on the Dart side processes them into Drift.
    if (kDebugMode) {
      print('[PAIRING] Activating syncEventStreamProvider...');
    }
    final syncAdapter = ref.read(driftSyncAdapterProvider);
    syncAdapter.beginSyncBatch();
    ref.listen(syncEventStreamProvider, (prev, next) {
      if (kDebugMode) {
        print(
          '[PAIRING] syncEventStream event: prev=$prev, next=${next.value?.type ?? next.error}',
        );
      }
    });

    // Try to bootstrap from ephemeral snapshot (fast path for new device)
    try {
      final restored = await ffi.bootstrapFromSnapshot(handle: handle);
      if (kDebugMode && restored > BigInt.zero) {
        debugPrint('[PAIRING] Bootstrapped $restored entities from snapshot');
      }
    } catch (e, stackTrace) {
      // Non-fatal — will sync incrementally
      if (kDebugMode) {
        debugPrint('[PAIRING] Snapshot bootstrap failed (non-fatal): $e');
      }
      ErrorReportingService.instance.report(
        'Snapshot bootstrap failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: stackTrace,
      );
    }

    // Pull any changes that arrived after the snapshot was created
    try {
      if (kDebugMode) {
        print('[PAIRING] Calling syncNow...');
      }
      final syncResult = await ffi.syncNow(handle: handle);
      if (kDebugMode) {
        print('[PAIRING] syncNow result: $syncResult');
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Pairing syncNow failed (non-fatal): $e',
        severity: ErrorSeverity.warning,
        stackTrace: st,
      );
    }

    // Wait for ALL remote changes (from both bootstrap and syncNow)
    // to finish being applied to the Drift database. The batch was
    // started before the bootstrap, so it captures everything.
    var syncTimedOut = false;
    await syncAdapter.syncBatchComplete.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        syncTimedOut = true;
        if (kDebugMode) {
          print(
            '[PAIRING] syncBatchComplete timed out — continuing with incomplete data',
          );
        }
      },
    );

    if (_generation != myGeneration) return;

    // Drain Rust credentials to platform keychain so they persist
    // across app restarts and the sync handle can auto-create.
    // Deferred until after all validation and cancellation checks so
    // partial credentials are never persisted on cancel.
    await drainRustStore(handle);

    // Cache raw DEK so subsequent launches bypass Argon2id (Signal-style)
    await cacheRuntimeKeys(handle);

    final counts = await _countLocalData();
    if (kDebugMode) {
      print(
        '[PAIRING] Local data counts: members=${counts.members}, sessions=${counts.frontingSessions}, convos=${counts.conversations}, messages=${counts.messages}, habits=${counts.habits}',
      );
    }
    state = state.copyWith(
      step: PairingStep.success,
      counts: counts,
      syncIncomplete: syncTimedOut,
    );
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
    // Guard: don't mark onboarding complete if no members exist yet.
    // This prevents Device B from skipping onboarding when the CRDT-synced
    // hasCompletedOnboarding flag arrives before member data.
    final memberRepo = ref.read(memberRepositoryProvider);
    final members = await memberRepo.getAllMembers();
    if (members.isEmpty) return;

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
