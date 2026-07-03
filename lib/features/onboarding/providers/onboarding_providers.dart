import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/services/auth_policy_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:uuid/uuid.dart';

/// Intercepts the bottom "Continue" button on the importData step so an
/// inline import sub-flow (PK token, SP file, Prism export) can run its
/// own action instead of silently skipping past it. When set, the Continue
/// button invokes this callback instead of advancing the step. The callback
/// is responsible for progressing onboarding on success.
class OnboardingPendingImportAction extends Notifier<Future<void> Function()?> {
  @override
  Future<void> Function()? build() => null;

  void set(Future<void> Function()? action) => state = action;
}

final onboardingPendingImportActionProvider =
    NotifierProvider<OnboardingPendingImportAction, Future<void> Function()?>(
      OnboardingPendingImportAction.new,
    );

enum OnboardingStep {
  welcome,
  pinSetup, // 6-digit PIN creation
  recoveryPhrase, // Show 12-word backup + save confirmation
  biometricSetup, // Face ID / Touch ID opt-in
  syncDevice,
  importedDataReady,
  importData,
  systemName,
  terminology,
  addMembers,
  features,
  navigation,
  frontingDefaults,
  chatSetup,
  appearance,
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
    terminology => 'Choose your words',
    addMembers => "Who's here?",
    features => 'Pick your tools',
    navigation => 'Arrange navigation',
    frontingDefaults => 'Fronting defaults',
    chatSetup => 'Set up chat',
    appearance => 'Make it yours',
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
    terminology => 'This changes labels throughout Prism.',
    addMembers => 'Add the people in your system.',
    features => 'Turn on what you need. Change anytime.',
    navigation => '',
    frontingDefaults => 'Choose how Home shows and starts fronts.',
    chatSetup => 'Channels for your system to talk.',
    appearance => 'Colors, theme, the small things.',
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
    terminology => AppIcons.duotoneChat,
    addMembers => AppIcons.duotoneMembers,
    features => AppIcons.duotoneSettings,
    navigation => AppIcons.navHome,
    frontingDefaults => AppIcons.duotoneFronting,
    chatSetup => AppIcons.duotoneChat,
    appearance => AppIcons.duotoneTheme,
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
  final ThemeBrightness? themeBrightness;
  final ThemeStyle? themeStyle;
  final CornerStyle? cornerStyle;
  final bool hasAccentColorPreview;
  final bool hasThemeBrightnessPreview;
  final bool hasThemeStylePreview;
  final bool hasCornerStylePreview;
  final bool chatEnabled;
  final bool pollsEnabled;
  final bool habitsEnabled;
  final bool sleepTrackingEnabled;
  final bool notesEnabled;
  final bool boardsEnabled;
  final bool remindersEnabled;
  final List<String> navBarItems;
  final List<String> navBarOverflowItems;
  final FrontingListViewMode? frontingListViewMode;
  final FrontStartBehavior? addFrontDefaultBehavior;
  final FrontStartBehavior? quickFrontDefaultBehavior;
  final String? selectedFronterId;
  final bool wasImportedFromPluralKit;
  final bool wasImportedFromSimplyPlural;
  final int importedSimplyPluralConversationCount;
  final int importedSimplyPluralMessageCount;
  final int importedSimplyPluralBoardPostCount;
  final OnboardingDataCounts? importedDataCounts;
  final String? customTermSingular;
  final String? customTermPlural;
  final bool useCustomSystemTerminology;
  final SystemTermPreset? selectedSystemTermPreset;
  final String? customSystemTermSingular;
  final String? customSystemTermPlural;
  final bool terminologyUseEnglish;
  final bool isSyncPath;

  /// The channel key that cannot be removed (locale-aware "All Members" name).
  /// Null until ChatSetupStep seeds the localized defaults on first render.
  final String? allMembersChannelKey;

  /// The 12-word mnemonic words generated during PIN setup. Ephemeral —
  /// kept in memory only until the biometric step completes or is skipped.
  final List<String> mnemonicWords;

  const OnboardingState({
    this.currentStep = OnboardingStep.welcome,
    this.systemName = '',
    this.selectedChannels = const {},
    this.customChannelName = '',
    this.selectedTerminology = SystemTerminology.headmates,
    this.accentColorHex = '#9070A0',
    this.usePerMemberColors = true,
    this.themeBrightness,
    this.themeStyle,
    this.cornerStyle,
    this.hasAccentColorPreview = false,
    this.hasThemeBrightnessPreview = false,
    this.hasThemeStylePreview = false,
    this.hasCornerStylePreview = false,
    this.chatEnabled = true,
    this.pollsEnabled = true,
    this.habitsEnabled = true,
    this.sleepTrackingEnabled = true,
    this.notesEnabled = true,
    this.boardsEnabled = false,
    this.remindersEnabled = true,
    this.navBarItems = const [],
    this.navBarOverflowItems = const [],
    this.frontingListViewMode,
    this.addFrontDefaultBehavior,
    this.quickFrontDefaultBehavior,
    this.selectedFronterId,
    this.wasImportedFromPluralKit = false,
    this.wasImportedFromSimplyPlural = false,
    this.importedSimplyPluralConversationCount = 0,
    this.importedSimplyPluralMessageCount = 0,
    this.importedSimplyPluralBoardPostCount = 0,
    this.importedDataCounts,
    this.customTermSingular,
    this.customTermPlural,
    this.useCustomSystemTerminology = false,
    this.selectedSystemTermPreset,
    this.customSystemTermSingular,
    this.customSystemTermPlural,
    this.terminologyUseEnglish = false,
    this.isSyncPath = false,
    this.allMembersChannelKey,
    this.mnemonicWords = const [],
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
    Object? themeBrightness = _sentinel,
    Object? themeStyle = _sentinel,
    Object? cornerStyle = _sentinel,
    bool? hasAccentColorPreview,
    bool? hasThemeBrightnessPreview,
    bool? hasThemeStylePreview,
    bool? hasCornerStylePreview,
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
    bool? notesEnabled,
    bool? boardsEnabled,
    bool? remindersEnabled,
    List<String>? navBarItems,
    List<String>? navBarOverflowItems,
    Object? frontingListViewMode = _sentinel,
    Object? addFrontDefaultBehavior = _sentinel,
    Object? quickFrontDefaultBehavior = _sentinel,
    String? selectedFronterId,
    bool? wasImportedFromPluralKit,
    bool? wasImportedFromSimplyPlural,
    int? importedSimplyPluralConversationCount,
    int? importedSimplyPluralMessageCount,
    int? importedSimplyPluralBoardPostCount,
    Object? importedDataCounts = _sentinel,
    Object? customTermSingular = _sentinel,
    Object? customTermPlural = _sentinel,
    bool? useCustomSystemTerminology,
    Object? selectedSystemTermPreset = _sentinel,
    Object? customSystemTermSingular = _sentinel,
    Object? customSystemTermPlural = _sentinel,
    bool? terminologyUseEnglish,
    bool? isSyncPath,
    bool clearFronterId = false,
    String? allMembersChannelKey,
    List<String>? mnemonicWords,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      systemName: systemName ?? this.systemName,
      selectedChannels: selectedChannels ?? this.selectedChannels,
      customChannelName: customChannelName ?? this.customChannelName,
      selectedTerminology: selectedTerminology ?? this.selectedTerminology,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      usePerMemberColors: usePerMemberColors ?? this.usePerMemberColors,
      themeBrightness: themeBrightness == _sentinel
          ? this.themeBrightness
          : themeBrightness as ThemeBrightness?,
      themeStyle: themeStyle == _sentinel
          ? this.themeStyle
          : themeStyle as ThemeStyle?,
      cornerStyle: cornerStyle == _sentinel
          ? this.cornerStyle
          : cornerStyle as CornerStyle?,
      hasAccentColorPreview:
          hasAccentColorPreview ?? this.hasAccentColorPreview,
      hasThemeBrightnessPreview:
          hasThemeBrightnessPreview ?? this.hasThemeBrightnessPreview,
      hasThemeStylePreview: hasThemeStylePreview ?? this.hasThemeStylePreview,
      hasCornerStylePreview:
          hasCornerStylePreview ?? this.hasCornerStylePreview,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      pollsEnabled: pollsEnabled ?? this.pollsEnabled,
      habitsEnabled: habitsEnabled ?? this.habitsEnabled,
      sleepTrackingEnabled: sleepTrackingEnabled ?? this.sleepTrackingEnabled,
      notesEnabled: notesEnabled ?? this.notesEnabled,
      boardsEnabled: boardsEnabled ?? this.boardsEnabled,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      navBarItems: navBarItems ?? this.navBarItems,
      navBarOverflowItems: navBarOverflowItems ?? this.navBarOverflowItems,
      frontingListViewMode: frontingListViewMode == _sentinel
          ? this.frontingListViewMode
          : frontingListViewMode as FrontingListViewMode?,
      addFrontDefaultBehavior: addFrontDefaultBehavior == _sentinel
          ? this.addFrontDefaultBehavior
          : addFrontDefaultBehavior as FrontStartBehavior?,
      quickFrontDefaultBehavior: quickFrontDefaultBehavior == _sentinel
          ? this.quickFrontDefaultBehavior
          : quickFrontDefaultBehavior as FrontStartBehavior?,
      selectedFronterId: clearFronterId
          ? null
          : (selectedFronterId ?? this.selectedFronterId),
      wasImportedFromPluralKit:
          wasImportedFromPluralKit ?? this.wasImportedFromPluralKit,
      wasImportedFromSimplyPlural:
          wasImportedFromSimplyPlural ?? this.wasImportedFromSimplyPlural,
      importedSimplyPluralConversationCount:
          importedSimplyPluralConversationCount ??
          this.importedSimplyPluralConversationCount,
      importedSimplyPluralMessageCount:
          importedSimplyPluralMessageCount ??
          this.importedSimplyPluralMessageCount,
      importedSimplyPluralBoardPostCount:
          importedSimplyPluralBoardPostCount ??
          this.importedSimplyPluralBoardPostCount,
      importedDataCounts: importedDataCounts == _sentinel
          ? this.importedDataCounts
          : importedDataCounts as OnboardingDataCounts?,
      customTermSingular: customTermSingular == _sentinel
          ? this.customTermSingular
          : customTermSingular as String?,
      customTermPlural: customTermPlural == _sentinel
          ? this.customTermPlural
          : customTermPlural as String?,
      useCustomSystemTerminology:
          useCustomSystemTerminology ?? this.useCustomSystemTerminology,
      selectedSystemTermPreset: selectedSystemTermPreset == _sentinel
          ? this.selectedSystemTermPreset
          : selectedSystemTermPreset as SystemTermPreset?,
      customSystemTermSingular: customSystemTermSingular == _sentinel
          ? this.customSystemTermSingular
          : customSystemTermSingular as String?,
      customSystemTermPlural: customSystemTermPlural == _sentinel
          ? this.customSystemTermPlural
          : customSystemTermPlural as String?,
      terminologyUseEnglish:
          terminologyUseEnglish ?? this.terminologyUseEnglish,
      isSyncPath: isSyncPath ?? this.isSyncPath,
      allMembersChannelKey: allMembersChannelKey ?? this.allMembersChannelKey,
      mnemonicWords: mnemonicWords ?? this.mnemonicWords,
    );
  }

  bool get hasImportedSimplyPluralChats =>
      wasImportedFromSimplyPlural &&
      (importedSimplyPluralConversationCount > 0 ||
          importedSimplyPluralMessageCount > 0);

  bool get hasImportedSimplyPluralBoardPosts =>
      wasImportedFromSimplyPlural && importedSimplyPluralBoardPostCount > 0;

  bool get hasAppearancePreview =>
      hasAccentColorPreview ||
      hasThemeBrightnessPreview ||
      hasThemeStylePreview ||
      hasCornerStylePreview;
}

({
  bool chat,
  bool polls,
  bool habits,
  bool sleep,
  bool notes,
  bool reminders,
  bool boards,
})
onboardingFeatureFlags(OnboardingState state) {
  return (
    chat: state.chatEnabled,
    polls: state.pollsEnabled,
    habits: state.habitsEnabled,
    sleep: state.sleepTrackingEnabled,
    notes: state.notesEnabled,
    reminders: state.remindersEnabled,
    boards: state.boardsEnabled,
  );
}

NavLayout onboardingNavLayout(OnboardingState state) {
  final hasDraftLayout =
      state.navBarItems.isNotEmpty || state.navBarOverflowItems.isNotEmpty;
  return normalizeNavLayout(
    primaryIds: hasDraftLayout ? state.navBarItems : defaultNavBarTabIds,
    overflowIds: hasDraftLayout
        ? state.navBarOverflowItems
        : defaultNavBarOverflowTabIds,
    flags: onboardingFeatureFlags(state),
  );
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  static const _uuid = Uuid();

  /// Reentrancy guard for [onPinConfirmed]. PinInputScreen has its own
  /// `_isCompleting` guard at the widget layer (commit 69bbc9f0), but a
  /// Riverpod invalidation of `onboardingProvider` — or any future caller
  /// that bypasses the widget — could still fire [onPinConfirmed] twice
  /// against the same FFI handle, which would call `ffi.initialize` twice
  /// and corrupt the wrapped DEK / device keys. This provider-scoped flag
  /// makes "at most one in-flight PIN derivation per notifier instance"
  /// enforceable regardless of caller.
  bool _pinSetupInFlight = false;

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
  /// 5. Rotates local database keys and caches a device-bound wrapped runtime
  ///    DEK when a sync identity already exists.
  /// 6. Stores the PIN hash via [PinLockService].
  /// 7. Advances to [OnboardingStep.recoveryPhrase] so the user can write the
  ///    mnemonic down. The phrase is NEVER persisted — it is an offline
  ///    backup credential.
  Future<void> onPinConfirmed(String pin) async {
    if (_pinSetupInFlight) {
      if (kDebugMode) {
        debugPrint(
          '[ONBOARDING] onPinConfirmed re-entered while in-flight; ignoring',
        );
      }
      return;
    }
    _pinSetupInFlight = true;
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

      // 3. Convert mnemonic phrase to secret-key bytes. The generated
      // mnemonic remains as display text below until the user saves it; the
      // FFI input copy is scrubbed as soon as conversion returns.
      Uint8List? mnemonicBytes = secretUtf8Bytes(mnemonic);
      Uint8List? secretKeyBytes;
      Uint8List? pinBytes;
      try {
        secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonicBytes);
      } finally {
        zeroBytesBestEffort(mnemonicBytes);
        mnemonicBytes = null;
      }

      // 4. Initialize the key hierarchy: PIN is the password, secretKey
      //    is the BIP39 entropy. This derives MEK → DEK → device keys.
      try {
        pinBytes = secretUtf8Bytes(pin);
        await ffi.initialize(
          handle: handle,
          password: pinBytes,
          secretKey: secretKeyBytes,
        );
      } finally {
        zeroBytesBestEffort(pinBytes);
        zeroBytesBestEffort(secretKeyBytes);
        pinBytes = null;
        secretKeyBytes = null;
      }

      // 5. Drain Rust's MemorySecureStore to the platform keychain
      //    (writes wrapped_dek, dek_salt, device_secret, device_id, etc.).
      //    The mnemonic is NOT written — it's an offline backup credential
      //    that the user will save themselves in step 7 and re-type when
      //    they change their PIN or pair another device.
      //
      //    Capture an authoritative pre-write snapshot first and use the
      //    snapshot-rollback drain so a partial keychain mirror failure
      //    restores the pre-onboarding keychain exactly. Onboarding is
      //    expected to run with a clean `prism_sync.*` namespace, but
      //    defensive snapshot-then-restore is still correct (e.g. a
      //    half-failed previous attempt may have left orphans). If the
      //    snapshot scan itself throws, fall back to the plain
      //    `drainRustStore` (post-config "log and continue" semantics) —
      //    aborting the in-flight onboarding for a transient keystore
      //    read failure is more disruptive than the loss of exact
      //    rollback. The capture failure is reported via
      //    `ErrorReportingService` inside `snapshotPrismSyncKeychain`.
      final preDrainKeychainSnapshot = await snapshotPrismSyncKeychain();
      if (preDrainKeychainSnapshot != null) {
        await drainRustStoreWithSnapshotRollback(
          handle,
          rollbackSnapshot: preDrainKeychainSnapshot,
        );
      } else {
        await drainRustStore(handle);
      }

      // 6. Rotate local database keys. If a sync identity already exists, also
      //    cache a device-bound wrapped DEK for Signal-style fast unlock.
      await cacheRuntimeKeys(handle, ref.read(databaseProvider));

      // 7. PIN hash already stored by PinSetupStep.onPinEntered before
      //    calling onPinConfirmed — no second storePin() call here.

      // 9. Record PIN as freshly verified so the 30-day check doesn't fire
      //     immediately after a new install.
      await ref.read(authPolicyServiceProvider).recordPinVerified();

      // 10. Store words in ephemeral state, advance step. The mnemonic words
      // are retained only for the recovery-phrase display and are cleared when
      // the user leaves the biometric setup step.
      state = state.copyWith(
        mnemonicWords: mnemonicWords,
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
    } finally {
      _pinSetupInFlight = false;
    }
  }

  /// Called when the user confirms they have saved their recovery phrase.
  void onPhraseSaved() {
    state = state.copyWith(currentStep: OnboardingStep.biometricSetup);
  }

  /// Called when the user enables biometric PIN unlock.
  Future<void> onBiometricEnrolled() async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .updateBiometricLockEnabled(true);
    state = state.copyWith(
      mnemonicWords: [],
      currentStep: OnboardingStep.importData,
    );
  }

  /// Called when the user skips the biometric enrollment step.
  void onBiometricSkipped() {
    state = state.copyWith(
      mnemonicWords: [],
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
      OnboardingStep.terminology => true,
      OnboardingStep.addMembers => true,
      OnboardingStep.features => true,
      OnboardingStep.navigation => true,
      OnboardingStep.frontingDefaults => true,
      OnboardingStep.chatSetup => true,
      OnboardingStep.appearance => true,
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

  void skipFronterSelection() {
    state = state.copyWith(clearFronterId: true);
    next();
  }

  void setWasImportedFromPluralKit(bool value) {
    state = state.copyWith(wasImportedFromPluralKit: value);
  }

  void setWasImportedFromSimplyPlural(
    bool value, {
    bool boardPostsImported = false,
    int? conversationCount,
    int? messageCount,
    int? boardPostCount,
  }) {
    final nextConversationCount = value
        ? conversationCount ?? state.importedSimplyPluralConversationCount
        : 0;
    final nextMessageCount = value
        ? messageCount ?? state.importedSimplyPluralMessageCount
        : 0;
    final nextBoardPostCount = value
        ? boardPostCount ??
              (boardPostsImported
                  ? state.importedSimplyPluralBoardPostCount > 0
                        ? state.importedSimplyPluralBoardPostCount
                        : 1
                  : state.importedSimplyPluralBoardPostCount)
        : 0;
    final hasImportedChats =
        value && (nextConversationCount > 0 || nextMessageCount > 0);
    final hasImportedBoardPosts = value && nextBoardPostCount > 0;
    state = state.copyWith(
      wasImportedFromSimplyPlural: value,
      importedSimplyPluralConversationCount: nextConversationCount,
      importedSimplyPluralMessageCount: nextMessageCount,
      importedSimplyPluralBoardPostCount: nextBoardPostCount,
      chatEnabled: hasImportedChats ? true : null,
      boardsEnabled: hasImportedBoardPosts ? true : null,
    );
  }

  void showImportedDataReady(OnboardingDataCounts counts) {
    state = state.copyWith(
      importedDataCounts: counts,
      currentStep: OnboardingStep.importedDataReady,
    );
  }

  Future<void> createMember({
    required String name,
    String? pronouns,
    String emoji = '\u{1F464}',
    String? age,
    String? bio,
    Uint8List? avatarImageData,
  }) async {
    try {
      await ref
          .read(memberRepositoryProvider)
          .createMember(
            Member(
              id: _uuid.v4(),
              name: name,
              pronouns: pronouns,
              emoji: emoji,
              age: age,
              bio: bio,
              avatarImageData: avatarImageData,
              createdAt: DateTime.now(),
            ),
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
      await ref.read(memberRepositoryProvider).deleteMember(memberId);
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
    if (state.hasImportedSimplyPluralChats) {
      state = state.copyWith(
        selectedChannels: const {},
        allMembersChannelKey: allMembersName,
      );
      return;
    }
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

  void setTerminology(
    SystemTerminology terminology, {
    bool useEnglish = false,
  }) {
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

  void setUseCustomSystemTerminology(bool value) {
    state = state.copyWith(
      useCustomSystemTerminology: value,
      selectedSystemTermPreset: null,
    );
  }

  void setSystemTermPreset(SystemTermPreset preset) {
    state = state.copyWith(
      useCustomSystemTerminology: false,
      selectedSystemTermPreset: preset,
    );
  }

  void setCustomSystemTermSingular(String value) {
    state = state.copyWith(customSystemTermSingular: value);
  }

  void setCustomSystemTermPlural(String value) {
    state = state.copyWith(customSystemTermPlural: value);
  }

  void setAccentColor(String hex) {
    state = state.copyWith(accentColorHex: hex, hasAccentColorPreview: true);
  }

  void setImportedAccentColor(String hex) {
    final legibility = classifyAccentLegibility(AppColors.fromHex(hex));
    state = state.copyWith(
      accentColorHex: hex,
      hasAccentColorPreview: legibility == AccentLegibility.ok,
    );
  }

  void setUsePerMemberColors(bool value) {
    state = state.copyWith(usePerMemberColors: value);
  }

  void setThemeBrightness(ThemeBrightness value) {
    state = state.copyWith(
      themeBrightness: value,
      hasThemeBrightnessPreview: true,
    );
  }

  void setThemeStyle(ThemeStyle value) {
    if (value == ThemeStyle.oled) {
      state = state.copyWith(
        themeStyle: value,
        hasThemeStylePreview: true,
        themeBrightness: ThemeBrightness.dark,
        hasThemeBrightnessPreview: true,
      );
      return;
    }
    state = state.copyWith(themeStyle: value, hasThemeStylePreview: true);
  }

  void setCornerStyle(CornerStyle value) {
    state = state.copyWith(cornerStyle: value, hasCornerStylePreview: true);
  }

  void clearAppearancePreview() {
    if (!state.hasAppearancePreview) return;
    state = state.copyWith(
      hasAccentColorPreview: false,
      hasThemeBrightnessPreview: false,
      hasThemeStylePreview: false,
      hasCornerStylePreview: false,
    );
  }

  void setFrontingListViewMode(FrontingListViewMode value) {
    state = state.copyWith(frontingListViewMode: value);
  }

  void setAddFrontDefaultBehavior(FrontStartBehavior value) {
    state = state.copyWith(addFrontDefaultBehavior: value);
  }

  void setQuickFrontDefaultBehavior(FrontStartBehavior value) {
    state = state.copyWith(quickFrontDefaultBehavior: value);
  }

  void setFeatureToggle({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
    bool? notesEnabled,
    bool? boardsEnabled,
    bool? remindersEnabled,
  }) {
    final lockedChatEnabled =
        state.hasImportedSimplyPluralChats && chatEnabled == false
        ? true
        : chatEnabled;
    final lockedBoardsEnabled =
        state.hasImportedSimplyPluralBoardPosts && boardsEnabled == false
        ? true
        : boardsEnabled;
    var nextState = state.copyWith(
      chatEnabled: lockedChatEnabled,
      pollsEnabled: pollsEnabled,
      habitsEnabled: habitsEnabled,
      sleepTrackingEnabled: sleepTrackingEnabled,
      notesEnabled: notesEnabled,
      boardsEnabled: lockedBoardsEnabled,
      remindersEnabled: remindersEnabled,
    );
    if (nextState.navBarItems.isNotEmpty ||
        nextState.navBarOverflowItems.isNotEmpty) {
      final layout = onboardingNavLayout(nextState);
      nextState = nextState.copyWith(
        navBarItems: layout.primary.map((tab) => tab.id.name).toList(),
        navBarOverflowItems: layout.overflow.map((tab) => tab.id.name).toList(),
      );
    }
    state = nextState;
  }

  void setNavLayout({
    required List<String> primary,
    required List<String> overflow,
  }) {
    final layout = normalizeNavLayout(
      primaryIds: primary,
      overflowIds: overflow,
      flags: onboardingFeatureFlags(state),
    );
    state = state.copyWith(
      navBarItems: layout.primary.map((tab) => tab.id.name).toList(),
      navBarOverflowItems: layout.overflow.map((tab) => tab.id.name).toList(),
    );
  }

  void seedNavLayoutIfUnset({
    required List<String> primary,
    required List<String> overflow,
  }) {
    if (state.navBarItems.isNotEmpty || state.navBarOverflowItems.isNotEmpty) {
      return;
    }
    setNavLayout(primary: primary, overflow: overflow);
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
      OnboardingNotifier.new,
    );

/// Predefined accent color options.
const predefinedColors = [
  '#9070A0', // Prism Purple (default)
  '#8474B7', // Prism Iris
  '#8B6FA8', // Heather
  '#667DB6', // Periwinkle
  '#AC6983', // Dusty Rose
  '#B86457', // Soft Coral
  '#6F8458', // Sage
  '#4F8A83', // Seafoam
  '#3476F2', // Azure
  '#9160F2', // Violet
  '#BB4CCB', // Orchid
  '#C75286', // Raspberry
  '#0B8F6A', // Emerald
  '#0284A8', // Cyan
  '#D05820', // Ember
];

/// Parses a hex color string to a Color.
Color hexToColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 6 || hex.length == 7) buffer.write('ff');
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
