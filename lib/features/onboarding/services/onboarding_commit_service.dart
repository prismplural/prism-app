import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Conversation, FrontingSession;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:uuid/uuid.dart';

final onboardingCommitServiceProvider = Provider<OnboardingCommitService>((
  ref,
) {
  return OnboardingCommitService(
    database: ref.watch(databaseProvider),
    settingsRepository: ref.watch(systemSettingsRepositoryProvider),
    memberRepository: ref.watch(memberRepositoryProvider),
    conversationRepository: ref.watch(conversationRepositoryProvider),
    frontingRepository: ref.watch(frontingSessionRepositoryProvider),
  );
});

class OnboardingCommitService {
  OnboardingCommitService({
    required AppDatabase database,
    required SystemSettingsRepository settingsRepository,
    required MemberRepository memberRepository,
    required ConversationRepository conversationRepository,
    required FrontingSessionRepository frontingRepository,
  }) : _database = database,
       _settingsRepository = settingsRepository,
       _memberRepository = memberRepository,
       _conversationRepository = conversationRepository,
       _frontingRepository = frontingRepository;

  static const _uuid = Uuid();

  final AppDatabase _database;
  final SystemSettingsRepository _settingsRepository;
  final MemberRepository _memberRepository;
  final ConversationRepository _conversationRepository;
  final FrontingSessionRepository _frontingRepository;

  Future<void> complete(OnboardingState onboarding) async {
    await _database.transaction(() async {
      final currentSettings = await _settingsRepository.getSettings();
      await _settingsRepository.updateSettings(
        currentSettings.copyWith(
          systemName: onboarding.systemName,
          terminology: onboarding.selectedTerminology,
          customTerminology: onboarding.customTermSingular,
          customPluralTerminology: onboarding.customTermPlural,
          accentColorHex: onboarding.accentColorHex,
          perMemberAccentColors: onboarding.usePerMemberColors,
          chatEnabled: onboarding.chatEnabled,
          pollsEnabled: onboarding.pollsEnabled,
          habitsEnabled: onboarding.habitsEnabled,
          sleepTrackingEnabled: onboarding.sleepTrackingEnabled,
          hasCompletedOnboarding: true,
        ),
      );

      final members = await _memberRepository.getAllMembers();

      if (onboarding.chatEnabled &&
          onboarding.selectedChannels.isNotEmpty &&
          members.isNotEmpty) {
        // Check for existing conversations to avoid duplicates when
        // re-running onboarding.
        final existingConversations = await _conversationRepository
            .getAllConversations();
        final existingTitles = existingConversations
            .map((c) => c.title)
            .toSet();

        final creatorId = members.first.id;
        final participantIds = members.map((member) => member.id).toList();

        for (final entry in onboarding.selectedChannels.entries) {
          if (existingTitles.contains(entry.key)) continue;
          await _conversationRepository.createConversation(
            Conversation(
              id: _uuid.v4(),
              createdAt: DateTime.now(),
              lastActivityAt: DateTime.now(),
              title: entry.key,
              emoji: entry.value,
              creatorId: creatorId,
              participantIds: participantIds,
            ),
          );
        }
      }

      final selectedFronterId = onboarding.selectedFronterId;
      if (selectedFronterId != null &&
          members.any((member) => member.id == selectedFronterId)) {
        final activeSessions = await _frontingRepository
            .getAllActiveSessionsUnfiltered();
        final now = DateTime.now();
        for (final session in activeSessions) {
          await _frontingRepository.endSession(session.id, now);
        }

        await _frontingRepository.createSession(
          FrontingSession(
            id: _uuid.v4(),
            startTime: now,
            memberId: selectedFronterId,
          ),
        );
      }
    });
  }
}
