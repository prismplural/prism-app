// The member profile's "Stats" card at large text sizes.
//
// `_StatRow` is `Row(spaceBetween, [Text(label), Text(value)])` with both sides
// unbounded, so at 2.25-3.375x the pair ran past the card that holds it. What is checked
// is that every paragraph inside each section card paints inside that card and that no
// layout error is reported; the test does not prescribe how the row should be laid out.
//
// The whole MemberDetailScreen is pumped, so an overflow on another part of that screen
// fails this test too - read the failure location before attributing it to the card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

import '../../helpers/fake_repositories.dart';
import 'rows_text_scale_harness.dart';

final _now = DateTime(2026, 5, 1, 12);

final _alice = Member(
  id: 'alice',
  name: 'Alice',
  createdAt: _now.subtract(const Duration(days: 40)),
  isActive: true,
);

Widget _memberDetail({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  Duration totalDuration = const Duration(hours: 40, minutes: 20),
  bool longValues = false,
}) {
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);

  return ProviderScope(
    overrides: [
      // No test may open the real database.
      databaseProvider.overrideWith((ref) {
        throw StateError('member detail row tests must not open a database');
      }),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(
          const SystemSettings(notesEnabled: false, boardsEnabled: false),
        ),
      ),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      memberByIdProvider(_alice.id).overrideWith((ref) => Stream.value(_alice)),
      allMembersProvider.overrideWith((ref) => Stream.value([_alice])),
      activeMembersProvider.overrideWith((ref) => Stream.value([_alice])),
      activeMemberListProvider.overrideWith((ref) => Stream.value([_alice])),
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(const <FrontingSession>[]),
      ),
      // Three stat rows, so the label/value pairs under test all render.
      memberFrontingStatsProvider(_alice.id).overrideWith(
        (ref) async => MemberFrontingStats(
          // A four-digit session count and a many-day duration are legal values;
          // the row must hold them without letting either side escape the card.
          totalSessions: longValues ? 12345 : 12,
          totalDuration: totalDuration,
          lastFronted: _now.subtract(const Duration(hours: 3)),
        ),
      ),
      memberRecentSessionsProvider(
        _alice.id,
      ).overrideWith((ref) async => <FrontingSession>[]),
      memberFrontingHistoryProvider.overrideWith(
        (ref, requestedMemberId) => const AsyncValue.data(
          MemberFrontingHistoryData(
            periods: <FrontingPeriod>[],
            targetSessions: <FrontingSession>[],
            hasMore: false,
          ),
        ),
      ),
      memberConversationActivityProvider(
        _alice.id,
      ).overrideWith((ref) async => const []),
      memberConversationPreviewActivityProvider(
        _alice.id,
      ).overrideWith((ref) async => const []),
      recentMemberNotesProvider(
        _alice.id,
      ).overrideWith((ref) => Stream.value(const [])),
      memberBoardSectionProvider(_alice.id).overrideWith(
        (ref) => Stream.value(
          const MemberBoardSection(
            publicPosts: <MemberBoardPost>[],
            totalPublic: 0,
          ),
        ),
      ),
      memberGroupsProvider(
        _alice.id,
      ).overrideWith((ref) => Stream.value(const <MemberGroup>[])),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      customFieldsProvider.overrideWith((ref) => Stream.value(const [])),
      pluralKitSyncProvider.overrideWith(
        () => _FakePluralKitSyncNotifier(
          const PluralKitSyncState(isConnected: false),
        ),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _FakePkSyncDirectionNotifier(PkSyncDirection.pullOnly),
      ),
      memberCustomFieldValuesProvider(
        _alice.id,
      ).overrideWith((ref) => Stream.value(const [])),
    ],
    child: rowsApp(
      const SizedBox.shrink(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
      routerConfig: GoRouter(
        initialLocation: '/members/${_alice.id}',
        routes: [
          GoRoute(
            path: '/members/:id',
            builder: (context, state) => MemberDetailScreen(
              memberId: state.pathParameters['id']!,
              branch: MemberNavigationBranch.members,
            ),
          ),
        ],
      ),
    ),
  );
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  _FakePluralKitSyncNotifier(this._state);

  final PluralKitSyncState _state;

  @override
  PluralKitSyncState build() => _state;
}

class _FakePkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _FakePkSyncDirectionNotifier(this._direction);

  final PkSyncDirection _direction;

  @override
  PkSyncDirection build() => _direction;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  for (final (system, app, scaleLabel) in rowsScales) {
    for (final fontFamily in rowsFontFamilies) {
      testWidgets('every profile section keeps its own text inside its card - '
          '$scaleLabel / $fontFamily', (tester) async {
        useWindow(tester, tallCompactPage);
        await tester.pumpWidget(
          _memberDetail(system: system, app: app, fontFamily: fontFamily),
        );
        await pumpUntilFound(
          tester,
          find.byType(PrismSectionCard),
          label: 'the profile sections',
        );
        await pumpUntilGone(
          tester,
          find.byType(PrismSpinner),
          label: 'profile loading',
        );

        expectNoLayoutError(
          tester,
          label: 'member detail $scaleLabel',
          ignoreCauseMatching: fixedHeightBarLayoutErrors,
        );

        final cards = find.byType(PrismSectionCard);
        expect(cards, findsWidgets, reason: 'the stats card should render');
        for (var i = 0; i < cards.evaluate().length; i++) {
          expectDescendantTextInside(
            tester,
            cards.at(i),
            label: 'member detail card $i ($scaleLabel)',
          );
        }
      });
    }
  }

  // A long value must not be able to escape the card either: a "flexible label +
  // unbounded intrinsic value" row survives the short counts above and fails
  // here, which is why the fix has to let either side take its own line.
  testWidgets(
    'long session count and duration stay inside the card at 3.375x',
    (tester) async {
      useWindow(tester, tallCompactPage);
      await tester.pumpWidget(
        _memberDetail(
          system: 2.25,
          app: 1.5,
          longValues: true,
          totalDuration: const Duration(hours: 98765, minutes: 40),
        ),
      );
      await pumpUntilFound(
        tester,
        find.byType(PrismSectionCard),
        label: 'the profile sections',
      );
      await pumpUntilGone(
        tester,
        find.byType(PrismSpinner),
        label: 'profile loading',
      );

      expectNoLayoutError(
        tester,
        label: 'member detail long values 3.375x',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
      );
      final cards = find.byType(PrismSectionCard);
      expect(cards, findsWidgets);
      for (var i = 0; i < cards.evaluate().length; i++) {
        expectDescendantTextInside(
          tester,
          cards.at(i),
          label: 'long-value card $i (3.375x)',
        );
      }
    },
  );
}
