import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Conversation, FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/services/onboarding_commit_service.dart';

import '../../helpers/fake_repositories.dart';

void main() {
  group('OnboardingNotifier', () {
    test('addDefaultMembers persists members through the member repository', () async {
      final memberRepository = FakeMemberRepository();
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(memberRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(onboardingProvider.notifier).addDefaultMembers();

      final members = await memberRepository.getAllMembers();
      expect(members, hasLength(8));
      expect(members.first.name, 'Zari');
      expect(members.last.name, 'Flux');
    });

    test('createMember and deleteMember delegate to the persisted source of truth', () async {
      final memberRepository = FakeMemberRepository();
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(memberRepository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      await notifier.createMember(
        name: 'Nova',
        pronouns: 'they/them',
        emoji: '🌙',
      );

      var members = await memberRepository.getAllMembers();
      expect(members, hasLength(1));
      expect(members.single.name, 'Nova');

      await notifier.deleteMember(members.single.id);

      members = await memberRepository.getAllMembers();
      expect(members, isEmpty);
    });
  });

  group('OnboardingCommitService', () {
    test('completes onboarding using persisted members and repositories', () async {
      final memberRepository = FakeMemberRepository()
        ..seed([
          Member(
            id: 'member-1',
            name: 'Alex',
            emoji: '✨',
            createdAt: DateTime(2026, 3, 11),
          ),
          Member(
            id: 'member-2',
            name: 'Blake',
            emoji: '🌙',
            createdAt: DateTime(2026, 3, 11),
          ),
        ]);
      final settingsRepository = FakeSystemSettingsRepository();
      final conversationRepository = FakeConversationRepository();
      final frontingRepository = FakeFrontingSessionRepository();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(memberRepository),
          systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
          conversationRepositoryProvider.overrideWithValue(conversationRepository),
          frontingSessionRepositoryProvider.overrideWithValue(frontingRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(onboardingCommitServiceProvider).complete(
            const OnboardingState(
              systemName: 'Prism Collective',
              selectedChannels: {
                'All Members': '👥',
                'Planning': '📝',
              },
              selectedFronterId: 'member-1',
            ),
          );

      expect(settingsRepository.settings.systemName, 'Prism Collective');
      expect(settingsRepository.settings.hasCompletedOnboarding, isTrue);
      expect(conversationRepository.conversations, hasLength(2));
      expect(
        conversationRepository.conversations.map((conversation) => conversation.title),
        containsAll(['All Members', 'Planning']),
      );
      expect(frontingRepository.sessions, hasLength(1));
      expect(frontingRepository.sessions.single.memberId, 'member-1');
    });
  });
}
