import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/views/onboarding_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Seeds onboarding at the add-members step so the shared "Continue" button
/// exercises the empty-system nudge without walking the whole flow.
class _AddMembersNotifier extends OnboardingNotifier {
  @override
  OnboardingState build() =>
      const OnboardingState(currentStep: OnboardingStep.addMembers);
}

Member _member(String name) =>
    Member(id: name.toLowerCase(), name: name, createdAt: DateTime(2020));

void main() {
  Future<ProviderContainer> pumpStep(
    WidgetTester tester, {
    required List<Member> members,
    AsyncValue<List<Member>>? memberList,
    AsyncValue<List<Member>>? fullMembers,
    bool settle = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        onboardingProvider.overrideWith(_AddMembersNotifier.new),
        hasCompletedOnboardingProvider.overrideWithValue(false),
        syncDisconnectMarkerProvider.overrideWith((ref) async => null),
        userVisibleAllMemberListProvider.overrideWithValue(
          memberList ?? AsyncValue.data(members),
        ),
        userVisibleAllMembersProvider.overrideWithValue(
          fullMembers ?? AsyncValue.data(members),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: OnboardingScreen(),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  testWidgets('members present: Continue advances with no nudge', (
    tester,
  ) async {
    final container = await pumpStep(tester, members: [_member('Alex')]);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Add someone first?'), findsNothing);
    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.features,
    );
  });

  testWidgets('loading members: Continue does not show empty nudge', (
    tester,
  ) async {
    final container = await pumpStep(
      tester,
      members: const [],
      memberList: const AsyncValue.loading(),
      settle: false,
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Add someone first?'), findsNothing);
    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.addMembers,
    );
  });

  testWidgets('visible members: Continue ignores unloaded full-member stream', (
    tester,
  ) async {
    final container = await pumpStep(
      tester,
      members: [_member('Alex')],
      fullMembers: const AsyncValue.loading(),
    );

    expect(find.text('Alex'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Add someone first?'), findsNothing);
    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.features,
    );
  });

  testWidgets('no members: cancelling the nudge keeps the add-members step', (
    tester,
  ) async {
    final container = await pumpStep(tester, members: const []);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Add someone first?'), findsOneWidget);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.addMembers,
    );
  });

  testWidgets('no members: confirming the nudge advances exactly one step', (
    tester,
  ) async {
    final container = await pumpStep(tester, members: const []);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.features,
    );
  });

  testWidgets('no members: a double tap opens only one nudge', (tester) async {
    await pumpStep(tester, members: const []);

    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Add someone first?'), findsOneWidget);
  });
}
