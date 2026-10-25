import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' hide Member;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_mention_text_field.dart';

const _aliceId = '11111111-2222-3333-4444-555555555555';
const _missingId = '66666666-7777-8888-9999-000000000000';

final _archivedAlice = Member(
  id: _aliceId,
  name: 'Alice',
  displayName: 'Alice Full',
  isActive: false,
  createdAt: DateTime(2026),
);

ProviderContainer _container({bool preferDisplayName = true}) {
  return ProviderContainer(
    overrides: [
      allMemberListProvider.overrideWithValue(
        AsyncValue.data([_archivedAlice]),
      ),
      activeMemberListProvider.overrideWithValue(const AsyncValue.data([])),
      memberNamePreferDisplayProvider.overrideWithValue(preferDisplayName),
      // Name resolution must never subscribe to full profiles or per-ID reads.
      allMembersProvider.overrideWith((ref) {
        throw StateError('Full profiles requested for mention resolution');
      }),
      activeMembersProvider.overrideWith((ref) {
        throw StateError(
          'Full active profiles requested for mention resolution',
        );
      }),
      memberByIdProvider.overrideWith((ref, id) {
        throw StateError('Per-ID profile requested before mention navigation');
      }),
    ],
  );
}

void main() {
  test(
    'existing mention names include archived members, not picker candidates',
    () {
      final container = _container();
      addTearDown(container.dispose);

      expect(
        replaceMemberMentionsWithNames(
          'Saved @[$_aliceId]',
          container.read(memberNameMapProvider),
        ),
        'Saved @Alice Full',
      );
      expect(container.read(userVisibleMemberListProvider).value, isEmpty);
    },
  );

  test(
    'archive survives database reopen, unarchive and delete resolve safely',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'mention-lifecycle-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final databaseFile = File('${directory.path}/members.sqlite');
      var db = AppDatabase(NativeDatabase(databaseFile));
      var repo = DriftMemberRepository(db.membersDao, null);
      Future<T> stage<T>(String name, Future<T> Function() action) async {
        debugPrint('mention lifecycle: $name start');
        final result = await action().timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw StateError('mention lifecycle stalled at $name'),
        );
        debugPrint('mention lifecycle: $name complete');
        return result;
      }

      addTearDown(() => stage('teardown database close', db.close));

      Future<void> expectResolution({
        required bool exists,
        required bool active,
      }) async {
        final container = ProviderContainer(
          overrides: [
            memberRepositoryProvider.overrideWithValue(repo),
            memberNamePreferDisplayProvider.overrideWithValue(true),
          ],
        );
        final allSubscription = container.listen(
          allMemberListProvider,
          (_, _) {},
        );
        final activeSubscription = container.listen(
          activeMemberListProvider,
          (_, _) {},
        );
        try {
          final all = await stage(
            'allMemberListProvider.future',
            () => container.read(allMemberListProvider.future),
          );
          await stage(
            'activeMemberListProvider.future',
            () => container.read(activeMemberListProvider.future),
          );
          expect(all.any((member) => member.id == _aliceId), exists);
          expect(
            container.read(memberNameMapProvider)[_aliceId],
            exists ? 'Alice Full' : isNull,
          );
          expect(
            container
                .read(userVisibleMemberListProvider)
                .value!
                .any((member) => member.id == _aliceId),
            active,
          );
          for (final member in all) {
            expect(member.bio, isNull);
            expect(member.avatarImageData, isNull);
            expect(member.profileHeaderImageData, isNull);
          }
        } finally {
          debugPrint('mention lifecycle: container disposal start');
          allSubscription.close();
          activeSubscription.close();
          container.dispose();
          debugPrint('mention lifecycle: container disposal complete');
        }
      }

      await stage(
        'repository create',
        () => repo.createMember(
          _archivedAlice.copyWith(isActive: true, bio: 'Private bio'),
        ),
      );
      await expectResolution(exists: true, active: true);
      await stage(
        'repository archive',
        () => repo.updateMember(_archivedAlice.copyWith(bio: 'Private bio')),
      );
      await expectResolution(exists: true, active: false);
      await stage('database close before reopen', db.close);
      db = AppDatabase(NativeDatabase(databaseFile));
      repo = DriftMemberRepository(db.membersDao, null);
      await expectResolution(exists: true, active: false);
      await stage(
        'repository unarchive',
        () => repo.updateMember(_archivedAlice.copyWith(isActive: true)),
      );
      await expectResolution(exists: true, active: true);
      await stage('repository delete', () => repo.deleteMember(_aliceId));
      await expectResolution(exists: false, active: false);
    },
  );

  testWidgets(
    'editor resolves archived labels without offering archived suggestions',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final controller = MarkdownEditingController(text: 'Saved @[$_aliceId]');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: MemberMentionTextField(
                controller: controller,
                focusNode: focus,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(TextField));
      controller.updateTheme(context);
      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 14),
        withComposing: false,
      );
      // Markdown mention spans pad hidden token offsets with U+200B.
      expect(span.toPlainText().replaceAll('\u200B', ''), 'Saved @Alice Full');
      expect(span.toPlainText().length, controller.text.length);
      expect(controller.text, 'Saved @[$_aliceId]');
      await tester.enterText(find.byType(TextField), '@Ali');
      await tester.pump();
      expect(
        find.byKey(const Key('memberMentionOverlaySurface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('archived mention names still respect canonical-name preference', () {
    final container = _container(preferDisplayName: false);
    addTearDown(container.dispose);
    expect(container.read(memberNameMapProvider)[_aliceId], 'Alice');
  });

  for (final table in [false, true]) {
    testWidgets('archived mentions resolve in ${table ? 'tables' : 'prose'}', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      final data = table
          ? '| Member |\n| --- |\n| @[$_aliceId] |'
          : 'Saved @[$_aliceId]';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PrismMarkdownText(data: data, mentionsInteractive: false),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('@Alice Full'), findsOneWidget);
      expect(find.textContaining('@Unknown'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable IDs stay noninteractive and do not open Unknown', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PrismMarkdownText(data: '@[$_missingId]')),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('@Unknown'), findsOneWidget);
    await tester.tap(find.textContaining('@Unknown'));
    await tester.pump();
    expect(find.byType(MemberDetailScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('real Unknown sentinel resolves by ID, unlike an unavailable ID', () {
    final unknown = Member(
      id: unknownSentinelMemberId,
      name: 'Unknown',
      createdAt: DateTime(2026),
    );
    final container = ProviderContainer(
      overrides: [
        allMemberListProvider.overrideWithValue(AsyncValue.data([unknown])),
        activeMemberListProvider.overrideWithValue(AsyncValue.data([unknown])),
        memberNamePreferDisplayProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final names = container.read(memberNameMapProvider);
    expect(names[unknownSentinelMemberId], 'Unknown');
    expect(names.containsKey(_missingId), isFalse);
    expect(container.read(userVisibleMemberListProvider).value, isEmpty);
  });
}
