import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';

/// Permission helper for [MemberBoardPost] actions.
///
/// Rules:
/// - [canEdit]   → author only
/// - [canDelete] → author OR profile-owner OR admin
///
/// Mirrors [ConversationPermissions] in structure; pure-Dart with no
/// provider or UI dependencies.
class MemberBoardPostPermissions {
  const MemberBoardPostPermissions({
    required this.post,
    required this.speakingAsMember,
  });

  final MemberBoardPost post;

  /// The member currently acting. `null` when no one is selected (e.g. no
  /// active fronter); all permission getters return `false` in that case.
  final Member? speakingAsMember;

  /// True when [speakingAsMember] authored this post.
  bool get isAuthor => post.authorId == speakingAsMember?.id;

  /// True when [speakingAsMember] is the member whose profile this post is on
  /// (i.e. [MemberBoardPost.targetMemberId] matches).
  bool get isProfileOwner => post.targetMemberId == speakingAsMember?.id;

  /// True when [speakingAsMember] holds the admin role.
  bool get isAdmin => speakingAsMember?.isAdmin ?? false;

  /// Only the author may edit their own post.
  bool get canEdit => isAuthor;

  /// Authors, profile-owners, and admins may delete a post.
  bool get canDelete => isAuthor || isProfileOwner || isAdmin;
}
