import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum OnboardingStep {
  welcome,
  pinSetup,        // 6-digit PIN creation
  recoveryPhrase,  // Show 12-word backup + save confirmation
  biometricSetup,  // Face ID / Touch ID opt-in
  syncDevice,
  importedDataReady,
  importData,
  systemName,
  addMembers,
  features,
  chatSetup,
  preferences,
  permissions,
  whosFronting,
  complete;

  String get title => switch (this) {
    welcome => 'Welcome to Prism',
    pinSetup => 'Set your PIN',
    recoveryPhrase => 'Save your recovery phrase',
    biometricSetup => 'Enable biometrics',
    syncDevice => 'Sync From Device',
    importedDataReady => 'Data Ready',
    importData => 'Already have data?',
    systemName => 'Name your system',
    addMembers => "Who's here?",
    features => 'Pick your tools',
    chatSetup => 'Set up chat',
    preferences => 'Make it yours',
    permissions => 'One more thing',
    whosFronting => "Who's fronting?",
    complete => 'Ready when you are',
  };

  String get subtitle => switch (this) {
    welcome => 'Your system, your way.',
    pinSetup => 'Protects your app and sync.',
    recoveryPhrase => 'Write these 12 words somewhere safe.',
    biometricSetup => 'Use Face ID or Touch ID to unlock.',
    syncDevice => 'Pair with an existing device',
    importedDataReady => 'Your imported system is ready to use',
    importData => 'Bring your system with you.',
    systemName => 'Whatever feels right.',
    addMembers => 'Add the people in your system.',
    features => 'Turn on what you need. Change anytime.',
    chatSetup => 'Channels for your system to talk.',
    preferences => 'Colors, language, the small things.',
    permissions => 'Optional permissions for the best experience.',
    whosFronting => "Tap whoever's here right now.",
    complete => "Your system is set up. Here's what to explore.",
  };

  IconData get icon => switch (this) {
    welcome => AppIcons.duotoneStar,
    pinSetup => AppIcons.duotoneLock,
    recoveryPhrase => AppIcons.duotoneKey,
    biometricSetup => AppIcons.fingerprint,
    syncDevice => AppIcons.duotoneSync,
    importedDataReady => AppIcons.duotoneSuccess,
    importData => AppIcons.duotoneImport,
    systemName => AppIcons.label,
    addMembers => AppIcons.duotoneMembers,
    features => AppIcons.duotoneSettings,
    chatSetup => AppIcons.duotoneChat,
    preferences => AppIcons.duotoneTheme,
    permissions => AppIcons.duotoneNotifications,
    whosFronting => AppIcons.duotoneFronting,
    complete => AppIcons.duotoneSuccess,
  };

}

class OnboardingState {
  final OnboardingStep currentStep;
  final String systemName;
  final Map<String, String> selectedChannels;
  final String customChannelName;
  final SystemTerminology selectedTerminology;
  final String accentColorHex;
  final bool usePerMemberColors;
  final bool chatEnabled;
  final bool pollsEnabled;
  final bool habitsEnabled;
  final bool sleepTrackingEnabled;
  final String? selectedFronterId;
  final bool wasImportedFromPluralKit;
  final OnboardingDataCounts? importedDataCounts;
  final String? customTermSingular;
  final String? customTermPlural;
  final bool terminologyUseEnglish;
  final bool isSyncPath;
  /// The channel key that cannot be removed (locale-aware "All Members" name).
  /// Null until ChatSetupStep seeds the localized defaults on first render.
  final String? allMembersChannelKey;
  /// The 12-word mnemonic words generated during PIN setup. Ephemeral —
  /// kept in memory only until the biometric step completes or is skipped.
  final List<String> mnemonicWords;
  /// The raw DEK bytes exported after initialize(). Used for biometric
  /// enrollment in BiometricSetupStep. Cleared after biometric step.
  final Uint8List? dekBytes;

  const OnboardingState({
    this.currentStep = OnboardingStep.welcome,
    this.systemName = '',
    this.selectedChannels = const {},
    this.customChannelName = '',
    this.selectedTerminology = SystemTerminology.headmates,
    this.accentColorHex = '#AF8EE9',
    this.usePerMemberColors = true,
    this.chatEnabled = true,
    this.pollsEnabled = true,
    this.habitsEnabled = true,
    this.sleepTrackingEnabled = true,
    this.selectedFronterId,
    this.wasImportedFromPluralKit = false,
    this.importedDataCounts,
    this.customTermSingular,
    this.customTermPlural,
    this.terminologyUseEnglish = false,
    this.isSyncPath = false,
    this.allMembersChannelKey,
    this.mnemonicWords = const [],
    this.dekBytes,
  });

  static const _sentinel = Object();

  OnboardingState copyWith({
    OnboardingStep? currentStep,
    String? systemName,
    Map<String, String>? selectedChannels,
    String? customChannelName,
    SystemTerminology? selectedTerminology,
    String? accentColorHex,
    bool? usePerMemberColors,
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
    String? selectedFronterId,
    bool? wasImportedFromPluralKit,
    Object? importedDataCounts = _sentinel,
    Object? customTermSingular = _sentinel,
    Object? customTermPlural = _sentinel,
    bool? terminologyUseEnglish,
    bool? isSyncPath,
    bool clearFronterId = false,
    String? allMembersChannelKey,
    List<String>? mnemonicWords,
    Object? dekBytes = _sentinel,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      systemName: systemName ?? this.systemName,
      selectedChannels: selectedChannels ?? this.selectedChannels,
      customChannelName: customChannelName ?? this.customChannelName,
      selectedTerminology: selectedTerminology ?? this.selectedTerminology,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      usePerMemberColors: usePerMemberColors ?? this.usePerMemberColors,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      pollsEnabled: pollsEnabled ?? this.pollsEnabled,
      habitsEnabled: habitsEnabled ?? this.habitsEnabled,
      sleepTrackingEnabled: sleepTrackingEnabled ?? this.sleepTrackingEnabled,
      selectedFronterId: clearFronterId
          ? null
          : (selectedFronterId ?? this.selectedFronterId),
      wasImportedFromPluralKit:
          wasImportedFromPluralKit ?? this.wasImportedFromPluralKit,
      importedDataCounts: importedDataCounts == _sentinel
          ? this.importedDataCounts
          : importedDataCounts as OnboardingDataCounts?,
      customTermSingular: customTermSingular == _sentinel
          ? this.customTermSingular
          : customTermSingular as String?,
      customTermPlural: customTermPlural == _sentinel
          ? this.customTermPlural
          : customTermPlural as String?,
      terminologyUseEnglish:
          terminologyUseEnglish ?? this.terminologyUseEnglish,
      isSyncPath: isSyncPath ?? this.isSyncPath,
      allMembersChannelKey: allMembersChannelKey ?? this.allMembersChannelKey,
      mnemonicWords: mnemonicWords ?? this.mnemonicWords,
      dekBytes: dekBytes == _sentinel ? this.dekBytes : dekBytes as Uint8List?,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  static const _defaultMembers =
      <({String name, String pronouns, String emoji})>[
        (name: 'Zari', pronouns: 'they/she', emoji: '\u2728'),
        (name: 'Ethan', pronouns: 'he/him', emoji: '\u26AB\uFE0F'),
        (name: 'Aimee', pronouns: 'she/her', emoji: '\u{1F31F}'),
        (name: 'Melanie', pronouns: 'she/her', emoji: '\u{1F496}'),
        (name: 'Christopher', pronouns: 'he/him', emoji: '\u26D3\uFE0F'),
        (name: 'Raine', pronouns: 'she/her', emoji: '\u{1F33A}'),
        (name: 'Aria', pronouns: 'she/her', emoji: '\u{1F48E}'),
        (name: 'Flux', pronouns: 'it/its', emoji: '\u{1F300}'),
      ];

  @override
  OnboardingState build() => const OnboardingState();

  /// Enter the sync-from-device pairing flow directly from the welcome step,
  /// skipping PIN setup and recovery phrase. The PIN entered during pairing
  /// becomes the app lock PIN.
  void enterSyncDeviceFlowFromWelcome() {
    state = state.copyWith(
      isSyncPath: true,
      currentStep: OnboardingStep.syncDevice,
    );
  }

  /// Leave the sync-from-device flow. Returns to the welcome step.
  /// Cancels any in-flight pairing attempt before invalidating.
  void leaveSyncDeviceFlow() {
    ref.read(devicePairingProvider.notifier).cancel();
    ref.invalidate(devicePairingProvider);
    state = state.copyWith(
      isSyncPath: false,
      currentStep: OnboardingStep.welcome,
    );
  }

  // ---------------------------------------------------------------------------
  // PIN / recovery phrase / biometric step handlers
  // ---------------------------------------------------------------------------

  /// Called when the user confirms their 6-digit PIN in [PinSetupStep].
  ///
  /// This is the master key-derivation step:
  /// 1. Generates a fresh BIP39 mnemonic via FFI.
  /// 2. Converts the mnemonic to secret-key bytes.
  /// 3. Calls `ffi.initialize()` — derives MEK, wraps DEK, creates device keys.
  /// 4. Drains Rust's MemorySecureStore to the platform keychain.
  /// 5. Writes the mnemonic to the keychain explicitly (Rust never does this).
  /// 6. Caches the runtime DEK (`kRuntimeDekKey`) for Signal-style fast unlock.
  /// 7. Stores the PIN hash via [PinLockService].
  /// 8. Advances to [OnboardingStep.recoveryPhrase].
  Future<void> onPinConfirmed(String pin) async {
    try {
      // 1. Get or create the sync handle (we need it for FFI calls).
      //    In new-device onboarding, no handle exists yet. We create one
      //    using the default relay URL — createSyncGroup will be called later.
      final handleNotifier = ref.read(prismSyncHandleProvider.notifier);
      ffi.PrismSyncHandle handle;
      final existingHandle = ref.read(prismSyncHandleProvider).value;
      if (existingHandle != null) {
        handle = existingHandle;
      } else {
        handle = await handleNotifier.createHandle(
          relayUrl: AppConstants.defaultRelayUrl,
        );
      }

      // 2. Generate mnemonic (returns the 12-word string).
      final mnemonic = await ffi.generateSecretKey();
      final mnemonicWords = mnemonic.split(' ');

      // 3. Convert mnemonic phrase to secret-key bytes.
      final secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonic);

      // 4. Initialize the key hierarchy: PIN is the password, secretKey
      //    is the BIP39 entropy. This derives MEK → DEK → device keys.
      await ffi.initialize(
        handle: handle,
        password: pin,
        secretKey: secretKeyBytes,
      );

      // 5. Drain Rust's MemorySecureStore to the platform keychain
      //    (writes wrapped_dek, dek_salt, device_secret, device_id, etc.).
      await drainRustStore(handle);

      // 6. Write mnemonic to keychain explicitly. Rust initialize() does NOT
      //    write it — we are the only writer. The key format matches
      //    attemptUnlock() which reads `prism_sync.mnemonic` as
      //    base64(utf8(mnemonic_string)).
      await secureStorage.write(
        key: 'prism_sync.mnemonic',
        value: base64Encode(utf8.encode(mnemonic)),
      );

      // 7. Export raw DEK and cache it (Signal-style: bypasses Argon2id on
      //    next launch). Also derives and caches the database key.
      await cacheRuntimeKeys(handle, ref.read(databaseProvider));
      final dekBytes = await ffi.exportDek(handle: handle);

      // 8. PIN hash already stored by PinSetupStep.onPinEntered before
      //    calling onPinConfirmed — no second storePin() call here.

      // 9. Also use the PIN as the sync auth password — record it in the
      //    pendingMnemonicProvider so the secret-key screen can show it if
      //    needed (not required here, but keeps state consistent).
      ref.read(pendingMnemonicProvider.notifier).set(mnemonic);

      // 10. Store words and DEK in ephemeral state, advance step.
      state = state.copyWith(
        mnemonicWords: mnemonicWords,
        dekBytes: dekBytes,
        currentStep: OnboardingStep.recoveryPhrase,
      );
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'onPinConfirmed failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      if (kDebugMode) debugPrint('[ONBOARDING] onPinConfirmed error: $e');
      rethrow;
    }
  }

  /// Called when the user confirms they have saved their recovery phrase.
  void onPhraseSaved() {
    state = state.copyWith(currentStep: OnboardingStep.biometricSetup);
  }

  /// Called when the user successfully enrolls biometrics.
  void onBiometricEnrolled() {
    // Clear sensitive ephemeral fields and advance.
    state = state.copyWith(
      mnemonicWords: [],
      dekBytes: null,
      currentStep: OnboardingStep.importData,
    );
  }

  /// Called when the user skips the biometric enrollment step.
  void onBiometricSkipped() {
    // Clear sensitive ephemeral fields and advance.
    state = state.copyWith(
      mnemonicWords: [],
      dekBytes: null,
      currentStep: OnboardingStep.importData,
    );
  }

  bool _shouldSkip(OnboardingStep step) {
    if (step == OnboardingStep.syncDevice && !state.isSyncPath) return true;
    if (step == OnboardingStep.importedDataReady &&
        state.importedDataCounts == null) {
      return true;
    }
    if (step == OnboardingStep.chatSetup && !state.chatEnabled) return true;
    // biometricSetup can only be skipped if needed (user can see it regardless)
    return false;
  }

  void next() {
    const steps = OnboardingStep.values;
    final currentIndex = steps.indexOf(state.currentStep);
    if (currentIndex < steps.length - 1) {
      var nextIndex = currentIndex + 1;
      while (nextIndex < steps.length && _shouldSkip(steps[nextIndex])) {
        nextIndex++;
      }
      if (nextIndex < steps.length) {
        state = state.copyWith(currentStep: steps[nextIndex]);
      }
    }
  }

  void back() {
    const steps = OnboardingStep.values;
    final currentIndex = steps.indexOf(state.currentStep);
    if (currentIndex > 0) {
      var prevIndex = currentIndex - 1;
      while (prevIndex >= 0 && _shouldSkip(steps[prevIndex])) {
        prevIndex--;
      }
      if (prevIndex >= 0) {
        state = state.copyWith(currentStep: steps[prevIndex]);
      }
    }
  }

  bool get canProceed {
    return switch (state.currentStep) {
      OnboardingStep.welcome => true,
      // PIN/recovery/biometric steps manage their own progression —
      // the bottom "Continue" button is hidden for these steps.
      OnboardingStep.pinSetup => false,
      OnboardingStep.recoveryPhrase => false,
      OnboardingStep.biometricSetup => false,
      OnboardingStep.syncDevice => false, // Managed by SyncDeviceStep itself
      OnboardingStep.importedDataReady => false,
      OnboardingStep.importData => true,
      OnboardingStep.systemName => state.systemName.trim().isNotEmpty,
      OnboardingStep.addMembers => true,
      OnboardingStep.features => true,
      OnboardingStep.chatSetup => true,
      OnboardingStep.preferences => true,
      OnboardingStep.permissions => true,
      OnboardingStep.whosFronting => true,
      OnboardingStep.complete => true,
    };
  }

  void setSystemName(String name) {
    state = state.copyWith(systemName: name);
  }

  void setSelectedFronter(String? memberId) {
    if (memberId == state.selectedFronterId) {
      state = state.copyWith(clearFronterId: true);
    } else {
      state = state.copyWith(selectedFronterId: memberId);
    }
  }

  void setWasImportedFromPluralKit(bool value) {
    state = state.copyWith(wasImportedFromPluralKit: value);
  }

  void showImportedDataReady(OnboardingDataCounts counts) {
    state = state.copyWith(
      importedDataCounts: counts,
      currentStep: OnboardingStep.importedDataReady,
    );
  }

  Future<void> addDefaultMembers() async {
    try {
      final notifier = ref.read(membersNotifierProvider.notifier);
      for (final member in _defaultMembers) {
        await notifier.createMember(
          name: member.name,
          pronouns: member.pronouns,
          emoji: member.emoji,
        );
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Failed to add default members during onboarding: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> createMember({
    required String name,
    String? pronouns,
    String emoji = '\u{1F464}',
    int? age,
    String? bio,
    Uint8List? avatarImageData,
  }) async {
    try {
      await ref
          .read(membersNotifierProvider.notifier)
          .createMember(
            name: name,
            pronouns: pronouns,
            emoji: emoji,
            age: age,
            bio: bio,
            avatarImageData: avatarImageData,
          );
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Failed to create member "$name" during onboarding: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> deleteMember(String memberId) async {
    try {
      await ref.read(membersNotifierProvider.notifier).deleteMember(memberId);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Failed to delete member "$memberId" during onboarding: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      rethrow;
    }
  }

  void seedDefaultChannels({
    required String allMembersName,
    required String ventingName,
  }) {
    // Only seed if channels haven't been initialized yet.
    if (state.allMembersChannelKey != null) return;
    state = state.copyWith(
      selectedChannels: {
        allMembersName: '\u{1F465}',
        ventingName: '\u{1F62E}\u200D\u{1F4A8}',
      },
      allMembersChannelKey: allMembersName,
    );
  }

  void toggleChannel(String name, String emoji) {
    final updated = Map<String, String>.from(state.selectedChannels);
    if (updated.containsKey(name)) {
      // Don't allow removing the protected "All Members" channel.
      if (name != state.allMembersChannelKey) {
        updated.remove(name);
      }
    } else {
      updated[name] = emoji;
    }
    state = state.copyWith(selectedChannels: updated);
  }

  void addCustomChannel(String name, String emoji) {
    if (name.trim().isEmpty) return;
    final updated = Map<String, String>.from(state.selectedChannels);
    updated[name.trim()] = emoji;
    state = state.copyWith(selectedChannels: updated, customChannelName: '');
  }

  void setCustomChannelName(String name) {
    state = state.copyWith(customChannelName: name);
  }

  void setTerminology(SystemTerminology terminology, {bool useEnglish = false}) {
    state = state.copyWith(
      selectedTerminology: terminology,
      terminologyUseEnglish: useEnglish,
    );
  }

  void setCustomTermSingular(String value) {
    state = state.copyWith(customTermSingular: value);
  }

  void setCustomTermPlural(String value) {
    state = state.copyWith(customTermPlural: value);
  }

  void setAccentColor(String hex) {
    state = state.copyWith(accentColorHex: hex);
  }

  void setUsePerMemberColors(bool value) {
    state = state.copyWith(usePerMemberColors: value);
  }

  void setFeatureToggle({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
  }) {
    state = state.copyWith(
      chatEnabled: chatEnabled,
      pollsEnabled: pollsEnabled,
      habitsEnabled: habitsEnabled,
      sleepTrackingEnabled: sleepTrackingEnabled,
    );
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
      OnboardingNotifier.new,
    );

/// Predefined accent color options.
const predefinedColors = [
  '#AF8EE9', // Prism Purple (default)
  '#FF6B6B', // Coral Red
  '#4ECDC4', // Teal
  '#45B7D1', // Sky Blue
  '#96CEB4', // Sage Green
  '#FFEAA7', // Warm Yellow
  '#DDA0DD', // Plum
  '#98D8C8', // Mint
  '#F7DC6F', // Gold
  '#BB8FCE', // Lavender
  '#85C1E9', // Powder Blue
  '#F1948A', // Salmon
];

/// Parses a hex color string to a Color.
Color hexToColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 6 || hex.length == 7) buffer.write('ff');
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
