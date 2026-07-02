import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/wake_up_sleep_sheet.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime.now().subtract(const Duration(hours: 7)),
  sessionType: SessionType.sleep,
);

// Five members so that 4 fill the top row and 1 appears behind "Others…".
// With empty morningCounts and identical displayOrder, sorted by id ascending:
//   alice, bob, charlie, diana → top row
//   eve                        → Others
List<Member> _fiveMembers() => [
  _member('alice', 'Alice'),
  _member('bob', 'Bob'),
  _member('charlie', 'Charlie'),
  _member('diana', 'Diana'),
  _member('eve', 'Eve'),
];

class _FakeFrontingNotifier extends FrontingNotifier {
  final wakeUps =
      <
        ({String sleepSessionId, SleepQuality? quality, List<String> memberIds})
      >[];
  Completer<void>? wakeUpCompleter;

  @override
  Future<void> build() async {}

  @override
  Future<void> wakeUp(
    String sleepSessionId, {
    SleepQuality? quality,
    List<String> frontingMemberIds = const [],
  }) async {
    wakeUps.add((
      sleepSessionId: sleepSessionId,
      quality: quality,
      memberIds: List<String>.from(frontingMemberIds),
    ));
    await wakeUpCompleter?.future;
  }
}

class _FakeSleepNotifier extends SleepNotifier {
  final endedSessionIds = <String>[];
  Completer<void>? endSleepCompleter;

  @override
  void build() {}

  @override
  Future<void> endSleep(String sessionId) async {
    endedSessionIds.add(sessionId);
    await endSleepCompleter?.future;
  }
}

Widget _buildSubject({
  List<Member>? members,
  _FakeFrontingNotifier? notifier,
  _FakeSleepNotifier? sleepNotifier,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith(
        (ref) => Stream.value(members ?? _fiveMembers()),
      ),
      activeMemberListProvider.overrideWith(
        (ref) => Stream.value(members ?? _fiveMembers()),
      ),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      morningFrontingCountsProvider.overrideWith((ref) => Future.value({})),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      if (notifier != null)
        frontingNotifierProvider.overrideWith(() => notifier),
      if (sleepNotifier != null)
        sleepNotifierProvider.overrideWith(() => sleepNotifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: WakeUpSleepSheet(session: _sleepSession())),
    ),
  );
}

Finder _quickAvatar(String name) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == name,
);

bool _isQuickAvatarSelected(WidgetTester tester, String name) {
  return tester.widget<Semantics>(_quickAvatar(name)).properties.selected ??
      false;
}

Finder _confirmButton() => find.byWidgetPredicate(
  (widget) => widget is PrismGlassIconButton && widget.icon == AppIcons.check,
);

bool _isSearchRowSelected(WidgetTester tester, String id) {
  return tester.widget<PrismListRow>(find.byKey(ValueKey(id))).selected ??
      false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('WakeUpSleepSheet – member picker', () {
    group('top member quick choices', () {
      testWidgets('Done submits selected members through wake-up notifier', (
        tester,
      ) async {
        final notifier = _FakeFrontingNotifier();

        await tester.pumpWidget(_buildSubject(notifier: notifier));
        await tester.pumpAndSettle();

        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();
        await tester.tap(_quickAvatar('Bob'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(notifier.wakeUps, hasLength(1));
        expect(notifier.wakeUps.single.sleepSessionId, 'sleep-1');
        expect(notifier.wakeUps.single.quality, isNull);
        expect(notifier.wakeUps.single.memberIds.toSet(), {'alice', 'bob'});
      });

      testWidgets('top 4 members are rendered as named avatar tiles', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('Charlie'), findsOneWidget);
        expect(find.text('Diana'), findsOneWidget);
      });

      testWidgets('5th member is not shown directly in the top row', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        // Eve is behind "Others…" – she must not appear as a named tile.
        expect(find.text('Eve'), findsNothing);
      });

      testWidgets('multiple suggested avatars can be selected independently', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();
        await tester.tap(_quickAvatar('Bob'));
        await tester.pumpAndSettle();

        expect(_isQuickAvatarSelected(tester, 'Alice'), isTrue);
        expect(_isQuickAvatarSelected(tester, 'Bob'), isTrue);

        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();

        expect(_isQuickAvatarSelected(tester, 'Alice'), isFalse);
        expect(_isQuickAvatarSelected(tester, 'Bob'), isTrue);
      });
    });

    group('others picker opens shared sheet', () {
      testWidgets('tapping Others opens MemberSearchSheet', (tester) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsOneWidget);
      });

      testWidgets('small member sets still expose search', (tester) async {
        await tester.pumpWidget(
          _buildSubject(
            members: [_member('alice', 'Alice'), _member('bob', 'Bob')],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('wakeUpMemberSearchButton')));
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsOneWidget);
      });

      testWidgets('empty member sets still expose Unknown', (tester) async {
        await tester.pumpWidget(_buildSubject(members: const []));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('wakeUpMemberSearchButton')));
        await tester.pumpAndSettle();

        expect(find.text('Unknown'), findsOneWidget);
      });
    });

    group('selection from shared sheet', () {
      testWidgets('full sheet can select multiple members', (tester) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('bob')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('eve')));
        await tester.pumpAndSettle();
        await tester.tap(_confirmButton());
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsNothing);
        expect(_isQuickAvatarSelected(tester, 'Bob'), isTrue);
        expect(find.text('Eve'), findsOneWidget);
        expect(find.text('Others...'), findsNothing);
      });

      testWidgets('Unknown can be combined with a real member', (tester) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ValueKey(unknownSentinelMemberId)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('eve')));
        await tester.pumpAndSettle();
        await tester.tap(_confirmButton());
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsNothing);
        expect(find.text('2 selected'), findsOneWidget);
        expect(find.text('Others...'), findsNothing);

        await tester.tap(find.byKey(const Key('wakeUpMemberSearchButton')));
        await tester.pumpAndSettle();

        expect(_isSearchRowSelected(tester, unknownSentinelMemberId), isTrue);
        expect(_isSearchRowSelected(tester, 'eve'), isTrue);
      });

      testWidgets('confirming an empty selection clears previous selection', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();
        expect(_isQuickAvatarSelected(tester, 'Alice'), isTrue);

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('alice')));
        await tester.pumpAndSettle();
        await tester.tap(_confirmButton());
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsNothing);
        expect(_isQuickAvatarSelected(tester, 'Alice'), isFalse);
        expect(find.text('Others...'), findsOneWidget);
      });
    });

    group('dismissing the shared sheet', () {
      testWidgets('cancel preserves previous selection', (tester) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('eve')));
        await tester.pumpAndSettle();

        // Close via the X button in MemberSearchSheet's top bar.
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsNothing);
        expect(_isQuickAvatarSelected(tester, 'Alice'), isTrue);
        expect(find.text('Others...'), findsOneWidget);
      });
    });

    group('submission', () {
      testWidgets('Done calls wakeUp with selected members and quality', (
        tester,
      ) async {
        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(_buildSubject(notifier: notifier));
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel('Rate sleep as Good'));
        await tester.pumpAndSettle();
        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();
        await tester.tap(_quickAvatar('Bob'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(notifier.wakeUps, hasLength(1));
        expect(notifier.wakeUps.single.sleepSessionId, 'sleep-1');
        expect(notifier.wakeUps.single.quality, SleepQuality.good);
        expect(notifier.wakeUps.single.memberIds, ['alice', 'bob']);
      });

      testWidgets('Done ignores repeated taps while wake-up is pending', (
        tester,
      ) async {
        final notifier = _FakeFrontingNotifier()
          ..wakeUpCompleter = Completer<void>();
        await tester.pumpWidget(_buildSubject(notifier: notifier));
        await tester.pumpAndSettle();

        await tester.tap(_quickAvatar('Alice'));
        await tester.pumpAndSettle();

        final doneButton = find.text('Done');
        await tester.tap(doneButton);
        await tester.tap(doneButton);

        expect(notifier.wakeUps, hasLength(1));
        expect(notifier.wakeUps.single.memberIds, ['alice']);

        notifier.wakeUpCompleter!.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('Skip ignores repeated taps while sleep end is pending', (
        tester,
      ) async {
        final sleepNotifier = _FakeSleepNotifier()
          ..endSleepCompleter = Completer<void>();
        await tester.pumpWidget(_buildSubject(sleepNotifier: sleepNotifier));
        await tester.pumpAndSettle();

        final skipButton = find.text('Skip');
        await tester.tap(skipButton);
        await tester.tap(skipButton);

        expect(sleepNotifier.endedSessionIds, ['sleep-1']);

        sleepNotifier.endSleepCompleter!.complete();
        await tester.pumpAndSettle();
      });
    });
  });
}
