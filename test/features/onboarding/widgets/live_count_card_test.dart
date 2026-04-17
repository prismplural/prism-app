import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/widgets/live_count_card.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('empty counts → SizedBox.shrink', (tester) async {
    await tester.pumpWidget(
      _wrap(const LiveCountCard(counts: {})),
    );
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.byType(OnboardingCountRow), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('all-zero counts → SizedBox.shrink', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 0, 'fronting_sessions': 0},
        ),
      ),
    );
    expect(find.byType(OnboardingCountRow), findsNothing);
  });

  testWidgets('first non-zero entry → OnboardingCountRow renders', (tester) async {
    await tester.pumpWidget(
      _wrap(const LiveCountCard(counts: {'members': 3})),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingCountRow), findsAtLeastNWidgets(1));
  });

  testWidgets('6 non-zero entries → only 4 OnboardingCountRow widgets', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {
            'members': 1,
            'fronting_sessions': 2,
            'conversations': 3,
            'chat_messages': 4,
            'habits': 5,
            'notes': 6,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingCountRow), findsNWidgets(4));
  });

  testWidgets('jump ≥50 → TweenAnimationBuilder<int> present', (tester) async {
    final countsNotifier = ValueNotifier<Map<String, int>>({'members': 10});

    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: countsNotifier,
          builder: (_, counts, child) => LiveCountCard(counts: counts),
        ),
      ),
    );
    await tester.pumpAndSettle();

    countsNotifier.value = {'members': 200};
    await tester.pump();

    expect(find.byType(TweenAnimationBuilder<int>), findsAtLeastNWidgets(1));

    countsNotifier.dispose();
  });

  testWidgets('jump <50 → no TweenAnimationBuilder<int> for that row', (tester) async {
    final countsNotifier = ValueNotifier<Map<String, int>>({'members': 10});

    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: countsNotifier,
          builder: (_, counts, child) => LiveCountCard(counts: counts),
        ),
      ),
    );
    await tester.pumpAndSettle();

    countsNotifier.value = {'members': 15};
    await tester.pump();

    expect(find.byType(TweenAnimationBuilder<int>), findsNothing);

    countsNotifier.dispose();
  });

  testWidgets('all counts go zero after mount → card frame stays visible', (tester) async {
    final countsNotifier = ValueNotifier<Map<String, int>>({'members': 5});

    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: countsNotifier,
          builder: (_, counts, child) => LiveCountCard(counts: counts),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingCountRow), findsAtLeastNWidgets(1));

    countsNotifier.value = {'members': 0};
    await tester.pump();

    expect(find.byType(AnimatedSize), findsAtLeastNWidgets(1));

    countsNotifier.dispose();
  });

  testWidgets('members row uses neutral "System members" label', (tester) async {
    await tester.pumpWidget(
      _wrap(const LiveCountCard(counts: {'members': 3})),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('System members'), findsOneWidget);
  });

  testWidgets('disableAnimations=true → no running animations', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(counts: {'members': 5}),
        disableAnimations: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('ExcludeSemantics wraps card content', (tester) async {
    await tester.pumpWidget(
      _wrap(const LiveCountCard(counts: {'members': 3})),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExcludeSemantics), findsAtLeastNWidgets(1));
  });
}
