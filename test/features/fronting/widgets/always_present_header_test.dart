import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import '../../../helpers/fake_repositories.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/widgets/always_present_header.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/comments_for_range_section.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';
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

Uint8List _pngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

Future<void> _pumpHeader(
  WidgetTester tester, {
  required AsyncValue<List<AlwaysPresentMember>> value,
  FrontingTerms frontingTerms = FrontingTerms.unset,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alwaysPresentMembersProvider.overrideWithValue(value),
        frontingTermsSettingProvider.overrideWithValue(frontingTerms),
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
        expect(find.text('Long-running front · 14d 0h'), findsOneWidget);
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
      expect(find.text('Long-running fronts · 14d 0h'), findsOneWidget);
    });

    testWidgets('fronting terminology preset relabels pinned header', (
      tester,
    ) async {
      final host = _member(id: 'host', name: 'Host');
      await _pumpHeader(
        tester,
        frontingTerms: const FrontingTerms.preset(FrontingTermPreset.out),
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: host,
            session: _session('s1', 'host'),
            age: const Duration(days: 14),
          ),
        ]),
      );

      expect(find.text('Long-running out session · 14d 0h'), findsOneWidget);
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

    testWidgets('hydrates avatar photo for lightweight always-present member', (
      tester,
    ) async {
      final host = _member(id: 'host', name: 'Host', isAlwaysFronting: true);
      final header = find.byType(AlwaysPresentHeader);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alwaysPresentMembersProvider.overrideWithValue(
              AsyncValue.data([
                AlwaysPresentMember(
                  member: host,
                  session: _session('s1', 'host'),
                  age: const Duration(days: 3),
                ),
              ]),
            ),
            memberAvatarImageDataProvider.overrideWith(
              (ref, memberId) =>
                  Stream.value(memberId == 'host' ? _pngBytes() : null),
            ),
            frontingTermsSettingProvider.overrideWithValue(FrontingTerms.unset),
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

      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.byType(Image)),
        findsOneWidget,
      );
    });

    testWidgets(
      'hydrates avatar photos for lightweight always-present member group',
      (tester) async {
        final host = _member(id: 'host', name: 'Host', isAlwaysFronting: true);
        final friend = _member(
          id: 'friend',
          name: 'Friend',
          isAlwaysFronting: true,
        );
        final header = find.byType(AlwaysPresentHeader);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              alwaysPresentMembersProvider.overrideWithValue(
                AsyncValue.data([
                  AlwaysPresentMember(
                    member: host,
                    session: _session('s1', 'host'),
                    age: const Duration(days: 3),
                  ),
                  AlwaysPresentMember(
                    member: friend,
                    session: _session('s2', 'friend'),
                    age: const Duration(days: 3),
                  ),
                ]),
              ),
              memberAvatarImageDataProvider.overrideWith(
                (ref, memberId) => Stream.value(
                  memberId == 'host' || memberId == 'friend'
                      ? _pngBytes()
                      : null,
                ),
              ),
              frontingTermsSettingProvider.overrideWithValue(
                FrontingTerms.unset,
              ),
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

        expect(header, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.byType(Image)),
          findsNWidgets(2),
        );
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

      expect(find.text('Always present · 3d 0h'), findsOneWidget);
    });

    testWidgets('renders hours when duration is < 1 day', (tester) async {
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

      expect(find.text('Always present · 5h'), findsOneWidget);
    });

    testWidgets('renders minutes when duration is < 1 hour', (tester) async {
      final host = _member(id: 'host', name: 'Host', isAlwaysFronting: true);
      await _pumpHeader(
        tester,
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: host,
            session: _session('s1', 'host'),
            age: const Duration(minutes: 1),
          ),
        ]),
      );

      expect(find.text('Always present · 1m'), findsOneWidget);
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
        find.bySemanticsLabel('Long-running fronts: Host & Friend, 14d 0h'),
        findsOneWidget,
      );
    });

    testWidgets('uses singular long-running semantics for one member', (
      tester,
    ) async {
      final host = _member(id: 'host', name: 'Host');
      await _pumpHeader(
        tester,
        value: AsyncValue.data([
          AlwaysPresentMember(
            member: host,
            session: _session('s1', 'host'),
            age: const Duration(days: 14),
          ),
        ]),
      );

      expect(
        find.bySemanticsLabel('Long-running front: Host, 14d 0h'),
        findsOneWidget,
      );
    });

    for (final width in [390.0, 1440.0]) {
      testWidgets('multi-member header exposes every session at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(PrismToast.resetForTest);
        final host = _member(id: 'host', name: 'Host', isAlwaysFronting: true);
        final friend = _member(
          id: 'friend',
          name: 'Friend',
          isAlwaysFronting: true,
        );
        final sessions = [_session('s1', host.id), _session('s2', friend.id)];
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: AlwaysPresentHeader()),
            ),
            GoRoute(
              path: '/period',
              builder: (_, state) => PeriodDetailScreen(
                sessionIds: parsePeriodIds(state.uri),
                isSessionGroup: state.uri.queryParameters['mode'] == 'sessions',
              ),
            ),
            GoRoute(
              path: AppRoutePaths.session(':id'),
              builder: (_, state) =>
                  Scaffold(body: Text('session:${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: AppRoutePaths.sessionEdit(':id'),
              builder: (_, state) =>
                  Scaffold(body: Text('edit:${state.pathParameters['id']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appPreferenceRepositoryProvider.overrideWithValue(
                FakeAppPreferenceRepository(),
              ),
              alwaysPresentMembersProvider.overrideWithValue(
                AsyncValue.data([
                  AlwaysPresentMember(
                    member: host,
                    session: sessions[0],
                    age: const Duration(days: 14),
                  ),
                  AlwaysPresentMember(
                    member: friend,
                    session: sessions[1],
                    age: const Duration(days: 14),
                  ),
                ]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              derivedPeriodsProvider.overrideWith(
                (ref) => const AsyncValue.data([]),
              ),
              for (final session in sessions)
                sessionByIdProvider(
                  session.id,
                ).overrideWith((ref) => Stream.value(session)),
              membersByIdsProvider(
                memberIdsKey([host.id, friend.id]),
              ).overrideWith(
                (ref) => Stream.value({host.id: host, friend.id: friend}),
              ),
              memberAvatarImageDataProvider.overrideWith(
                (ref, memberId) => Stream.value(null),
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
        await tester.tap(find.text('Host & Friend'));
        await tester.pumpAndSettle();
        expect(find.byType(PeriodDetailScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('co-fronter-s1')), findsOneWidget);
        expect(find.byKey(const ValueKey('co-fronter-s2')), findsOneWidget);
        expect(find.byType(CommentsForRangeSection), findsNothing);
        final context = tester.element(find.byType(PeriodDetailScreen));
        final l10n = AppLocalizations.of(context);
        expect(
          find.byTooltip(l10n.frontingSessionDetailDeleteTooltip),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        if (width < 1000) {
          await tester.tap(find.byKey(const ValueKey('co-fronter-s2')));
          await tester.pumpAndSettle();
          expect(find.text('session:s2'), findsOneWidget);
          router.pop();
          await tester.pumpAndSettle();
          await tester.longPress(find.byKey(const ValueKey('co-fronter-s2')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.edit));
          await tester.pumpAndSettle();
          expect(find.text('edit:s2'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }

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
                frontingTermsSettingProvider.overrideWithValue(
                  FrontingTerms.unset,
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
