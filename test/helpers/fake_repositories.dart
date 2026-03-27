import 'dart:typed_data';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';

// =============================================================================
// FakeMemberRepository
// =============================================================================

class FakeMemberRepository implements MemberRepository {
  final List<Member> _members = [];

  void seed(List<Member> members) {
    _members
      ..clear()
      ..addAll(members);
  }

  @override
  Future<void> createMember(Member member) async {
    _members.add(member);
  }

  @override
  Future<void> deleteMember(String id) async {
    _members.removeWhere((member) => member.id == id);
  }

  @override
  Future<List<Member>> getAllMembers() async => List.unmodifiable(_members);

  @override
  Future<Member?> getMemberById(String id) async {
    for (final member in _members) {
      if (member.id == id) {
        return member;
      }
    }
    return null;
  }

  @override
  Future<List<Member>> getMembersByIds(List<String> ids) async {
    return _members.where((member) => ids.contains(member.id)).toList();
  }

  @override
  Future<void> updateMember(Member member) async {
    final index = _members.indexWhere((existing) => existing.id == member.id);
    if (index >= 0) {
      _members[index] = member;
    }
  }

  @override
  Stream<List<Member>> watchActiveMembers() {
    return Stream.value(List.unmodifiable(_members.where((member) => member.isActive)));
  }

  @override
  Stream<List<Member>> watchAllMembers() {
    return Stream.value(List.unmodifiable(_members));
  }

  @override
  Stream<Member?> watchMemberById(String id) {
    return Stream.value(
      _members.cast<Member?>().firstWhere(
            (member) => member?.id == id,
            orElse: () => null,
          ),
    );
  }

  @override
  Future<int> getCount() async => _members.length;
}

// =============================================================================
// FakeSystemSettingsRepository
// =============================================================================

class FakeSystemSettingsRepository implements SystemSettingsRepository {
  SystemSettings settings = const SystemSettings();

  @override
  Future<SystemSettings> getSettings() async => settings;

  @override
  Future<void> updateSettings(SystemSettings settings) async {
    this.settings = settings;
  }

  @override
  Stream<SystemSettings> watchSettings() => Stream.value(settings);

  // Field-level update stubs — delegate to updateSettings via copyWith.
  @override
  Future<void> updateSystemName(String? name) async =>
      updateSettings(settings.copyWith(systemName: name));
  @override
  Future<void> updateAccentColorHex(String hex) async =>
      updateSettings(settings.copyWith(accentColorHex: hex));
  @override
  Future<void> updateCustomTerminology(String? value) async =>
      updateSettings(settings.copyWith(customTerminology: value));
  @override
  Future<void> updateCustomPluralTerminology(String? value) async =>
      updateSettings(settings.copyWith(customPluralTerminology: value));
  @override
  Future<void> updatePreviousAccentColorHex(String value) async =>
      updateSettings(settings.copyWith(previousAccentColorHex: value));
  @override
  Future<void> updateShowQuickFront(bool value) async =>
      updateSettings(settings.copyWith(showQuickFront: value));
  @override
  Future<void> updatePerMemberAccentColors(bool value) async =>
      updateSettings(settings.copyWith(perMemberAccentColors: value));
  @override
  Future<void> updateFrontingRemindersEnabled(bool value) async =>
      updateSettings(settings.copyWith(frontingRemindersEnabled: value));
  @override
  Future<void> updateChatEnabled(bool value) async =>
      updateSettings(settings.copyWith(chatEnabled: value));
  @override
  Future<void> updatePollsEnabled(bool value) async =>
      updateSettings(settings.copyWith(pollsEnabled: value));
  @override
  Future<void> updateHabitsEnabled(bool value) async =>
      updateSettings(settings.copyWith(habitsEnabled: value));
  @override
  Future<void> updateSleepTrackingEnabled(bool value) async =>
      updateSettings(settings.copyWith(sleepTrackingEnabled: value));
  @override
  Future<void> updateChatLogsFront(bool value) async =>
      updateSettings(settings.copyWith(chatLogsFront: value));
  @override
  Future<void> updateHabitsBadgeEnabled(bool value) async =>
      updateSettings(settings.copyWith(habitsBadgeEnabled: value));
  @override
  Future<void> updateNotesEnabled(bool value) async =>
      updateSettings(settings.copyWith(notesEnabled: value));
  @override
  Future<void> updateSyncThemeEnabled(bool value) async =>
      updateSettings(settings.copyWith(syncThemeEnabled: value));
  @override
  Future<void> updateHasCompletedOnboarding(bool value) async =>
      updateSettings(settings.copyWith(hasCompletedOnboarding: value));
  @override
  Future<void> updateTerminology(SystemTerminology value) async =>
      updateSettings(settings.copyWith(terminology: value));
  @override
  Future<void> updateThemeMode(AppThemeMode value) async =>
      updateSettings(settings.copyWith(themeMode: value));
  @override
  Future<void> updateThemeBrightness(ThemeBrightness value) async =>
      updateSettings(settings.copyWith(themeBrightness: value));
  @override
  Future<void> updateThemeStyle(ThemeStyle value) async =>
      updateSettings(settings.copyWith(themeStyle: value));
  @override
  Future<void> updateTimingMode(FrontingTimingMode value) async =>
      updateSettings(settings.copyWith(timingMode: value));
  @override
  Future<void> updateFrontingReminderIntervalMinutes(int value) async =>
      updateSettings(
          settings.copyWith(frontingReminderIntervalMinutes: value));
  @override
  Future<void> updateQuickSwitchThresholdSeconds(int value) async =>
      updateSettings(settings.copyWith(quickSwitchThresholdSeconds: value));
  @override
  Future<void> updateTerminologyFields({
    required SystemTerminology terminology,
    String? customTerminology,
    String? customPluralTerminology,
  }) async =>
      updateSettings(settings.copyWith(
        terminology: terminology,
        customTerminology: customTerminology,
        customPluralTerminology: customPluralTerminology,
      ));
  @override
  Future<void> updateFrontingReminders({
    required bool enabled,
    required int intervalMinutes,
  }) async =>
      updateSettings(settings.copyWith(
        frontingRemindersEnabled: enabled,
        frontingReminderIntervalMinutes: intervalMinutes,
      ));
  @override
  Future<void> updateFeatureToggles({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
  }) async =>
      updateSettings(settings.copyWith(
        chatEnabled: chatEnabled ?? settings.chatEnabled,
        pollsEnabled: pollsEnabled ?? settings.pollsEnabled,
        habitsEnabled: habitsEnabled ?? settings.habitsEnabled,
        sleepTrackingEnabled:
            sleepTrackingEnabled ?? settings.sleepTrackingEnabled,
      ));
  @override
  Future<void> updateRemindersEnabled(bool value) async =>
      updateSettings(settings.copyWith(remindersEnabled: value));
  @override
  Future<void> updateSystemDescription(String? value) async =>
      updateSettings(settings.copyWith(systemDescription: value));
  @override
  Future<void> updateSystemAvatarData(Uint8List? value) async =>
      updateSettings(settings.copyWith(systemAvatarData: value));
  @override
  Future<void> updateFontScale(double value) async =>
      updateSettings(settings.copyWith(fontScale: value));
  @override
  Future<void> updateFontFamily(FontFamily value) async =>
      updateSettings(settings.copyWith(fontFamily: value));
  @override
  Future<void> updatePinLockEnabled(bool value) async =>
      updateSettings(settings.copyWith(pinLockEnabled: value));
  @override
  Future<void> updateBiometricLockEnabled(bool value) async =>
      updateSettings(settings.copyWith(biometricLockEnabled: value));
  @override
  Future<void> updateAutoLockDelaySeconds(int value) async =>
      updateSettings(settings.copyWith(autoLockDelaySeconds: value));
  @override
  Future<void> updateNavBarItems(List<String> items) async =>
      updateSettings(settings.copyWith(navBarItems: items));
  @override
  Future<void> updateNavBarOverflowItems(List<String> items) async =>
      updateSettings(settings.copyWith(navBarOverflowItems: items));
  @override
  Future<void> updateSyncNavigationEnabled(bool value) async =>
      updateSettings(settings.copyWith(syncNavigationEnabled: value));
  @override
  Future<void> updateChatBadgePreferences(Map<String, String> prefs) async =>
      updateSettings(settings.copyWith(chatBadgePreferences: prefs));
}

// =============================================================================
// FakeConversationRepository
// =============================================================================

class FakeConversationRepository implements ConversationRepository {
  final List<Conversation> conversations = [];

  @override
  Future<void> createConversation(Conversation conversation) async {
    conversations.add(conversation);
  }

  @override
  Future<void> deleteConversation(String id) async {
    conversations.removeWhere((conversation) => conversation.id == id);
  }

  @override
  Future<List<Conversation>> getAllConversations() async {
    return List.unmodifiable(conversations);
  }

  @override
  Future<Conversation?> getConversationById(String id) async {
    for (final conversation in conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  @override
  Future<List<Conversation>> getConversationsForMember(String memberId) async {
    return conversations
        .where((conversation) => conversation.participantIds.contains(memberId))
        .toList();
  }

  @override
  Future<void> updateConversation(Conversation conversation) async {
    final index = conversations.indexWhere((existing) => existing.id == conversation.id);
    if (index >= 0) {
      conversations[index] = conversation;
    }
  }

  @override
  Future<void> addParticipantId(String conversationId, String memberId) async {}

  @override
  Future<void> removeParticipantId(String conversationId, String memberId) async {}

  @override
  Future<void> setArchivedByMemberIds(String conversationId, List<String> memberIds) async {}

  @override
  Future<void> setMutedByMemberIds(String conversationId, List<String> memberIds) async {}

  @override
  Future<void> setLastReadTimestamps(String conversationId, Map<String, DateTime> timestamps) async {}

  @override
  Future<void> updateLastActivity(String id) async {}

  @override
  Future<int> getCount() async => conversations.length;

  @override
  Stream<List<Conversation>> watchAllConversations() {
    return Stream.value(List.unmodifiable(conversations));
  }

  @override
  Stream<Conversation?> watchConversationById(String id) {
    return Stream.value(
      conversations.cast<Conversation?>().firstWhere(
            (conversation) => conversation?.id == id,
            orElse: () => null,
          ),
    );
  }
}

// =============================================================================
// FakeFrontingSessionRepository
// =============================================================================

class FakeFrontingSessionRepository implements FrontingSessionRepository {
  final List<FrontingSession> sessions = [];
  final List<String> deletedIds = [];

  @override
  Future<void> createSession(FrontingSession session) async {
    sessions.add(session);
  }

  @override
  Future<void> deleteSession(String id) async {
    sessions.removeWhere((session) => session.id == id);
    deletedIds.add(id);
  }

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    final index = sessions.indexWhere((session) => session.id == id);
    if (index >= 0) {
      sessions[index] = sessions[index].copyWith(endTime: endTime);
    }
  }

  @override
  Future<FrontingSession?> getActiveSession() async {
    try {
      return sessions.firstWhere((session) => session.isActive);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<FrontingSession>> getActiveSessions() async {
    return sessions.where((session) => session.isActive).toList();
  }

  @override
  Future<List<FrontingSession>> getAllSessions() async => List.unmodifiable(sessions);

  @override
  Future<FrontingSession?> getSessionById(String id) async {
    try {
      return sessions.firstWhere((session) => session.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<FrontingSession>> getRecentSessions({int limit = 20}) async {
    return sessions.take(limit).toList();
  }

  @override
  Future<List<FrontingSession>> getSessionsBetween(DateTime start, DateTime end) async {
    return sessions
        .where((session) =>
            !session.startTime.isBefore(start) && !session.startTime.isAfter(end))
        .toList();
  }

  @override
  Future<List<FrontingSession>> getSessionsForMember(String memberId) async {
    return sessions.where((session) => session.memberId == memberId).toList();
  }

  @override
  Future<void> updateSession(FrontingSession session) async {
    final index = sessions.indexWhere((existing) => existing.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    }
  }

  @override
  Stream<FrontingSession?> watchActiveSession() => Stream.value(null);

  @override
  Stream<List<FrontingSession>> watchActiveSessions() => Stream.value(const []);

  @override
  Stream<List<FrontingSession>> watchAllSessions() =>
      Stream.value(List.unmodifiable(sessions));

  @override
  Stream<List<FrontingSession>> watchRecentSessions({int limit = 20}) =>
      Stream.value(sessions.take(limit).toList());

  @override
  Stream<FrontingSession?> watchSessionById(String id) => Stream.value(null);

  @override
  Future<int> getCount() async => sessions.length;

  @override
  Future<Map<String, int>> getMemberFrontingCounts({int limit = 50}) async =>
      {};
}
