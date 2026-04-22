import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/whos_fronting_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

final Uint8List _avatarBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO4B7WQAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('localizes avatar semantics labels', (tester) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    final repo = FakeMemberRepository()
      ..seed([
        Member(
          id: 'alex',
          name: 'Alex',
          avatarImageData: _avatarBytes,
          createdAt: DateTime(2026, 4, 22),
        ),
      ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [memberRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: const Scaffold(body: WhosFrontingStep()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(semanticsWithLabel('Avatar de Alex'), findsOneWidget);
  });
}
