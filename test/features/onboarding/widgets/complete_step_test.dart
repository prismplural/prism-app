import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/complete_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

import '../../../helpers/fake_repositories.dart';

Member _member({
  required String id,
  required String name,
  required String emoji,
}) {
  return Member(
    id: id,
    name: name,
    emoji: emoji,
    createdAt: DateTime(2026, 5, 6),
  );
}

Future<void> _pumpStep(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: CompleteStep()),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders welcome text with system name and member cloud', (
    tester,
  ) async {
    final repo = FakeMemberRepository()
      ..seed([
        _member(id: 'alex', name: 'Alex', emoji: '🌙'),
        _member(id: 'bea', name: 'Bea', emoji: '⭐'),
        _member(id: 'cy', name: 'Cy', emoji: '🌿'),
      ]);
    final container = ProviderContainer(
      overrides: [memberRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container
        .read(onboardingProvider.notifier)
        .setSystemName('Prism Collective');

    await _pumpStep(tester, container: container);

    expect(find.text('Welcome to Prism'), findsOneWidget);
    expect(find.text('Prism Collective'), findsOneWidget);
    expect(find.byType(MemberAvatar), findsNWidgets(3));
    expect(find.text('🌙'), findsOneWidget);
    expect(find.text('⭐'), findsOneWidget);
    expect(find.text('🌿'), findsOneWidget);

    final textZone = tester
        .getRect(find.text('Welcome to Prism'))
        .expandToInclude(tester.getRect(find.text('Prism Collective')))
        .inflate(10);
    for (final avatar in find.byType(MemberAvatar).evaluate()) {
      expect(
        tester.getRect(find.byWidget(avatar.widget)).overlaps(textZone),
        isFalse,
      );
    }
  });

  testWidgets('limits abstract members without rendering a plus count', (
    tester,
  ) async {
    final repo = FakeMemberRepository()
      ..seed([
        for (var i = 0; i < 24; i++)
          _member(id: 'member-$i', name: 'Member $i', emoji: '✨'),
      ]);
    final container = ProviderContainer(
      overrides: [memberRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await _pumpStep(tester, container: container);

    expect(find.text('My System'), findsOneWidget);
    expect(find.byType(MemberAvatar), findsNWidgets(18));
    expect(find.text('+6'), findsNothing);
  });
}
