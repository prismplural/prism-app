// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/domain/repositories/member_board_posts_repository.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider, SpeakingAsNotifier;
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/image_size_field.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeClipboardReader implements AppClipboardReader {
  const _FakeClipboardReader({this.image});

  final ClipboardImageData? image;

  @override
  Future<ClipboardImageData?> readImage({
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
  }) async => image;

  @override
  Future<ClipboardImageData?> readImageUri(String uri) async => null;
}

class _FakeSpeakingAsNotifier extends SpeakingAsNotifier {
  _FakeSpeakingAsNotifier([this._id]);
  final String? _id;

  @override
  String? build() => _id;
}

class _FakeComposerDefaultNotifier extends ComposerDefaultMemberNotifier {
  _FakeComposerDefaultNotifier(this._mode);
  final ComposerDefaultMember _mode;

  @override
  Future<ComposerDefaultMember> build() async => _mode;
}

class _FakeBoardPostNotifier extends MemberBoardPostNotifier {
  @override
  Future<void> build() async {}
}

class _FakeRepository implements MemberBoardPostsRepository {
  @override
  Future<MemberBoardPost?> getPostById(String id) async => null;
  @override
  Future<void> createPost(MemberBoardPost post) async {}
  @override
  Future<void> updatePost(MemberBoardPost post) async {}
  @override
  Future<void> softDeletePost(String id) async {}
  @override
  Future<void> markInboxOpenedFor(List<String> activeFronterIds) async {}
  @override
  Stream<List<MemberBoardPost>> watchPublicPaginated({
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) => Stream.value(const []);
  @override
  Stream<List<MemberBoardPost>> watchInboxPaginated(
    List<String> targetMemberIds, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) => Stream.value(const []);
  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberPaginated(
    String memberId, {
    DateTime? afterWrittenAt,
    String? afterId,
    int limit = 30,
  }) => Stream.value(const []);
  @override
  Stream<List<MemberBoardPost>> watchPublicForMemberRecent(
    String memberId, {
    int limit = 3,
  }) => Stream.value(const []);
  @override
  Stream<MemberBoardPost?> watchPostById(String id) => Stream.value(null);
}

void main() {
  final alice = Member(
    id: 'alice',
    name: 'Alice',
    createdAt: DateTime(2026, 1, 1),
    isActive: true,
  );

  Widget buildSubject(AppClipboardReader reader) {
    return ProviderScope(
      overrides: [
        appClipboardReaderProvider.overrideWithValue(reader),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        speakingAsProvider.overrideWith(() => _FakeSpeakingAsNotifier('alice')),
        composerDefaultMemberProvider.overrideWith(
          () => _FakeComposerDefaultNotifier(ComposerDefaultMember.latestFronter),
        ),
        activeSessionsProvider.overrideWithValue(const AsyncValue.data([])),
        activeMembersProvider.overrideWith((ref) => Stream.value([alice])),
        userVisibleMembersProvider.overrideWith(
          (ref) => AsyncValue.data([alice]),
        ),
        allGroupsProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWith(
          (ref) => Stream.value(const <MemberGroupEntry>[]),
        ),
        memberByIdProvider('alice').overrideWith((ref) => Stream.value(alice)),
        memberBoardPostsRepositoryProvider.overrideWithValue(_FakeRepository()),
        memberBoardPostNotifierProvider.overrideWith(_FakeBoardPostNotifier.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => ComposePostSheet.show(
                ctx,
                defaultTargetMemberId: null,
                defaultAudience: 'public',
                defaultTitle: null,
                defaultBody: null,
                editingPostId: null,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'pasting an image into the compose body opens the add-image dialog',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          _FakeClipboardReader(
            image: ClipboardImageData(
              bytes: _kTransparentPngBytes,
              mimeType: 'image/png',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(ImageSizeField), findsNothing);

      // The body field is the last TextField. Pasting through it exercises the
      // GlobalKey threaded from the sheet state down through _EditorMarkdownActions
      // to the MarkdownImageButton — the most fragile wiring in this change.
      final bodyField = find.byType(TextField).last;
      await tester.tap(bodyField);
      await tester.pump();
      Actions.invoke(
        tester.element(bodyField),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ImageSizeField), findsOneWidget);
    },
  );
}

final Uint8List _kTransparentPngBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
