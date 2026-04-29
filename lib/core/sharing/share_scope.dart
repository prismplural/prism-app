import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Permission scopes for friend sharing, ordered from least to most access.
///
/// Each higher scope implicitly includes all lower scopes.
enum ShareScope { frontStatusOnly, memberProfiles, frontHistory, fullAccess }

extension ShareScopeX on ShareScope {
  String displayNameFor({String termPlural = 'Member'}) => switch (this) {
    ShareScope.frontStatusOnly => 'Front Status Only',
    ShareScope.memberProfiles => '$termPlural Profiles',
    ShareScope.frontHistory => 'Front History',
    ShareScope.fullAccess => 'Full Access',
  };

  String get displayName => displayNameFor();

  String descriptionFor({String termSingular = 'Member'}) => switch (this) {
    ShareScope.frontStatusOnly => 'Who\'s currently fronting and since when',
    ShareScope.memberProfiles =>
      '$termSingular names, pronouns, emoji, and avatars',
    ShareScope.frontHistory => 'Full fronting session history',
    ShareScope.fullAccess => 'All system data including chat and polls',
  };

  String get description => descriptionFor();

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
