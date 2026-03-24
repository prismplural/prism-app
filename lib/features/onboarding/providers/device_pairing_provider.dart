import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum PairingStep {
  // User enters a URL or invite string to join
  enterUrl,
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
  final String? url;
  final String? errorMessage;
  final SyncCounts? counts;

  /// When true, the initial data sync timed out and some data may still be
  /// arriving in the background. The pairing itself succeeded, but the user
  /// should be informed that not all data may be visible yet.
  final bool syncIncomplete;

  const PairingState({
    this.step = PairingStep.enterUrl,
    this.url,
    this.errorMessage,
    this.counts,
    this.syncIncomplete = false,
  });

  PairingState copyWith({
    PairingStep? step,
    Object? url = _sentinel,
    Object? errorMessage = _sentinel,
    Object? counts = _sentinel,
    bool? syncIncomplete,
  }) {
    return PairingState(
      step: step ?? this.step,
      url: url == _sentinel ? this.url : url as String?,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
      counts: counts == _sentinel ? this.counts : counts as SyncCounts?,
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

  void setUrl(String url) {
    state = state.copyWith(url: url, step: PairingStep.enterPassword);
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

  Future<void> connect(String password) async {
    final url = state.url;
    if (url == null || url.isEmpty) {
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: 'No invite URL provided.',
      );
      return;
    }

    // Validate password is non-empty
    if (password.trim().isEmpty) {
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: 'Password cannot be empty.',
      );
      return;
    }

    _generation++;
    final myGeneration = _generation;
    state = state.copyWith(step: PairingStep.connecting, errorMessage: null);

    try {
      await _connectWithTimeout(url, password, myGeneration);
    } on TimeoutException {
      await _cleanupKeychainOnFailure();
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage:
            'Connection timed out. Check your internet connection and try again.',
      );
    } catch (e) {
      await _cleanupKeychainOnFailure();
      if (_generation != myGeneration) return;
      state = state.copyWith(
        step: PairingStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _connectWithTimeout(
    String url,
    String password,
    int myGeneration,
  ) async {
    // 60s timeout so the user isn't stuck on the spinner indefinitely.
    await Future(() async {
      // Get or create the FFI handle. Use the app's configured relay URL
      // (or the default) since the real relay URL is embedded in the invite
      // and Rust extracts it internally during joinFromUrl.
      final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
      final relayUrl =
          await ref.read(relayUrlProvider.future) ??
          AppConstants.defaultRelayUrl;
      final handle = await handleNotifier.createHandle(relayUrl: relayUrl);

      if (_generation != myGeneration) return;

      await ffi.joinFromUrl(handle: handle, url: url, password: password);

      if (_generation != myGeneration) return;

      await ffi.configureEngine(handle: handle);
      await ffi.setAutoSync(
        handle: handle,
        enabled: true,
        debounceMs: BigInt.from(300),
        retryDelayMs: BigInt.from(30000),
        maxRetries: 3,
      );

      if (_generation != myGeneration) return;

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
      await syncAdapter.syncBatchComplete
          .timeout(const Duration(seconds: 10), onTimeout: () {
        syncTimedOut = true;
        if (kDebugMode) {
          print('[PAIRING] syncBatchComplete timed out — continuing with incomplete data');
        }
      });

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
    }).timeout(const Duration(seconds: 60));
  }

  /// Remove any keychain keys that may have been written during a failed
  /// pairing attempt (via drainRustStore / cacheRuntimeKeys) so that
  /// partial credentials don't linger and confuse future startup logic.
  Future<void> _cleanupKeychainOnFailure() async {
    const prefix = 'prism_sync.';
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
      '${prefix}database_key',
      '${prefix}database_encrypted',
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
          'SELECT COUNT(*) AS c FROM fronting_sessions WHERE is_deleted = 0',
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
