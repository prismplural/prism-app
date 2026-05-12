import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

enum _Tab { a, b }

Widget _harness({
  required int? badgeACount,
  String? badgeASemanticLabel,
  int? badgeBCount,
  String? badgeBSemanticLabel,
  _Tab selected = _Tab.a,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: PrismSegmentedControl<_Tab>(
            segments: [
              PrismSegment(
                value: _Tab.a,
                label: 'Alpha',
                badgeCount: badgeACount,
                badgeSemanticLabel: badgeASemanticLabel,
              ),
              PrismSegment(
                value: _Tab.b,
                label: 'Beta',
                badgeCount: badgeBCount,
                badgeSemanticLabel: badgeBSemanticLabel,
              ),
            ],
            selected: selected,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('PrismSegmentedControl badges', () {
    testWidgets('renders no badge text when badgeCount is null', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(badgeACount: null));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('9+'), findsNothing);
    });

    testWidgets('renders no badge text when badgeCount is 0', (tester) async {
      await tester.pumpWidget(_harness(badgeACount: 0));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders the count when badgeCount is 5', (tester) async {
      await tester.pumpWidget(_harness(badgeACount: 5));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('caps at "9+" when badgeCount exceeds 9', (tester) async {
      await tester.pumpWidget(_harness(badgeACount: 15));
      await tester.pumpAndSettle();

      expect(find.text('9+'), findsOneWidget);
      expect(find.text('15'), findsNothing);
    });

    testWidgets('exposes badgeSemanticLabel via Semantics', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(
          badgeACount: 3,
          badgeASemanticLabel: '3 unread direct messages',
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      // Badge Semantics wraps the Text child, so the merged label contains
      // both the caller-provided semantic label and the raw "3".
      expect(
        find.bySemanticsLabel(RegExp(r'3 unread direct messages')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
