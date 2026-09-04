import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/views/onboarding_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

class _LaterOnboardingNotifier extends OnboardingNotifier {
  @override
  OnboardingState build() =>
      const OnboardingState(currentStep: OnboardingStep.frontingDefaults);

  void showWhosFronting() {
    state = state.copyWith(currentStep: OnboardingStep.whosFronting);
  }
}

ProviderContainer _buildContainer() {
  final members = FakeMemberRepository()
    ..seed([
      Member(id: 'member-1', name: 'Ana', createdAt: DateTime(2026, 1, 1)),
    ]);
  return ProviderContainer(
    overrides: [
      onboardingProvider.overrideWith(_LaterOnboardingNotifier.new),
      hasCompletedOnboardingProvider.overrideWithValue(false),
      syncDisconnectMarkerProvider.overrideWith((ref) async => null),
      systemSettingsRepositoryProvider.overrideWithValue(
        FakeSystemSettingsRepository(),
      ),
      memberRepositoryProvider.overrideWithValue(members),
      frontingSessionRepositoryProvider.overrideWithValue(
        FakeFrontingSessionRepository(),
      ),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
    ],
  );
}

void main() {
  testWidgets('pending fronting preset updates later onboarding immediately', (
    tester,
  ) async {
    final container = _buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fronting defaults'), findsOneWidget);

    container
        .read(onboardingProvider.notifier)
        .setFrontingTermPreset(FrontingTermPreset.out);
    await tester.pumpAndSettle();

    expect(find.text('Out defaults'), findsOneWidget);

    (container.read(onboardingProvider.notifier) as _LaterOnboardingNotifier)
        .showWhosFronting();
    await tester.pumpAndSettle();

    expect(find.text("Who's out?"), findsOneWidget);
    expect(find.text("Who's fronting?"), findsNothing);
  });

  testWidgets('pending preset updates the remaining Spanish onboarding flow', (
    tester,
  ) async {
    final container = _buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(onboardingProvider.notifier)
        .setFrontingTermPreset(FrontingTermPreset.out);
    await tester.pumpAndSettle();

    expect(find.text('Configuración: Fuera'), findsOneWidget);
    expect(find.text('Marcar como fuera'), findsWidgets);

    (container.read(onboardingProvider.notifier) as _LaterOnboardingNotifier)
        .showWhosFronting();
    await tester.pumpAndSettle();

    expect(find.text('¿Quién está fuera?'), findsOneWidget);
    expect(find.textContaining('¿Quién está fuera ahora?'), findsWidgets);
    expect(find.textContaining('fronting'), findsNothing);
  });
}
