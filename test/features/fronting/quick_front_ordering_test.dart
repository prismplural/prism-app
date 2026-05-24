import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Member _m(String id, String name, {int displayOrder = 0}) => Member(
  id: id,
  name: name,
  createdAt: DateTime(2026, 1, 1),
  displayOrder: displayOrder,
);

FrontingSession _session(String memberId, DateTime startTime) =>
    FrontingSession(
      id: 'session-$memberId',
      startTime: startTime,
      memberId: memberId,
    );

Widget _harness({
  required List<Member> members,
  required List<FrontingSession> activeSessions,
  Map<String, int> counts = const {},
  double width = 400,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(activeSessions),
      ),
      memberFrontingCountsProvider.overrideWith((ref) async => counts),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: SizedBox(width: width, child: const QuickFrontSection()),
      ),
    ),
  );
}

List<String> _renderedTileOrderByName(
  WidgetTester tester,
  List<Member> members,
) {
  // Sort visible member labels by left edge — works in both layouts without
  // crawling the element tree.
  final entries = <MapEntry<String, double>>[];
  for (final member in members) {
    final finder = find.text(member.name);
    if (finder.evaluate().isEmpty) continue;
    entries.add(MapEntry(member.id, tester.getTopLeft(finder.first).dx));
  }
  entries.sort((a, b) => a.value.compareTo(b.value));
  return [for (final e in entries) e.key];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no fronters: fills slots with frequent picks, no scroll', (
    tester,
  ) async {
    final members = [
      _m('a', 'Alex'),
      _m('b', 'Bea'),
      _m('c', 'Cy'),
      _m('d', 'Dev'),
      _m('e', 'Eli'),
    ];

    await tester.pumpWidget(
      _harness(
        members: members,
        activeSessions: const [],
        counts: {'a': 10, 'b': 8, 'c': 6, 'd': 4, 'e': 2},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    expect(_renderedTileOrderByName(tester, members), ['a', 'b', 'c', 'd']);
  });

  testWidgets(
    'two fronters: 2 current + 2 frequent fill 4 slots, no scroll, current first',
    (tester) async {
      final members = [
        _m('a', 'Alex'),
        _m('b', 'Bea'),
        _m('c', 'Cy'),
        _m('d', 'Dev'),
        _m('e', 'Eli'),
      ];
      final t = DateTime(2026, 1, 1, 12);
      final sessions = [
        _session('a', t),
        _session('c', t.add(const Duration(minutes: 5))),
      ];

      await tester.pumpWidget(
        _harness(
          members: members,
          activeSessions: sessions,
          counts: {'d': 10, 'e': 8, 'b': 1},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(_renderedTileOrderByName(tester, members), ['c', 'a', 'd', 'e']);
    },
  );

  testWidgets(
    'three+ fronters: scroll mode, all current first then 4 frequent picks',
    (tester) async {
      // Three members start in one gesture, rows share startTime. Pre-fix
      // only one of the three rendered; now all three must, in displayOrder
      // not database-rowid order.
      final members = [
        _m('bianca', 'Bianca', displayOrder: 10),
        _m('irena', 'Irena', displayOrder: 20),
        _m('olek', 'Olek', displayOrder: 30),
        _m('mischa', 'Mischa', displayOrder: 40),
        _m('frank', 'Frank', displayOrder: 50),
        _m('greta', 'Greta', displayOrder: 60),
        _m('hugo', 'Hugo', displayOrder: 70),
      ];
      final t = DateTime(2026, 1, 1, 12);
      final sessions = [
        _session('bianca', t),
        _session('irena', t),
        _session('olek', t),
      ];

      await tester.pumpWidget(
        _harness(
          members: members,
          activeSessions: sessions,
          counts: {'mischa': 10, 'frank': 8, 'greta': 6, 'hugo': 4},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      // Scroll mode wraps the scroll view in a ShaderMask so the cut edge
      // fades — without it the bar reads as "this is everyone."
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(_renderedTileOrderByName(tester, members), [
        'bianca',
        'irena',
        'olek',
        'mischa',
        'frank',
        'greta',
        'hugo',
      ]);
    },
  );

  testWidgets(
    'simultaneous fronters break startTime ties by displayOrder, not selection order',
    (tester) async {
      final members = [
        _m('z', 'Zed', displayOrder: 5),
        _m('a', 'Alex', displayOrder: 10),
      ];
      final t = DateTime(2026, 1, 1, 12);
      // Session order opposite of expected display order, to prove the sort
      // isn't accidentally preserving input order.
      final sessions = [_session('a', t), _session('z', t)];

      await tester.pumpWidget(
        _harness(members: members, activeSessions: sessions, counts: const {}),
      );
      await tester.pumpAndSettle();

      // No frequent picks available (no non-fronters), so just the 2 tiles.
      expect(_renderedTileOrderByName(tester, members), ['z', 'a']);
    },
  );

  testWidgets('wider viewport shows more slots before scrolling kicks in', (
    tester,
  ) async {
    // 600 / 88 ≈ 6 slots, so two fronters + four frequent fit without scroll.
    final members = [
      _m('a', 'Alex'),
      _m('b', 'Bea'),
      _m('c', 'Cy'),
      _m('d', 'Dev'),
      _m('e', 'Eli'),
      _m('f', 'Fae'),
      _m('g', 'Gus'),
    ];
    final t = DateTime(2026, 1, 1, 12);
    final sessions = [
      _session('a', t),
      _session('b', t.add(const Duration(minutes: 1))),
    ];

    await tester.pumpWidget(
      _harness(
        members: members,
        activeSessions: sessions,
        counts: {'c': 10, 'd': 8, 'e': 6, 'f': 4, 'g': 2},
        width: 600,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(_renderedTileOrderByName(tester, members), [
      'b',
      'a',
      'c',
      'd',
      'e',
      'f',
    ]);
  });
}
