import 'package:prism_plurality/core/router/app_routes.dart';

/// Navigation branch for member and group screens that are mounted in more
/// than one route tree.
enum MemberNavigationBranch { settings, members, groups }

extension MemberNavigationBranchPaths on MemberNavigationBranch {
  String groupPath(String groupId) {
    return switch (this) {
      MemberNavigationBranch.settings => AppRoutePaths.settingsGroup(groupId),
      MemberNavigationBranch.members => AppRoutePaths.memberGroup(groupId),
      MemberNavigationBranch.groups => AppRoutePaths.group(groupId),
    };
  }

  String memberPath(String memberId, {String? groupId}) {
    return switch (this) {
      MemberNavigationBranch.settings => AppRoutePaths.settingsMember(memberId),
      MemberNavigationBranch.members => AppRoutePaths.member(memberId),
      MemberNavigationBranch.groups =>
        groupId == null
            ? AppRoutePaths.member(memberId)
            : AppRoutePaths.groupMember(groupId, memberId),
    };
  }

  String memberFrontingHistoryPath(String memberId, {String? groupId}) {
    return switch (this) {
      MemberNavigationBranch.settings =>
        AppRoutePaths.settingsMemberFrontingHistory(memberId),
      MemberNavigationBranch.members => AppRoutePaths.memberFrontingHistory(
        memberId,
      ),
      MemberNavigationBranch.groups =>
        groupId == null
            ? AppRoutePaths.memberFrontingHistory(memberId)
            : AppRoutePaths.groupMemberFrontingHistory(groupId, memberId),
    };
  }

  String memberConversationsPath(String memberId, {String? groupId}) {
    return switch (this) {
      MemberNavigationBranch.settings =>
        AppRoutePaths.settingsMemberConversations(memberId),
      MemberNavigationBranch.members => AppRoutePaths.memberConversations(
        memberId,
      ),
      MemberNavigationBranch.groups =>
        groupId == null
            ? AppRoutePaths.memberConversations(memberId)
            : AppRoutePaths.groupMemberConversations(groupId, memberId),
    };
  }
}
