import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/models/member_board_post_permissions.dart';

void main() {
  final now = DateTime(2026, 5, 1);

  // ── Fixture builders ──────────────────────────────────────────────────────

  Member makeMember({required String id, bool isAdmin = false}) =>
      Member(id: id, name: 'Member $id', createdAt: now, isAdmin: isAdmin);

  /// Builds a [MemberBoardPost] where [authorId] and [targetMemberId] are set
  /// to known sentinel IDs so tests can control isAuthor / isProfileOwner
  /// independently.
  MemberBoardPost makePost({
    required String audience, // 'public' | 'private'
    String authorId = 'author-id',
    String targetMemberId = 'owner-id',
  }) => MemberBoardPost(
    id: 'post-1',
    authorId: authorId,
    targetMemberId: targetMemberId,
    audience: audience,
    body: 'Hello headmates',
    createdAt: now,
    writtenAt: now,
    isDeleted: false,
  );

  /// Returns permissions for a given actor against a post.
  ///
  /// [actorIsAuthor] → actor id == post.authorId
  /// [actorIsProfileOwner] → actor id == post.targetMemberId
  /// [actorIsAdmin] → Member.isAdmin = true
  MemberBoardPostPermissions makePerms({
    required bool actorIsAuthor,
    required bool actorIsProfileOwner,
    required bool actorIsAdmin,
    required String audience,
  }) {
    // Pick IDs so the author / profile-owner flags are satisfied independently.
    // If BOTH are true the actor must match both columns in the post.
    final authorId = actorIsAuthor ? 'actor-id' : 'other-author-id';
    final targetMemberId = actorIsProfileOwner ? 'actor-id' : 'other-owner-id';

    final post = makePost(
      audience: audience,
      authorId: authorId,
      targetMemberId: targetMemberId,
    );
    final actor = makeMember(id: 'actor-id', isAdmin: actorIsAdmin);
    return MemberBoardPostPermissions(post: post, speakingAsMember: actor);
  }

  // ── Helper: expected canEdit / canDelete from the rule definitions ────────

  bool expectedCanEdit({required bool isAuthor}) => isAuthor;

  bool expectedCanDelete({
    required bool isAuthor,
    required bool isProfileOwner,
    required bool isAdmin,
  }) => isAuthor || isProfileOwner || isAdmin;

  // ── Matrix: 8 actor combos × 2 audiences = 16 cases ─────────────────────

  const audienceValues = ['public', 'private'];

  /// All 8 truth-table combinations for (isAuthor, isProfileOwner, isAdmin).
  const actorCombos = [
    (isAuthor: false, isProfileOwner: false, isAdmin: false),
    (isAuthor: true, isProfileOwner: false, isAdmin: false),
    (isAuthor: false, isProfileOwner: true, isAdmin: false),
    (isAuthor: false, isProfileOwner: false, isAdmin: true),
    (isAuthor: true, isProfileOwner: true, isAdmin: false),
    (isAuthor: true, isProfileOwner: false, isAdmin: true),
    (isAuthor: false, isProfileOwner: true, isAdmin: true),
    (isAuthor: true, isProfileOwner: true, isAdmin: true),
  ];

  for (final combo in actorCombos) {
    for (final audience in audienceValues) {
      final label = 'isAuthor=${combo.isAuthor}, '
          'isProfileOwner=${combo.isProfileOwner}, '
          'isAdmin=${combo.isAdmin}, '
          'audience=$audience';

      group('MemberBoardPostPermissions — $label', () {
        late MemberBoardPostPermissions perms;

        setUp(() {
          perms = makePerms(
            actorIsAuthor: combo.isAuthor,
            actorIsProfileOwner: combo.isProfileOwner,
            actorIsAdmin: combo.isAdmin,
            audience: audience,
          );
        });

        test('isAuthor', () => expect(perms.isAuthor, combo.isAuthor));
        test(
          'isProfileOwner',
          () => expect(perms.isProfileOwner, combo.isProfileOwner),
        );
        test('isAdmin', () => expect(perms.isAdmin, combo.isAdmin));

        test('canEdit', () {
          expect(
            perms.canEdit,
            expectedCanEdit(isAuthor: combo.isAuthor),
          );
        });

        test('canDelete', () {
          expect(
            perms.canDelete,
            expectedCanDelete(
              isAuthor: combo.isAuthor,
              isProfileOwner: combo.isProfileOwner,
              isAdmin: combo.isAdmin,
            ),
          );
        });
      });
    }
  }

  // ── Edge case: speakingAsMember = null ────────────────────────────────────

  group('MemberBoardPostPermissions — speakingAsMember = null', () {
    late MemberBoardPostPermissions perms;

    setUp(() {
      // Use a post where the author and target are real members; null actor
      // should still produce false for all action gates.
      final post = makePost(audience: 'public');
      perms = MemberBoardPostPermissions(post: post, speakingAsMember: null);
    });

    test('isAuthor is false', () => expect(perms.isAuthor, isFalse));
    test('isProfileOwner is false', () => expect(perms.isProfileOwner, isFalse));
    test('isAdmin is false', () => expect(perms.isAdmin, isFalse));
    test('canEdit is false', () => expect(perms.canEdit, isFalse));
    test('canDelete is false', () => expect(perms.canDelete, isFalse));
  });
}
