import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/first_device_admission_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum SyncSetupStep { intro, password, secretKey }

enum SyncSetupProgress {
  creatingGroup,
  configuringEngine,
  cachingKeys,
  bootstrappingData,
  syncing,
}

const _sentinel = Object();

class SyncSetupState {
  final SyncSetupStep step;
  final String relayUrl;
  final String? registrationToken;
  final String? password;
  final String? mnemonic;
  final bool isProcessing;
  final SyncSetupProgress? currentProgress;
  final String? error;

  const SyncSetupState({
    this.step = SyncSetupStep.intro,
    this.relayUrl = AppConstants.defaultRelayUrl,
    this.registrationToken,
    this.password,
    this.mnemonic,
    this.isProcessing = false,
    this.currentProgress,
    this.error,
  });

  SyncSetupState copyWith({
    SyncSetupStep? step,
    String? relayUrl,
    Object? registrationToken = _sentinel,
    Object? password = _sentinel,
    Object? mnemonic = _sentinel,
    bool? isProcessing,
    Object? currentProgress = _sentinel,
    Object? error = _sentinel,
  }) => SyncSetupState(
    step: step ?? this.step,
    relayUrl: relayUrl ?? this.relayUrl,
    registrationToken: registrationToken == _sentinel
        ? this.registrationToken
        : registrationToken as String?,
    password: password == _sentinel ? this.password : password as String?,
    mnemonic: mnemonic == _sentinel ? this.mnemonic : mnemonic as String?,
    isProcessing: isProcessing ?? this.isProcessing,
    currentProgress: currentProgress == _sentinel
        ? this.currentProgress
        : currentProgress as SyncSetupProgress?,
    error: error == _sentinel ? this.error : error as String?,
  );
}

class SyncSetupNotifier extends Notifier<SyncSetupState> {
  @override
  SyncSetupState build() => const SyncSetupState();

  void setRelayUrl(String url) {
    state = state.copyWith(relayUrl: url);
  }

  void setRegistrationToken(String? token) {
    state = state.copyWith(registrationToken: token);
  }

  void proceedToPassword() {
    // Validate relay URL before proceeding
    final uri = Uri.tryParse(state.relayUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      state = state.copyWith(
        error: 'Invalid relay URL. Must be a valid http or https URL.',
      );
      return;
    }
    state = state.copyWith(step: SyncSetupStep.password, error: null);
  }

  Future<void> proceedToSecretKey(String password) async {
    // Validate password is non-empty
    if (password.trim().isEmpty) {
      state = state.copyWith(error: 'Password cannot be empty.');
      return;
    }

    // Generate mnemonic via FFI
    final mnemonic = await ffi.generateSecretKey();
    state = state.copyWith(
      step: SyncSetupStep.secretKey,
      password: password,
      mnemonic: mnemonic,
      error: null,
    );
  }

  void goBack() {
    switch (state.step) {
      case SyncSetupStep.intro:
        break;
      case SyncSetupStep.password:
        state = state.copyWith(step: SyncSetupStep.intro, error: null);
      case SyncSetupStep.secretKey:
        state = state.copyWith(
          step: SyncSetupStep.password,
          mnemonic: null,
          error: null,
        );
    }
  }

  Future<bool> complete() async {
    final password = state.password;
    final mnemonic = state.mnemonic;
    if (password == null || mnemonic == null) return false;

    // Defense-in-depth: re-validate before FFI calls
    if (password.trim().isEmpty) {
      state = state.copyWith(error: 'Password cannot be empty.');
      return false;
    }
    final uri = Uri.tryParse(state.relayUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      state = state.copyWith(error: 'Invalid relay URL.');
      return false;
    }

    state = state.copyWith(
      isProcessing: true,
      currentProgress: SyncSetupProgress.creatingGroup,
      error: null,
    );

    try {
      final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
      final handle = await handleNotifier.createHandle(
        relayUrl: state.relayUrl,
      );
      final admissionService = FirstDeviceAdmissionService();
      await admissionService.preparePendingRegistration(
        handle: handle,
        relayUrl: state.relayUrl,
        registrationToken: state.registrationToken,
      );

      // createSyncGroup handles key hierarchy creation internally.
      // Pass the mnemonic so it uses the one shown to the user (which
      // they saved for recovery) rather than generating a different one.
      final inviteJson = await ffi.createSyncGroup(
        handle: handle,
        password: password,
        relayUrl: state.relayUrl,
        mnemonic: mnemonic,
      );

      // Parse the invite to extract sync_id and relay_url, then persist both
      // so relayUrlProvider and syncIdProvider survive app restarts.
      final invite = jsonDecode(inviteJson) as Map<String, dynamic>;
      final syncId = invite['sync_id'] as String;
      final persistedRelayUrl =
          (invite['relay_url'] as String?) ?? state.relayUrl;
      // Base64-encode before storing — seedRustStore expects base64
      await secureStorage.write(
        key: kSyncRelayUrlKey,
        value: base64Encode(utf8.encode(persistedRelayUrl)),
      );
      await secureStorage.write(
        key: kSyncIdKey,
        value: base64Encode(utf8.encode(syncId)),
      );
      ref.invalidate(relayUrlProvider);
      ref.invalidate(syncIdProvider);

      state = state.copyWith(
        currentProgress: SyncSetupProgress.configuringEngine,
      );
      await ffi.configureEngine(handle: handle);
      await ffi.setAutoSync(
        handle: handle,
        enabled: true,
        debounceMs: BigInt.from(300),
        retryDelayMs: BigInt.from(30000),
        maxRetries: 3,
      );

      // Drain Rust SecureStore back to platform keychain
      state = state.copyWith(currentProgress: SyncSetupProgress.cachingKeys);
      await drainRustStore(handle);

      // Cache raw DEK so subsequent launches bypass Argon2id (Signal-style)
      await cacheRuntimeKeys(handle);

      // Bootstrap: push all existing data as record_create ops so the
      // relay has it for other devices to pull.
      state = state.copyWith(
        currentProgress: SyncSetupProgress.bootstrappingData,
      );
      await _bootstrapExistingData(handle);

      ref.read(pendingMnemonicProvider.notifier).set(mnemonic);

      state = state.copyWith(isProcessing: false, currentProgress: null);
      return true;
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      await _cleanupKeychainOnFailure();
      state = state.copyWith(
        isProcessing: false,
        currentProgress: null,
        error: 'Setup failed: ${_friendlySetupError(structuredError, e)}',
      );
      return false;
    }
  }

  /// Remove any keychain keys that may have been written during a failed
  /// setup attempt so that partial credentials don't linger and confuse
  /// future startup logic.
  Future<void> _cleanupKeychainOnFailure() async {
    const prefix = 'prism_sync.';
    // NOTE: database_key is intentionally NOT cleaned up here. It is a
    // local encryption key (Signal model) that must survive failed sync
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
      '${prefix}sharing_prekey_store',
      '${prefix}sharing_id_cache',
      '${prefix}min_signature_version_floor',
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

  /// Map structured sync errors to user-friendly messages for the setup flow.
  String _friendlySetupError(
    PrismSyncStructuredError? structured,
    Object rawError,
  ) {
    if (structured != null) {
      final msg = structured.message.toLowerCase();

      // Unsupported first-device admission challenge (e.g., PoW version mismatch)
      if (msg.contains('unsupported') &&
          msg.contains('first-device admission')) {
        return "Your app version doesn't support this relay's security "
            'requirements. Please update the app.';
      }

      // Rate limiting on registration
      if (msg.contains('registration failed') &&
          (msg.contains('rate limit') || structured.status == 429)) {
        return 'Too many registration attempts. Please wait and try again.';
      }

      // Generic relay / network errors
      if (structured.errorType == 'relay' || structured.relayKind != null) {
        return 'Could not connect to relay server. Check your internet '
            'connection and relay URL.';
      }

      // Fall back to the structured user message
      return structured.userMessage;
    }

    // No structured error — check for common network patterns
    final raw = rawError.toString().toLowerCase();
    if (raw.contains('socketexception') ||
        raw.contains('connection refused') ||
        raw.contains('timed out')) {
      return 'Could not connect to relay server. Check your internet '
          'connection and relay URL.';
    }

    return rawError.toString();
  }

  /// Push all existing local data to the sync engine so it gets synced
  /// to other devices. This is needed because data created before sync
  /// was enabled has no pending ops.
  Future<void> _bootstrapExistingData(ffi.PrismSyncHandle handle) async {
    final db = ref.read(databaseProvider);

    final tables = <String, Future<List<dynamic>> Function()>{
      'members': () => db.select(db.members).get(),
      'fronting_sessions': () => db.select(db.frontingSessions).get(),
      'conversations': () => db.select(db.conversations).get(),
      'chat_messages': () => db.select(db.chatMessages).get(),
      'system_settings': () => db.select(db.systemSettingsTable).get(),
      'polls': () => db.select(db.polls).get(),
      'poll_options': () => db.select(db.pollOptions).get(),
      'poll_votes': () => db.select(db.pollVotes).get(),
      'habits': () => db.select(db.habits).get(),
      'habit_completions': () => db.select(db.habitCompletions).get(),
    };

    final adapter = ref.read(driftSyncAdapterProvider).adapter;
    var totalOps = 0;

    for (final entry in tables.entries) {
      final tableName = entry.key;
      final entity = adapter.entityForTable(tableName);
      if (entity == null) continue;

      final rows = await entry.value();
      for (final row in rows) {
        try {
          final fields = entity.toSyncFields(row);
          // Extract the id from the row — all entity tables have an 'id' field
          final id = (row as dynamic).id as String;
          await ffi.recordCreate(
            handle: handle,
            table: tableName,
            entityId: id,
            fieldsJson: jsonEncode(fields),
          );
          totalOps++;
        } catch (e) {
          if (kDebugMode) debugPrint('[BOOTSTRAP] Failed to push $tableName row: $e');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('[BOOTSTRAP] Pushed $totalOps existing records to sync engine');
    }

    // Trigger an immediate sync to push the bootstrap data to the relay
    state = state.copyWith(currentProgress: SyncSetupProgress.syncing);
    try {
      final result = await ffi.syncNow(handle: handle);
      if (kDebugMode) debugPrint('[BOOTSTRAP] syncNow result: $result');
    } catch (e) {
      if (kDebugMode) debugPrint('[BOOTSTRAP] syncNow failed: $e');
    }
  }
}

final syncSetupProvider = NotifierProvider<SyncSetupNotifier, SyncSetupState>(
  SyncSetupNotifier.new,
);
