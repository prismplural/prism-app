import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';

enum OnboardingStep {
  welcome,
  syncDevice,
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
    importData => 'Import Data',
    systemName => 'Name Your System',
    addMembers => 'Add Members',
    features => 'Choose Features',
    chatSetup => 'Set Up Chat',
    preferences => 'Customize',
    whosFronting => "Who's Fronting?",
    complete => "You're All Set!",
  };

  String get subtitle => switch (this) {
    welcome => 'A safe space for managing your plural system',
    syncDevice => 'Pair with an existing device',
    importData => 'Bring your data from another app',
    systemName => 'What would you like to call your system?',
    addMembers => 'Add the members of your system',
    features => 'Select which features you want to use',
    chatSetup => 'Enable internal communication',
    preferences => 'Personalize your experience',
    whosFronting => 'Set your initial fronter',
    complete => 'Your system is ready to use',
  };

  IconData get icon => switch (this) {
    welcome => Icons.auto_awesome,
    syncDevice => Icons.sync,
    importData => Icons.download,
    systemName => Icons.label,
    addMembers => Icons.group,
    features => Icons.grid_view,
    chatSetup => Icons.forum,
    preferences => Icons.brush,
    whosFronting => Icons.person_pin,
    complete => Icons.check_circle,
  };

  Color get iconColor => switch (this) {
    welcome => Colors.purple,
    syncDevice => Colors.cyan,
    importData => Colors.cyan,
    systemName => Colors.blue,
    addMembers => Colors.green,
    features => Colors.indigo,
    chatSetup => Colors.orange,
    preferences => Colors.pink,
    whosFronting => Colors.cyan,
    complete => Colors.green,
  };

  List<Color> get gradientColors => switch (this) {
    welcome => [
      Colors.purple.withValues(alpha: 0.3),
      Colors.blue.withValues(alpha: 0.3),
    ],
    syncDevice => [
      Colors.cyan.withValues(alpha: 0.3),
      Colors.purple.withValues(alpha: 0.3),
    ],
    importData => [
      Colors.cyan.withValues(alpha: 0.3),
      Colors.blue.withValues(alpha: 0.3),
    ],
    systemName => [
      Colors.blue.withValues(alpha: 0.3),
      Colors.cyan.withValues(alpha: 0.3),
    ],
    addMembers => [
      Colors.green.withValues(alpha: 0.3),
      Colors.teal.withValues(alpha: 0.3),
    ],
    features => [
      Colors.indigo.withValues(alpha: 0.3),
      Colors.purple.withValues(alpha: 0.3),
    ],
    chatSetup => [
      Colors.orange.withValues(alpha: 0.3),
      Colors.yellow.withValues(alpha: 0.3),
    ],
    preferences => [
      Colors.pink.withValues(alpha: 0.3),
      Colors.pink.withValues(alpha: 0.2),
    ],
    whosFronting => [
      Colors.cyan.withValues(alpha: 0.3),
      Colors.blue.withValues(alpha: 0.3),
    ],
    complete => [
      Colors.green.withValues(alpha: 0.3),
      Colors.teal.withValues(alpha: 0.3),
    ],
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
  final String? customTermSingular;
  final String? customTermPlural;
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
    this.customTermSingular,
    this.customTermPlural,
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
    Object? customTermSingular = _sentinel,
    Object? customTermPlural = _sentinel,
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
      customTermSingular: customTermSingular == _sentinel
          ? this.customTermSingular
          : customTermSingular as String?,
      customTermPlural: customTermPlural == _sentinel
          ? this.customTermPlural
          : customTermPlural as String?,
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

  void setTerminology(SystemTerminology terminology) {
    state = state.copyWith(selectedTerminology: terminology);
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
