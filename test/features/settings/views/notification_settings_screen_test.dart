import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/settings/views/notification_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  testWidgets(
    'custom suppress duration OK saves without closing settings route',
    (tester) async {
      final prefs = FakeAppPreferenceRepository()
        ..seed(frontingReminderSuppressMinutesPreference, 5);
      final settings = FakeSystemSettingsRepository()
        ..settings = const SystemSettings(
          frontingRemindersEnabled: true,
          frontingReminderIntervalMinutes: 60,
        );
      addTearDown(prefs.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferenceRepositoryProvider.overrideWithValue(prefs),
            systemSettingsRepositoryProvider.overrideWithValue(settings),
            notificationPermissionProvider.overrideWith((ref) async => true),
          ],
          child: const _NestedNavigatorApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('5 minutes'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Custom').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '42');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(await prefs.get(frontingReminderSuppressMinutesPreference), 42);
      expect(find.text('Skip reminder for'), findsNothing);
      expect(find.text('Notifications'), findsOneWidget);
    },
  );
}

class _NestedNavigatorApp extends StatelessWidget {
  const _NestedNavigatorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const NotificationSettingsScreen(),
        ),
      ),
    );
  }
}
