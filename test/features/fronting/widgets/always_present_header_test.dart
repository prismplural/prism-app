import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/widgets/always_present_header.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Member _member({
  required String id,
  String? name,
  bool isAlwaysFronting = false,
}) {
  return Member(
    id: id,
    name: name ?? id,
    createdAt: DateTime(2025, 1, 1),
    isAlwaysFronting: isAlwaysFronting,
  );
}

FrontingSession _session(String id, String memberId) {
  return FrontingSession(
    id: id,
    memberId: memberId,
    startTime: DateTime.now().subtract(const Duration(days: 14)),
  );
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required AsyncValue<List<AlwaysPresentMember>> value,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alwaysPresentMembersProvider.overrideWithValue(value),
      ],
      // ignore: prefer_const_constructors — `value` is non-const.
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en'), Locale('es')],
        locale: const Locale('en'),
        home: const Scaffold(body: AlwaysPresentHeader()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AlwaysPresentHeader', () {
    testWidgets('empty list collapses to SizedBox.shrink', (tester) async {
      await _pumpHeader(tester, value: const AsyncValue.data([]));

      // No "Always present" subtitle text rendered.
      expect(find.textContaining('Always present'), findsNothing);
    });

    testWidgets('loading state collapses to SizedBox.shrink', (tester) async {
      await _pumpHeader(tester, value: const AsyncValue.loading());

      expect(find.textContaining('Always present'), findsNothing);
    });

    testWidgets('renders name + duration label for one qualifying member',
        (tester) async {
      final member = _member(id: 'host', name: 'Host');
      await _pumpHeader(
        tester,
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: member,
            session: _session('s1', 'host'),
            age: const Duration(days: 14),
          ),
        ]),
      );

      expect(find.text('Host'), findsOneWidget);
      // Duration falls in the weeks bucket → "2 weeks".
      expect(find.text('Always present · 2 weeks'), findsOneWidget);
    });

    testWidgets('joins names for two qualifying members with ampersand',
        (tester) async {
      final host = _member(id: 'host', name: 'Host');
      final friend = _member(id: 'friend', name: 'Friend');
      await _pumpHeader(
        tester,
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: host,
            session: _session('s1', 'host'),
            age: const Duration(days: 21),
          ),
          AlwaysPresentMember(
            member: friend,
            session: _session('s2', 'friend'),
            age: const Duration(days: 14),
          ),
        ]),
      );

      expect(find.text('Host & Friend'), findsOneWidget);
      // Shortest age wins for the duration → 2 weeks.
      expect(find.text('Always present · 2 weeks'), findsOneWidget);
    });

    testWidgets(
      'shows +N pill when more than three members qualify (avatar cap)',
      (tester) async {
        final members = [
          for (var i = 0; i < 5; i++) _member(id: 'm$i', name: 'M$i'),
        ];
        await _pumpHeader(
          tester,
          value: AsyncValue.data([
            for (var i = 0; i < 5; i++)
              AlwaysPresentMember(
                member: members[i],
                session: _session('s$i', 'm$i'),
                age: const Duration(days: 10),
              ),
          ]),
        );

        // 5 members, cap is 3 → "+2" pill in the avatar row.
        expect(find.text('+2'), findsOneWidget);
      },
    );

    testWidgets('renders days bucket when duration is < 1 week', (tester) async {
      // Reachable only via explicit-always-fronting (auto-promote is 7d).
      final host = _member(
        id: 'host',
        name: 'Host',
        isAlwaysFronting: true,
      );
      await _pumpHeader(
        tester,
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: host,
            session: _session('s1', 'host'),
            age: const Duration(days: 3),
          ),
        ]),
      );

      expect(find.text('Always present · 3 days'), findsOneWidget);
    });

    testWidgets('renders hours bucket when duration is < 1 day', (tester) async {
      final host = _member(
        id: 'host',
        name: 'Host',
        isAlwaysFronting: true,
      );
      await _pumpHeader(
        tester,
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: host,
            session: _session('s1', 'host'),
            age: const Duration(hours: 5),
          ),
        ]),
      );

      expect(find.text('Always present · 5 hours'), findsOneWidget);
    });

    testWidgets(
      'wraps a single Semantics container that combines names + duration',
      (tester) async {
        final host = _member(id: 'host', name: 'Host');
        final friend = _member(id: 'friend', name: 'Friend');
        await _pumpHeader(
          tester,
          value: AsyncValue.data([
            AlwaysPresentMember(
              member: host,
              session: _session('s1', 'host'),
              age: const Duration(days: 14),
            ),
            AlwaysPresentMember(
              member: friend,
              session: _session('s2', 'friend'),
              age: const Duration(days: 14),
            ),
          ]),
        );

        // The combined Semantics label should match the localized
        // template — names then duration.
        expect(
          find.bySemanticsLabel(
            'Always-present fronters: Host & Friend, 2 weeks',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
