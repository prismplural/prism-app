import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/services/auth_policy_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/views/fronting_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(body: FrontingBannerStack(theme: ThemeData.light())),
      ),
    );
  }

  testWidgets(
    'stacks home banners with backup reminder above timeline issues',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          backupReminderDueProvider.overrideWith((ref) async => true),
          frontingIssueCountProvider.overrideWith(_IssueCountNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildSubject(container));
      await tester.pump();
      await tester.pump();

      expect(find.byType(InfoBanner), findsNWidgets(2));

      final backupTitle = find.text('Have you backed up your recovery phrase?');
      final timelineTitle = find.text('Timeline issues found');
      expect(backupTitle, findsOneWidget);
      expect(timelineTitle, findsOneWidget);
      expect(
        tester.getTopLeft(backupTitle).dy,
        lessThan(tester.getTopLeft(timelineTitle).dy),
      );
    },
  );
}

class _IssueCountNotifier extends FrontingIssueCountNotifier {
  @override
  int build() => 2;
}
