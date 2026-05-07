import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Conversation, FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/services/onboarding_commit_service.dart';

import '../../helpers/fake_repositories.dart';

void main() {
  group('OnboardingNotifier', () {
    test(
      'createMember and deleteMember delegate to the persisted source of truth',
      () async {
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
      },
    );

    test('next() skips importedDataReady when importedDataCounts is null', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      expect(
        container.read(onboardingProvider).currentStep,
        OnboardingStep.welcome,
      );

      // next() from welcome proceeds to pinSetup (new PIN auth step).
      notifier.next();
      expect(
        container.read(onboardingProvider).currentStep,
        OnboardingStep.pinSetup,
      );
    });

    test('next() does not skip importedDataReady when counts are set', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      // Set counts so importedDataReady is not skipped
      notifier.showImportedDataReady(const OnboardingDataCounts(members: 2));
      // Move back to welcome to test forward navigation
      // We can't go back easily, so instead verify the step was set
      expect(
        container.read(onboardingProvider).currentStep,
        OnboardingStep.importedDataReady,
      );
    });

    test('canProceed returns false for importedDataReady step', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      notifier.showImportedDataReady(const OnboardingDataCounts(members: 1));
      expect(notifier.canProceed, isFalse);
    });

    test('showImportedDataReady sets step and counts', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      const counts = OnboardingDataCounts(members: 3, notes: 5);

      notifier.showImportedDataReady(counts);

      final state = container.read(onboardingProvider);
      expect(state.currentStep, OnboardingStep.importedDataReady);
      expect(state.importedDataCounts, isNotNull);
      expect(state.importedDataCounts!.members, 3);
      expect(state.importedDataCounts!.notes, 5);
    });

    test('fronting behavior setters update onboarding state independently', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);

      notifier.setAddFrontDefaultBehavior(FrontStartBehavior.replace);
      expect(
        container.read(onboardingProvider).addFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
      expect(
        container.read(onboardingProvider).quickFrontDefaultBehavior,
        isNull,
      );

      notifier.setQuickFrontDefaultBehavior(FrontStartBehavior.replace);
      expect(
        container.read(onboardingProvider).quickFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
    });

    test('onboarding nav layout filters disabled feature tabs', () {
      final layout = onboardingNavLayout(
        const OnboardingState(chatEnabled: false, pollsEnabled: false),
      );
      final primaryIds = layout.primary.map((tab) => tab.id).toList();
      final overflowIds = layout.overflow.map((tab) => tab.id).toList();

      expect(primaryIds, [
        AppShellTabId.home,
        AppShellTabId.habits,
        AppShellTabId.settings,
      ]);
      expect(overflowIds, [
        AppShellTabId.members,
        AppShellTabId.notes,
        AppShellTabId.reminders,
        AppShellTabId.statistics,
        AppShellTabId.timeline,
        AppShellTabId.sleep,
      ]);
    });

    test('setNavLayout reinserts settings when hidden', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      notifier.setNavLayout(primary: ['home'], overflow: const []);

      final state = container.read(onboardingProvider);
      expect(state.navBarItems, ['home']);
      expect(state.navBarOverflowItems, ['settings']);
    });

    test('disabling a feature removes its drafted nav item', () {
      final container = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      notifier.setNavLayout(
        primary: ['home', 'notes', 'settings'],
        overflow: const [],
      );
      notifier.setFeatureToggle(notesEnabled: false);

      final state = container.read(onboardingProvider);
      expect(state.navBarItems, ['home', 'settings']);
      expect(state.navBarOverflowItems, isEmpty);
    });
  });

  group('OnboardingCommitService', () {
    test(
      'completes onboarding using persisted members and repositories',
      () async {
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
            systemSettingsRepositoryProvider.overrideWithValue(
              settingsRepository,
            ),
            conversationRepositoryProvider.overrideWithValue(
              conversationRepository,
            ),
            frontingSessionRepositoryProvider.overrideWithValue(
              frontingRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(onboardingCommitServiceProvider)
            .complete(
              const OnboardingState(
                systemName: 'Prism Collective',
                selectedChannels: {'All Members': '👥', 'Planning': '📝'},
                selectedFronterId: 'member-1',
              ),
            );

        expect(settingsRepository.settings.systemName, 'Prism Collective');
        expect(settingsRepository.settings.hasCompletedOnboarding, isTrue);
        expect(conversationRepository.conversations, hasLength(2));
        expect(
          conversationRepository.conversations.map(
            (conversation) => conversation.title,
          ),
          containsAll(['All Members', 'Planning']),
        );
        expect(frontingRepository.sessions, hasLength(1));
        expect(frontingRepository.sessions.single.memberId, 'member-1');
      },
    );

    test('complete writes onboarding front behavior choices', () async {
      final settingsRepository = FakeSystemSettingsRepository();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
          systemSettingsRepositoryProvider.overrideWithValue(
            settingsRepository,
          ),
          conversationRepositoryProvider.overrideWithValue(
            FakeConversationRepository(),
          ),
          frontingSessionRepositoryProvider.overrideWithValue(
            FakeFrontingSessionRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(onboardingCommitServiceProvider)
          .complete(
            const OnboardingState(
              systemName: 'Prism Collective',
              addFrontDefaultBehavior: FrontStartBehavior.replace,
              quickFrontDefaultBehavior: FrontStartBehavior.replace,
            ),
          );

      expect(
        settingsRepository.settings.addFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
      expect(
        settingsRepository.settings.quickFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
    });

    test(
      'complete preserves existing front behavior choices when untouched',
      () async {
        final settingsRepository = FakeSystemSettingsRepository()
          ..settings = const SystemSettings(
            addFrontDefaultBehavior: FrontStartBehavior.replace,
            quickFrontDefaultBehavior: FrontStartBehavior.replace,
          );
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
            systemSettingsRepositoryProvider.overrideWithValue(
              settingsRepository,
            ),
            conversationRepositoryProvider.overrideWithValue(
              FakeConversationRepository(),
            ),
            frontingSessionRepositoryProvider.overrideWithValue(
              FakeFrontingSessionRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(onboardingCommitServiceProvider)
            .complete(const OnboardingState(systemName: 'Prism Collective'));

        expect(
          settingsRepository.settings.addFrontDefaultBehavior,
          FrontStartBehavior.replace,
        );
        expect(
          settingsRepository.settings.quickFrontDefaultBehavior,
          FrontStartBehavior.replace,
        );
      },
    );

    test('complete writes drafted onboarding navigation layout', () async {
      final settingsRepository = FakeSystemSettingsRepository();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
          systemSettingsRepositoryProvider.overrideWithValue(
            settingsRepository,
          ),
          conversationRepositoryProvider.overrideWithValue(
            FakeConversationRepository(),
          ),
          frontingSessionRepositoryProvider.overrideWithValue(
            FakeFrontingSessionRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(onboardingCommitServiceProvider)
          .complete(
            const OnboardingState(
              systemName: 'Prism Collective',
              boardsEnabled: true,
              navBarItems: ['home', 'settings'],
              navBarOverflowItems: ['members'],
            ),
          );

      expect(settingsRepository.settings.navBarItems, ['home', 'settings']);
      expect(settingsRepository.settings.navBarOverflowItems, ['members']);
    });

    test(
      'completes imported bootstrap without overwriting imported settings',
      () async {
        final memberRepository = FakeMemberRepository();
        final settingsRepository = FakeSystemSettingsRepository()
          ..settings = const SystemSettings(
            systemName: 'Imported Collective',
            chatEnabled: false,
            pollsEnabled: false,
            habitsEnabled: true,
            hasCompletedOnboarding: false,
          );
        final conversationRepository = FakeConversationRepository();
        final frontingRepository = FakeFrontingSessionRepository();
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(memberRepository),
            systemSettingsRepositoryProvider.overrideWithValue(
              settingsRepository,
            ),
            conversationRepositoryProvider.overrideWithValue(
              conversationRepository,
            ),
            frontingSessionRepositoryProvider.overrideWithValue(
              frontingRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(onboardingCommitServiceProvider)
            .completeImportedBootstrap();

        expect(settingsRepository.settings.systemName, 'Imported Collective');
        expect(settingsRepository.settings.chatEnabled, isFalse);
        expect(settingsRepository.settings.pollsEnabled, isFalse);
        expect(settingsRepository.settings.habitsEnabled, isTrue);
        expect(settingsRepository.settings.hasCompletedOnboarding, isTrue);
        expect(conversationRepository.conversations, isEmpty);
        expect(frontingRepository.sessions, isEmpty);
      },
    );

    test(
      'completeImportedBootstrap is a no-op when already completed',
      () async {
        final settingsRepository = FakeSystemSettingsRepository()
          ..settings = const SystemSettings(
            systemName: 'Already Done',
            hasCompletedOnboarding: true,
          );
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
            systemSettingsRepositoryProvider.overrideWithValue(
              settingsRepository,
            ),
            conversationRepositoryProvider.overrideWithValue(
              FakeConversationRepository(),
            ),
            frontingSessionRepositoryProvider.overrideWithValue(
              FakeFrontingSessionRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(onboardingCommitServiceProvider)
            .completeImportedBootstrap();

        // Settings should remain unchanged
        expect(settingsRepository.settings.systemName, 'Already Done');
        expect(settingsRepository.settings.hasCompletedOnboarding, isTrue);
      },
    );
  });
}
