import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/widgets/live_count_card.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  const headmatesTerminology = SystemTerminology.headmates;
  const membersTerminology = SystemTerminology.members;
  const altersTerminology = SystemTerminology.alters;
  const partsTerminology = SystemTerminology.parts;

  testWidgets('empty counts → SizedBox.shrink', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(counts: {}, terminology: headmatesTerminology),
      ),
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
          terminology: headmatesTerminology,
        ),
      ),
    );
    expect(find.byType(OnboardingCountRow), findsNothing);
  });

  testWidgets('first non-zero entry → OnboardingCountRow renders', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 3},
          terminology: headmatesTerminology,
        ),
      ),
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
          terminology: headmatesTerminology,
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
          builder: (_, counts, child) => LiveCountCard(
            counts: counts,
            terminology: headmatesTerminology,
          ),
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
          builder: (_, counts, child) => LiveCountCard(
            counts: counts,
            terminology: headmatesTerminology,
          ),
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
          builder: (_, counts, child) => LiveCountCard(
            counts: counts,
            terminology: headmatesTerminology,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingCountRow), findsAtLeastNWidgets(1));

    countsNotifier.value = {'members': 0};
    await tester.pump();

    // Container frame stays mounted once _hasEverMounted is true;
    // AnimatedSize collapses to empty but is still in the tree.
    expect(find.byType(AnimatedSize), findsAtLeastNWidgets(1));

    countsNotifier.dispose();
  });

  testWidgets('terminology headmates → label contains "Headmates"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 3},
          terminology: headmatesTerminology,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Headmates'), findsAtLeastNWidgets(1));
  });

  testWidgets('terminology members → label contains "Members"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 3},
          terminology: membersTerminology,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Members'), findsAtLeastNWidgets(1));
  });

  testWidgets('terminology alters → label contains "Alters"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 3},
          terminology: altersTerminology,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Alters'), findsAtLeastNWidgets(1));
  });

  testWidgets('terminology parts → label contains "Parts"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 3},
          terminology: partsTerminology,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Parts'), findsAtLeastNWidgets(1));
  });

  testWidgets('disableAnimations=true → no running animations', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 5},
          terminology: headmatesTerminology,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('ExcludeSemantics wraps card content', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LiveCountCard(
          counts: {'members': 3},
          terminology: headmatesTerminology,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExcludeSemantics), findsAtLeastNWidgets(1));
  });
}
