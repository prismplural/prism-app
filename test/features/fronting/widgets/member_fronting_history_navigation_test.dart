import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

FrontingSession _session({
  required String id,
  required String memberId,
  required DateTime start,
  required DateTime end,
}) =>
    FrontingSession(id: id, memberId: memberId, startTime: start, endTime: end);

void main() {
  testWidgets('member fronting history pushes session detail so back returns', (
    tester,
  ) async {
    final start = DateTime(2026, 4, 1, 10);
    final end = DateTime(2026, 4, 1, 11);
    final member = _member('alice', 'Alice');
    final session = _session(
      id: 's1',
      memberId: member.id,
      start: start,
      end: end,
    );

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/members/alice/fronting',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              Scaffold(body: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(body: Text('home')),
                  routes: [
                    GoRoute(
                      path: 'session/:id',
                      builder: (context, state) => Scaffold(
                        body: Column(
                          children: [
                            Text('session-${state.pathParameters['id']}'),
                            TextButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              child: const Text('Back'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/members',
                  builder: (_, _) => const Scaffold(body: Text('members')),
                  routes: [
                    GoRoute(
                      path: ':id/fronting',
                      builder: (_, state) => const Scaffold(
                        body: CustomScrollView(
                          slivers: [
                            MemberFrontingHistoryList(memberId: 'alice'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberFrontingHistoryProvider.overrideWith((ref, memberId) {
            return AsyncValue.data(
              MemberFrontingHistoryData(
                periods: [
                  FrontingPeriod(
                    start: start,
                    end: end,
                    activeMembers: [member.id],
                    briefVisitors: const [],
                    sessionIds: [session.id],
                    alwaysPresentMembers: const [],
                    isOpenEnded: false,
                  ),
                ],
                targetSessions: [session],
                hasMore: false,
              ),
            );
          }),
          membersByIdsProvider.overrideWith(
            (ref, ids) => Stream.value({member.id: member}),
          ),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('session-s1'), findsOneWidget);
    expect(router.canPop(), isTrue);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/members/alice/fronting',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member history keeps its stack through session detail edit', (
    tester,
  ) async {
    final start = DateTime(2026, 4, 1, 10);
    final end = DateTime(2026, 4, 1, 11);
    final member = _member('alice', 'Alice');
    final session = _session(
      id: 's1',
      memberId: member.id,
      start: start,
      end: end,
    );

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/members/alice/fronting',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              Scaffold(body: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(body: Text('home')),
                  routes: [
                    GoRoute(
                      path: 'session/:id',
                      builder: (_, state) => SessionDetailScreen(
                        sessionId: state.pathParameters['id']!,
                      ),
                      routes: [
                        GoRoute(
                          path: 'edit',
                          builder: (context, state) => Scaffold(
                            body: Column(
                              children: [
                                Text('edit-${state.pathParameters['id']}'),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  child: const Text('Back from edit'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/members',
                  builder: (_, _) => const Scaffold(body: Text('members')),
                  routes: [
                    GoRoute(
                      path: ':id/fronting',
                      builder: (_, state) => const Scaffold(
                        body: CustomScrollView(
                          slivers: [
                            MemberFrontingHistoryList(memberId: 'alice'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberFrontingHistoryProvider.overrideWith((ref, memberId) {
            return AsyncValue.data(
              MemberFrontingHistoryData(
                periods: [
                  FrontingPeriod(
                    start: start,
                    end: end,
                    activeMembers: [member.id],
                    briefVisitors: const [],
                    sessionIds: [session.id],
                    alwaysPresentMembers: const [],
                    isOpenEnded: false,
                  ),
                ],
                targetSessions: [session],
                hasMore: false,
              ),
            );
          }),
          membersByIdsProvider.overrideWith(
            (ref, ids) => Stream.value({member.id: member}),
          ),
          sessionByIdProvider(
            session.id,
          ).overrideWith((ref) => Stream.value(session)),
          memberByIdProvider(
            member.id,
          ).overrideWith((ref) => Stream.value(member)),
          commentsForSessionProvider(
            session.id,
          ).overrideWith((ref) => Stream.value(const [])),
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('edit-s1'), findsOneWidget);

    await tester.tap(find.text('Back from edit'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailScreen), findsOneWidget);

    await Navigator.of(
      tester.element(find.byType(SessionDetailScreen)),
    ).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/members/alice/fronting',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
