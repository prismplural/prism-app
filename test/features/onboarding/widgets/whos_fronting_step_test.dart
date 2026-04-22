import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
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
  Locale locale = const Locale('en'),
}) async {
  final repo = FakeMemberRepository()..seed(members);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [memberRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en'), Locale('es')],
        locale: locale,
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
}
