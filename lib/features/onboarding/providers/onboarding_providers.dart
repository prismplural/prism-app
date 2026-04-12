import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

enum OnboardingStep {
  welcome,
  syncDevice,
  importedDataReady,
  importData,
  systemName,
  addMembers,
  features,
  chatSetup,
  preferences,
  whosFronting,
  complete;

  String get title => switch (this) {
    welcome => 'Welcome to Prism',
    syncDevice => 'Sync From Device',
    importedDataReady => 'Data Ready',
    importData => 'Already have data?',
    systemName => 'Name your system',
    addMembers => "Who's here?",
    features => 'Pick your tools',
    chatSetup => 'Set up chat',
    preferences => 'Make it yours',
    whosFronting => "Who's fronting?",
    complete => 'Ready when you are',
  };

  String get subtitle => switch (this) {
    welcome => 'Your system, your way.',
    syncDevice => 'Pair with an existing device',
    importedDataReady => 'Your imported system is ready to use',
    importData => 'Bring your system with you.',
    systemName => 'Whatever feels right.',
    addMembers => 'Add the people in your system.',
    features => 'Turn on what you need. Change anytime.',
    chatSetup => 'Channels for your system to talk.',
    preferences => 'Colors, language, the small things.',
    whosFronting => "Tap whoever's here right now.",
    complete => "Your system is set up. Here's what to explore.",
  };

  IconData get icon => switch (this) {
    welcome => AppIcons.duotoneStar,
    syncDevice => AppIcons.duotoneSync,
    importedDataReady => AppIcons.duotoneSuccess,
    importData => AppIcons.duotoneImport,
    systemName => AppIcons.label,
    addMembers => AppIcons.duotoneMembers,
    features => AppIcons.duotoneSettings,
    chatSetup => AppIcons.duotoneChat,
    preferences => AppIcons.duotoneTheme,
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

  const OnboardingState({
    this.currentStep = OnboardingStep.welcome,
    this.systemName = '',
    this.selectedChannels = const {
      'All Members': '\u{1F465}',
      'Venting': '\u{1F62E}\u200D\u{1F4A8}',
    },
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

  /// Enter the sync-from-device pairing flow from the import data step.
  void enterSyncDeviceFlow() {
    state = state.copyWith(
      isSyncPath: true,
      currentStep: OnboardingStep.syncDevice,
    );
  }

  /// Leave the sync-from-device flow and return to import data.
  /// Cancels any in-flight pairing attempt before invalidating.
  void leaveSyncDeviceFlow() {
    ref.read(devicePairingProvider.notifier).cancel();
    ref.invalidate(devicePairingProvider);
    state = state.copyWith(
      isSyncPath: false,
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
      OnboardingStep.syncDevice => false, // Managed by SyncDeviceStep itself
      OnboardingStep.importedDataReady => false,
      OnboardingStep.importData => true,
      OnboardingStep.systemName => state.systemName.trim().isNotEmpty,
      OnboardingStep.addMembers => true,
      OnboardingStep.features => true,
      OnboardingStep.chatSetup => true,
      OnboardingStep.preferences => true,
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

  void toggleChannel(String name, String emoji) {
    final updated = Map<String, String>.from(state.selectedChannels);
    if (updated.containsKey(name)) {
      // Don't allow removing "All Members"
      if (name != 'All Members') {
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
