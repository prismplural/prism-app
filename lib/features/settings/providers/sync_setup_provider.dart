import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/crypto/bip39_english_wordlist.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/first_device_admission_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_bootstrap.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum SyncSetupStep { intro, enterPhrase }

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
  final bool isProcessing;
  final SyncSetupProgress? currentProgress;
  final String? error;

  const SyncSetupState({
    this.step = SyncSetupStep.intro,
    this.relayUrl = AppConstants.defaultRelayUrl,
    this.registrationToken,
    this.isProcessing = false,
    this.currentProgress,
    this.error,
  });

  SyncSetupState copyWith({
    SyncSetupStep? step,
    String? relayUrl,
    Object? registrationToken = _sentinel,
    bool? isProcessing,
    Object? currentProgress = _sentinel,
    Object? error = _sentinel,
  }) => SyncSetupState(
    step: step ?? this.step,
    relayUrl: relayUrl ?? this.relayUrl,
    registrationToken: registrationToken == _sentinel
        ? this.registrationToken
        : registrationToken as String?,
    isProcessing: isProcessing ?? this.isProcessing,
    currentProgress: currentProgress == _sentinel
        ? this.currentProgress
        : currentProgress as SyncSetupProgress?,
    error: error == _sentinel ? this.error : error as String?,
  );
}

class SyncSetupNotifier extends Notifier<SyncSetupState> {
  /// Handle created during [proceedToEnterPhrase] and reused in [_complete].
  ffi.PrismSyncHandle? _handle;

  @override
  SyncSetupState build() {
    const bakedToken = BuildInfo.betaRegistrationToken;
    return SyncSetupState(
      registrationToken: bakedToken.isEmpty ? null : bakedToken,
    );
  }

  void setRelayUrl(String url) {
    state = state.copyWith(relayUrl: url);
  }

  void setRegistrationToken(String? token) {
    state = state.copyWith(registrationToken: token);
  }

  /// Validate the relay URL, create the sync handle, and proceed to the
  /// enter-phrase step.
  Future<void> proceedToEnterPhrase() async {
    // Validate relay URL before proceeding. Match the joiner flow
    // (SyncDeviceStep): require https:// unless the host is a loopback
    // address, in which case plain http:// is allowed for local dev.
    final uri = Uri.tryParse(state.relayUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      state = state.copyWith(
        error: 'Invalid relay URL. Must be a valid http or https URL.',
      );
      return;
    }
    if (uri.scheme == 'http' && !_isLoopbackHost(uri.host)) {
      state = state.copyWith(
        error: 'Relay URL must use https://.',
      );
      return;
    }

    // Create the handle now so the phrase-verification step can use it.
    final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
    final handle = await handleNotifier.createHandle(relayUrl: state.relayUrl);
    _handle = handle;

    state = state.copyWith(
      step: SyncSetupStep.enterPhrase,
      error: null,
    );
  }

  void goBack() {
    switch (state.step) {
      case SyncSetupStep.intro:
        break;
      case SyncSetupStep.enterPhrase:
        _handle = null;
        state = state.copyWith(
          step: SyncSetupStep.intro,
          error: null,
        );
    }
  }

  /// Validate and submit the recovery phrase together with the user's PIN.
  ///
  /// Normalizes the mnemonic, checks that all 12 words are valid BIP39 words,
  /// then calls [ffi.unlock] to verify the phrase matches this account's key
  /// hierarchy. On success, proceeds to complete sync group creation.
  Future<bool> submitPhrase(String mnemonic, String pin) async {
    final normalized = PrismMnemonicField.normalize(mnemonic);
    final words = normalized.split(' ');

    // Validate 12 words, all in BIP39 wordlist.
    if (words.length != 12 || !words.every(bip39EnglishWordlistSet.contains)) {
      state = state.copyWith(
        error: 'Check that all 12 words are correct.',
      );
      return false;
    }

    final handle = _handle;
    if (handle == null) {
      state = state.copyWith(error: 'Setup handle not ready. Please go back and try again.');
      return false;
    }

    state = state.copyWith(isProcessing: true, error: null);

    // Derive secret key bytes from mnemonic and verify against this account.
    final Uint8List secretKeyBytes;
    try {
      secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: normalized);
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Check that all 12 words are correct.',
      );
      return false;
    }

    // If wrapped_dek exists, verify the phrase unlocks the existing key
    // hierarchy before creating a new sync group. After a sync reset,
    // wrapped_dek is gone — skip verification and go straight to createSyncGroup.
    final wrappedDek = await secureStorage.read(
      key: 'prism_sync.wrapped_dek',
    );
    if (wrappedDek != null) {
      try {
        await ffi.unlock(
          handle: handle,
          password: pin,
          secretKey: secretKeyBytes,
        );
      } catch (e) {
        state = state.copyWith(
          isProcessing: false,
          error: 'Incorrect PIN or recovery phrase. Check each word and try again.',
        );
        return false;
      }
    }

    return _complete(pin, normalized);
  }

  /// Complete sync group creation. Called from [submitPhrase] after the phrase
  /// has been verified.
  Future<bool> _complete(String pin, String mnemonic) async {
    final handle = _handle;
    if (handle == null) return false;

    // Snapshot keychain keys that may be written during setup so we can
    // restore them if setup fails partway through.
    const keychainKeys = [
      'prism_sync.wrapped_dek',
      'prism_sync.dek_salt',
      'prism_sync.device_secret',
      'prism_sync.device_id',
      'prism_sync.runtime_dek',
    ];
    final snapshot = <String, String?>{};
    for (final key in keychainKeys) {
      snapshot[key] = await secureStorage.read(key: key);
    }

    state = state.copyWith(
      isProcessing: true,
      currentProgress: SyncSetupProgress.creatingGroup,
      error: null,
    );

    try {
      final admissionService = FirstDeviceAdmissionService();
      await admissionService.preparePendingRegistration(
        handle: handle,
        relayUrl: state.relayUrl,
        registrationToken: state.registrationToken,
      );

      // createSyncGroup handles key hierarchy creation internally.
      // Pass the mnemonic so it uses the one the user entered (which they
      // already verified they have) rather than generating a new one.
      final inviteJson = await ffi.createSyncGroup(
        handle: handle,
        password: pin,
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
      await cacheRuntimeKeys(handle, ref.read(databaseProvider));

      // Bootstrap: push all existing data as record_create ops so the
      // relay has it for other devices to pull.
      state = state.copyWith(
        currentProgress: SyncSetupProgress.bootstrappingData,
      );
      await _bootstrapExistingData(handle);

      state = state.copyWith(isProcessing: false, currentProgress: null);
      return true;
    } catch (e) {
      final structuredError = PrismSyncStructuredError.tryParse(e);
      await _restoreKeychainSnapshot(snapshot);
      state = state.copyWith(
        isProcessing: false,
        currentProgress: null,
        error: 'Setup failed: ${_friendlySetupError(structuredError, e)}',
      );
      return false;
    }
  }

  /// Restore keychain keys from a previously taken snapshot.
  ///
  /// Used to roll back any partial writes from a failed setup attempt while
  /// preserving keys that existed before setup started.
  Future<void> _restoreKeychainSnapshot(Map<String, String?> snapshot) async {
    for (final entry in snapshot.entries) {
      try {
        if (entry.value != null) {
          await secureStorage.write(key: entry.key, value: entry.value!);
        } else {
          await secureStorage.delete(key: entry.key);
        }
      } catch (_) {
        // Best-effort restore — don't propagate errors
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
  /// to other devices. Data created before sync was enabled has no
  /// pending ops, so the pairing snapshot would otherwise miss it.
  Future<void> _bootstrapExistingData(ffi.PrismSyncHandle handle) async {
    final db = ref.read(databaseProvider);
    final adapter = ref.read(driftSyncAdapterProvider).adapter;

    await bootstrapExistingData(handle: handle, db: db, adapter: adapter);

    // Trigger an immediate sync to push the bootstrap data to the relay.
    //
    // UX follow-up (deferred, see Appendix B.3 of the 2026-04-11
    // sync-robustness plan): with the inner retry rewrite, `syncNow` now
    // throws `CoreError::Relay` on exhausted retries instead of burying
    // the error in the result JSON. This path only logs in debug mode; a
    // future improvement is to surface a `SyncSetupProgress.error` state
    // variant so the user can retry without restarting the onboarding
    // flow. The auto-sync driver will retry in the background
    // regardless, so data is never lost — only the bootstrap UX is
    // affected.
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

/// Returns true if [host] names a loopback address suitable for allowing
/// plain `http://` during first-device relay setup. Matches the joiner
/// flow's scheme rule with a carve-out for local dev relays.
bool _isLoopbackHost(String host) {
  if (host.isEmpty) return false;
  // Uri.host strips IPv6 brackets, so compare against the raw address form.
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
