import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/services/database_health_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/database_diagnostics_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/database_diagnostics_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        nodeIdProvider.overrideWith((ref) async => 'node-1'),
        crdtLatestHlcProvider.overrideWith((ref) async => null),
        dbPathProvider.overrideWith((ref) async => '/tmp/prism.db'),
        memberCountProvider.overrideWith((ref) async => 2),
        sessionCountProvider.overrideWith((ref) async => 3),
        conversationCountProvider.overrideWith((ref) async => 4),
        pollCountProvider.overrideWith((ref) async => 5),
        healthReportProvider.overrideWith(
          (ref) => throw UnimplementedError('health check not opened'),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: DatabaseDiagnosticsScreen(),
      ),
    );
  }

  group('DatabaseDiagnosticsScreen member count', () {
    testWidgets('shows total member count by default', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Headmates'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Fronting Sessions'), findsOneWidget);
    });

    testWidgets('hides total member count when local preference is enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.hide_total_member_count': true,
      });

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Headmates'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(find.text('Fronting Sessions'), findsOneWidget);
    });
  });
}
