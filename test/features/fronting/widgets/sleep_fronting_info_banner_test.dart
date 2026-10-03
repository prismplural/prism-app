import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/fronting/widgets/sleep_fronting_info_banner.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget subject({VoidCallback? onOpenSettings}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SleepFrontingInfoBanner(onOpenSettings: onOpenSettings ?? () {}),
    ),
  );

  testWidgets('dismissal persists across visits', (tester) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    expect(find.text('Choose what happens during sleep'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    expect(find.text('Choose what happens during sleep'), findsNothing);
  });

  testWidgets('settings action opens settings and dismisses the hint', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(subject(onOpenSettings: () => opened = true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep settings'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.text('Choose what happens during sleep'), findsNothing);
  });
}
