import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/widgets/always_present_header.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';

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
        terminologySettingProvider.overrideWithValue((
          term: SystemTerminology.headmates,
          customSingular: null,
          customPlural: null,
          useEnglish: false,
        )),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en'), Locale('es')],
        locale: Locale('en'),
        home: Scaffold(body: AlwaysPresentHeader()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AlwaysPresentHeader', () {
    testWidgets('empty list collapses to SizedBox.shrink', (tester) async {
      await _pumpHeader(tester, value: const AsyncValue.data([]));
      expect(find.textContaining('Always present'), findsNothing);
    });

    testWidgets('loading state collapses to SizedBox.shrink', (tester) async {
      await _pumpHeader(tester, value: const AsyncValue.loading());
      expect(find.textContaining('Always present'), findsNothing);
    });

    testWidgets(
      'long-running sessions show the long-running label, not "Always present"',
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
        expect(find.text('Long-running · 2 weeks'), findsOneWidget);
        expect(find.textContaining('Always present'), findsNothing);
      },
    );

    testWidgets('joins names for two qualifying members with ampersand', (
      tester,
    ) async {
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
      expect(find.text('Long-running · 2 weeks'), findsOneWidget);
    });

    testWidgets(
      'uses the shared group avatar for multiple qualifying members',
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

        expect(find.byType(GroupMemberAvatar), findsOneWidget);
        expect(find.text('+2'), findsNothing);
      },
    );

    testWidgets('explicit always-fronting members keep the label', (
      tester,
    ) async {
      final host = _member(id: 'host', name: 'Host', isAlwaysFronting: true);
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

    testWidgets('renders hours bucket when duration is < 1 day', (
      tester,
    ) async {
      final host = _member(id: 'host', name: 'Host', isAlwaysFronting: true);
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

    testWidgets('uses long-running semantics when the member is not explicit', (
      tester,
    ) async {
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

      expect(
        find.bySemanticsLabel(
          'Long-running fronters: Host & Friend, 2 weeks. Double tap to view details.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tap opens the qualifying session detail route', (
      tester,
    ) async {
      final member = _member(id: 'host', name: 'Host');
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => ProviderScope(
              overrides: [
                alwaysPresentMembersProvider.overrideWithValue(
                  AsyncValue.data([
                    AlwaysPresentMember(
                      member: member,
                      session: _session('s1', 'host'),
                      age: const Duration(days: 14),
                    ),
                  ]),
                ),
                terminologySettingProvider.overrideWithValue((
                  term: SystemTerminology.headmates,
                  customSingular: null,
                  customPlural: null,
                  useEnglish: false,
                )),
              ],
              child: const Scaffold(body: AlwaysPresentHeader()),
            ),
          ),
          GoRoute(
            path: AppRoutePaths.session(':id'),
            builder: (context, state) =>
                Text('session:${state.pathParameters['id']}'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Host'));
      await tester.pumpAndSettle();

      expect(find.text('session:s1'), findsOneWidget);
    });
  });
}
