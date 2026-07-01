import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_fronter_choice_card.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_who_is_fronting_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

// ---------------------------------------------------------------------------
// Helper types
// ---------------------------------------------------------------------------

typedef _FronterEntry = ({String id, String name});

_FronterEntry _e(String id, String name) => (id: id, name: name);

// ---------------------------------------------------------------------------
// Widget wrapper
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

// ---------------------------------------------------------------------------
// Pure-logic tests (computeOptions)
// ---------------------------------------------------------------------------

void main() {
  // (a) Symmetric case (Prism [A], PK [B]) + bidirectional → 3 options, cofront recommended
  test('(a) symmetric + bidirectional → 3 options, cofront recommended', () {
    final options = computeOptions(
      localIds: {'A'},
      pkIds: {'B'},
      direction: PkSyncDirection.bidirectional,
    );
    expect(options.length, 3);
    // Recommended is cofront
    final recommended = options.where((o) => o.recommended).toList();
    expect(recommended.length, 1);
    expect(recommended.first.kind, FronterChoiceKind.cofront);
  });

  // (b) Symmetric + pullOnly → 2 options (cofront, usePk), usePk recommended
  test('(b) symmetric + pullOnly → 2 options, usePk recommended', () {
    final options = computeOptions(
      localIds: {'A'},
      pkIds: {'B'},
      direction: PkSyncDirection.pullOnly,
    );
    expect(options.length, 2);
    final kinds = options.map((o) => o.kind).toSet();
    expect(kinds.contains(FronterChoiceKind.usePrism), isFalse);
    expect(kinds.contains(FronterChoiceKind.cofront), isTrue);
    expect(kinds.contains(FronterChoiceKind.usePk), isTrue);
    final recommended = options.where((o) => o.recommended).toList();
    expect(recommended.length, 1);
    expect(recommended.first.kind, FronterChoiceKind.usePk);
  });

  // (c) Symmetric + pushOnly → 3 options, usePrism recommended
  test('(c) symmetric + pushOnly → 3 options, usePrism recommended', () {
    final options = computeOptions(
      localIds: {'A'},
      pkIds: {'B'},
      direction: PkSyncDirection.pushOnly,
    );
    expect(options.length, 3);
    final recommended = options.where((o) => o.recommended).toList();
    expect(recommended.length, 1);
    expect(recommended.first.kind, FronterChoiceKind.usePrism);
  });

  // (d) Collapse rule: Prism [A,B] vs PK [A] → cofront and usePrism resolve to same set
  //     → only 2 options (usePrism survives, cofront collapsed; usePk remains)
  test(
    '(d) collapse rule: Prism [A,B] vs PK [A] → usePrism and cofront same set → 2 options',
    () {
      final options = computeOptions(
        localIds: {'A', 'B'},
        pkIds: {'A'},
        direction: PkSyncDirection.bidirectional,
      );
      // usePrism={A,B}, cofront=union={A,B} → same set → collapse to 1; usePk={A} → total 2
      expect(options.length, 2);
      // The remaining option with set {A,B} should be usePrism (higher priority)
      final abOption = options.firstWhere(
        (o) => _setsEqual(o.resolvedLocalIds, {'A', 'B'}),
      );
      expect(abOption.kind, FronterChoiceKind.usePrism);
    },
  );

  // (e) Prism empty, PK [B] → 2 options (setMembers recommended, leaveNoneFronting)
  test('(e) Prism empty, PK non-empty → 2 options, setMembers recommended', () {
    final options = computeOptions(
      localIds: {},
      pkIds: {'B'},
      direction: PkSyncDirection.bidirectional,
    );
    expect(options.length, 2);
    final kinds = options.map((o) => o.kind).toList();
    expect(kinds.contains(FronterChoiceKind.setMembers), isTrue);
    expect(kinds.contains(FronterChoiceKind.leaveNoneFronting), isTrue);
    final recommended = options.where((o) => o.recommended).single;
    expect(recommended.kind, FronterChoiceKind.setMembers);
  });

  // (f) PK empty, Prism [A] → 2 options (keepMembers recommended, matchPkNone)
  test(
    '(f) PK empty, Prism non-empty → 2 options, keepMembers recommended',
    () {
      final options = computeOptions(
        localIds: {'A'},
        pkIds: {},
        direction: PkSyncDirection.bidirectional,
      );
      expect(options.length, 2);
      final kinds = options.map((o) => o.kind).toList();
      expect(kinds.contains(FronterChoiceKind.keepMembers), isTrue);
      expect(kinds.contains(FronterChoiceKind.matchPkNone), isTrue);
      final recommended = options.where((o) => o.recommended).single;
      expect(recommended.kind, FronterChoiceKind.keepMembers);
    },
  );

  // (g) Sets identical → empty list
  test('(g) sets identical → empty list', () {
    final options = computeOptions(
      localIds: {'A', 'B'},
      pkIds: {'A', 'B'},
      direction: PkSyncDirection.bidirectional,
    );
    expect(options, isEmpty);
  });

  // (h) Both empty → empty list
  test('(h) both empty → empty list', () {
    final options = computeOptions(
      localIds: {},
      pkIds: {},
      direction: PkSyncDirection.bidirectional,
    );
    expect(options, isEmpty);
  });

  // (i) Direction == disabled → empty list
  test('(i) direction disabled → empty list', () {
    final options = computeOptions(
      localIds: {'A'},
      pkIds: {'B'},
      direction: PkSyncDirection.disabled,
    );
    expect(options, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  // (j) Renders title + subtitle + N PkFronterChoiceCards
  testWidgets('(j) renders title, subtitle, and PkFronterChoiceCards', (
    tester,
  ) async {
    Set<String>? result;
    await tester.pumpWidget(
      _wrap(
        PkWhoIsFrontingSheet(
          localFronters: [_e('A', 'Alice')],
          pkFronters: [_e('B', 'Bob')],
          direction: PkSyncDirection.bidirectional,
          onResult: (r) => result = r,
        ),
      ),
    );
    await tester.pump();

    // Title and subtitle should be rendered
    expect(find.text("Who's fronting?"), findsOneWidget);
    expect(
      find.textContaining('Prism and PluralKit have different answers'),
      findsOneWidget,
    );

    // 3 cards for symmetric bidirectional case (Prism [A], PK [B])
    expect(find.byType(PkFronterChoiceCard), findsNWidgets(3));

    // "Decide later" button
    expect(find.text('Decide later'), findsOneWidget);

    // Suppress unused-variable warning
    result;
  });

  testWidgets('(j2) modal actions clear bottom system navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => PkWhoIsFrontingSheet.show(
              context: context,
              localFronters: [_e('A', 'Alice')],
              pkFronters: [_e('B', 'Bob')],
              direction: PkSyncDirection.bidirectional,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final decideLaterButton = find.widgetWithText(PrismButton, 'Decide later');
    expect(decideLaterButton, findsOneWidget);
    expect(
      tester.getBottomLeft(decideLaterButton).dy,
      lessThanOrEqualTo(800 - 48),
    );
  });

  // (k) Tapping a card calls onResult(resolvedLocalIds)
  testWidgets('(k) tapping a card calls onResult with the resolved local IDs', (
    tester,
  ) async {
    Set<String>? result;
    // Use pushOnly so "Use Prism's" (ids={'A'}) is recommended and first
    await tester.pumpWidget(
      _wrap(
        PkWhoIsFrontingSheet(
          localFronters: [_e('A', 'Alice')],
          pkFronters: [_e('B', 'Bob')],
          direction: PkSyncDirection.pushOnly,
          onResult: (r) => result = r,
        ),
      ),
    );
    await tester.pump();

    // Tap the first card (Use Prism's — ids={'A'})
    await tester.tap(find.byType(PkFronterChoiceCard).first);
    await tester.pump();

    expect(result, isNotNull);
    expect(result, equals({'A'}));
  });

  // (l) Tapping "Decide later" calls onResult(null)
  testWidgets('(l) tapping Decide later calls onResult(null)', (tester) async {
    var called = false;
    Set<String>? result = {'sentinel'};
    await tester.pumpWidget(
      _wrap(
        PkWhoIsFrontingSheet(
          localFronters: [_e('A', 'Alice')],
          pkFronters: [_e('B', 'Bob')],
          direction: PkSyncDirection.bidirectional,
          onResult: (r) {
            called = true;
            result = r;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Decide later'));
    await tester.pump();

    expect(called, isTrue);
    expect(result, isNull);
  });

  // (m) Prism empty + PK [B] → 2 cards titled by action label (asymmetric)
  testWidgets(
    '(m) Prism empty + PK [Bob] → cards titled "Set Bob fronting" and "Leave no one fronting"',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          PkWhoIsFrontingSheet(
            localFronters: const [],
            pkFronters: [_e('B', 'Bob')],
            direction: PkSyncDirection.bidirectional,
            onResult: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PkFronterChoiceCard), findsNWidgets(2));
      // Card titles must be the action labels, not the sheet title
      expect(find.text('Set Bob fronting'), findsOneWidget);
      expect(find.text('Leave no one fronting'), findsOneWidget);
      // The sheet title "Who's fronting?" must appear exactly once (in the header)
      expect(find.text("Who's fronting?"), findsOneWidget);
    },
  );

  // (n) PK empty + Prism [A] → 2 cards titled by action label (asymmetric)
  testWidgets(
    '(n) PK empty + Prism [Alice] → cards titled "Keep Alice fronting" and "Match PluralKit (no one fronting)"',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          PkWhoIsFrontingSheet(
            localFronters: [_e('A', 'Alice')],
            pkFronters: const [],
            direction: PkSyncDirection.bidirectional,
            onResult: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PkFronterChoiceCard), findsNWidgets(2));
      expect(find.text('Keep Alice fronting'), findsOneWidget);
      expect(find.text('Match PluralKit (no one fronting)'), findsOneWidget);
      // The sheet title must appear exactly once (in the header, not repeated in cards)
      expect(find.text("Who's fronting?"), findsOneWidget);
    },
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool _setsEqual<E>(Set<E> a, Set<E> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
