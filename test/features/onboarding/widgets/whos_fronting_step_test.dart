import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/whos_fronting_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

import '../../../helpers/fake_repositories.dart';

final Uint8List _avatarBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO4B7WQAAAAASUVORK5CYII=',
);

Member _member({
  required String id,
  required String name,
  Uint8List? avatarImageData,
}) => Member(
  id: id,
  name: name,
  avatarImageData: avatarImageData,
  createdAt: DateTime(2026, 4, 22),
);

Future<void> _pumpStep(
  WidgetTester tester, {
  required List<Member> members,
  List<FrontingSession> activeSessions = const [],
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  final repo = FakeMemberRepository()..seed(members);
  final frontingRepo = FakeFrontingSessionRepository()
    ..sessions.addAll(activeSessions);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(repo),
        frontingSessionRepositoryProvider.overrideWithValue(frontingRepo),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en'), Locale('es')],
        locale: locale,
        theme: theme,
        home: const Scaffold(body: WhosFrontingStep()),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('small systems keep the member grid', (tester) async {
    await _pumpStep(
      tester,
      members: [
        _member(id: 'alex', name: 'Alex'),
        _member(id: 'bea', name: 'Bea'),
      ],
    );

    expect(find.byType(GridView), findsOneWidget);
    expect(
      find.byKey(const Key('onboardingFrontingSearchTrigger')),
      findsNothing,
    );
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
  });

  testWidgets('small systems also expose shared search', (tester) async {
    await _pumpStep(
      tester,
      members: [
        _member(id: 'alex', name: 'Alex'),
        _member(id: 'bea', name: 'Bea'),
      ],
    );

    await tester.tap(find.byKey(const Key('onboardingFrontingSearchButton')));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bea');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bea')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WhosFrontingStep)),
    );
    expect(container.read(onboardingProvider).selectedFronterId, 'bea');
  });

  testWidgets('small system member cards use the active theme surface color', (
    tester,
  ) async {
    const cardColor = Color(0xFFE2F4EF);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
      ).copyWith(surfaceContainer: cardColor),
    );

    await _pumpStep(
      tester,
      theme: theme,
      members: [
        _member(id: 'alex', name: 'Alex'),
        _member(id: 'bea', name: 'Bea'),
      ],
    );

    final cardFinder = find.ancestor(
      of: find.text('Alex'),
      matching: find.byType(AnimatedContainer),
    );
    final card = tester.widget<AnimatedContainer>(cardFinder.first);
    final decoration = card.decoration as BoxDecoration;

    expect(decoration.color, cardColor);
  });

  testWidgets('large systems use shared search and update selection', (
    tester,
  ) async {
    final members = List.generate(
      16,
      (index) => _member(id: 'member-$index', name: 'Member $index'),
    );

    await _pumpStep(tester, members: members);

    expect(find.byType(GridView), findsNothing);
    expect(
      find.byKey(const Key('onboardingFrontingSearchTrigger')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('onboardingFrontingSearchTrigger')));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);

    await tester.enterText(find.byType(TextField), '15');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('member-15')));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsNothing);
    expect(find.text('Member 15'), findsOneWidget);
  });

  testWidgets('localizes avatar semantics labels', (tester) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    await _pumpStep(
      tester,
      locale: const Locale('es'),
      members: [
        _member(id: 'alex', name: 'Alex', avatarImageData: _avatarBytes),
      ],
    );

    expect(semanticsWithLabel('Avatar de Alex'), findsOneWidget);
  });

  testWidgets('reflects imported active fronters as already selected', (
    tester,
  ) async {
    await _pumpStep(
      tester,
      members: [
        _member(id: 'alex', name: 'Alex'),
        _member(id: 'bea', name: 'Bea'),
      ],
      activeSessions: [
        FrontingSession(
          id: 'active-alex',
          memberId: 'alex',
          startTime: DateTime(2026, 5, 6, 8),
        ),
        FrontingSession(
          id: 'active-bea',
          memberId: 'bea',
          startTime: DateTime(2026, 5, 6, 8),
        ),
      ],
    );

    expect(
      find.text('Profiles imported under \u201cFronting\u201d: Alex, Bea'),
      findsOneWidget,
    );
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets('skip button advances without choosing a replacement fronter', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        memberRepositoryProvider.overrideWithValue(
          FakeMemberRepository()..seed([_member(id: 'alex', name: 'Alex')]),
        ),
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
    addTearDown(container.dispose);
    container.read(onboardingProvider.notifier).state = const OnboardingState(
      currentStep: OnboardingStep.whosFronting,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en'), Locale('es')],
          home: Scaffold(body: WhosFrontingStep()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    expect(container.read(onboardingProvider).selectedFronterId, 'alex');

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(container.read(onboardingProvider).selectedFronterId, isNull);
    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.complete,
    );
  });
}
