import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'shows timeline issue banner when issues exist',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          frontingIssueCountProvider.overrideWith(_IssueCountNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildSubject(container));
      await tester.pump();
      await tester.pump();

      expect(find.byType(InfoBanner), findsOneWidget);
      expect(find.text('Timeline issues found'), findsOneWidget);
    },
  );
}

class _IssueCountNotifier extends FrontingIssueCountNotifier {
  @override
  int build() => 2;
}
