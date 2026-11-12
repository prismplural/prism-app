import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/features/boards/views/post_detail_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Regression coverage for prism-app#2 in the post detail view: the body must be
/// selectable/copyable through a [SelectionArea] (not a read-only text field).

final _now = DateTime(2026, 5, 1);

final _alice = Member(id: 'alice', name: 'Alice', createdAt: _now);
final _bob = Member(id: 'bob', name: 'Bob', createdAt: _now);

MemberBoardPost _post({String body = 'Synthetic post'}) => MemberBoardPost(
  id: 'post',
  authorId: 'alice',
  targetMemberId: 'bob',
  audience: 'public',
  body: body,
  createdAt: _now,
  writtenAt: _now,
);

class _PostRepository implements MemberBoardPostsRepository {
  _PostRepository(this.post);

  final MemberBoardPost post;

  @override
  Stream<MemberBoardPost?> watchPostById(String id) => Stream.value(post);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpDetail(WidgetTester tester, MemberBoardPost post) async {
  final members = [_alice, _bob];
  final container = ProviderContainer(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      activeMemberListProvider.overrideWith((ref) => Stream.value(members)),
      userVisibleMemberListProvider.overrideWith(
        (ref) => AsyncValue.data(members),
      ),
      memberByIdProvider.overrideWith(
        (ref, id) => Stream.value(members.where((m) => m.id == id).firstOrNull),
      ),
      allGroupsProvider.overrideWith((ref) => Stream.value(<MemberGroup>[])),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(<MemberGroupEntry>[]),
      ),
      memberBoardPostsRepositoryProvider.overrideWithValue(
        _PostRepository(post),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PostDetailScreen(postId: 'post'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final clipboardWrites = <String>[];

  setUp(() {
    clipboardWrites.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            clipboardWrites.add(args['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('detail body copies its text via SelectionArea', (tester) async {
    await _pumpDetail(tester, _post(body: 'Hello headmates!'));

    final body = find.descendant(
      of: find.byType(SelectionArea),
      matching: find.byType(RichText),
    );
    expect(body, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getTopLeft(body) + const Offset(2, 6),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getTopRight(body) + const Offset(-2, 6));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(clipboardWrites, isNotEmpty);
    expect(clipboardWrites.last, contains('Hello headmates'));
  });

  testWidgets('detail body keeps plain-text semantics', (tester) async {
    await _pumpDetail(tester, _post(body: 'Hello headmates!'));

    final area = find.byType(SelectionArea);
    expect(area, findsOneWidget);
    // A read-only text field would announce itself as an editable input and
    // duplicate the post's semantics; SelectionArea keeps a RenderParagraph.
    expect(
      find.descendant(of: area, matching: find.byType(SelectableText)),
      findsNothing,
    );
    expect(
      find.descendant(of: area, matching: find.byType(EditableText)),
      findsNothing,
    );
  });
}
