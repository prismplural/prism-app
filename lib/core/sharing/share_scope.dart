import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Permission scopes for friend sharing, ordered from least to most access.
///
/// Each higher scope implicitly includes all lower scopes.
enum ShareScope {
  frontStatusOnly,
  memberProfiles,
  frontHistory,
  fullAccess,
}

extension ShareScopeX on ShareScope {
  String get displayName => switch (this) {
        ShareScope.frontStatusOnly => 'Front Status Only',
        ShareScope.memberProfiles => 'Member Profiles',
        ShareScope.frontHistory => 'Front History',
        ShareScope.fullAccess => 'Full Access',
      };

  String get description => switch (this) {
        ShareScope.frontStatusOnly =>
          'Who\'s currently fronting and since when',
        ShareScope.memberProfiles =>
          'Member names, pronouns, emoji, and avatars',
        ShareScope.frontHistory => 'Full fronting session history',
        ShareScope.fullAccess => 'All system data including chat and polls',
      };

  IconData get icon => switch (this) {
        ShareScope.frontStatusOnly => AppIcons.personOutline,
        ShareScope.memberProfiles => AppIcons.peopleOutline,
        ShareScope.frontHistory => AppIcons.history,
        ShareScope.fullAccess => AppIcons.lockOpen,
      };

  /// Whether this scope includes another scope.
  ///
  /// Higher-index scopes include all lower-index scopes.
  bool includes(ShareScope other) => index >= other.index;
}
