import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

Color? resolveMemberAccentColor(
  ThemeData theme,
  Member member, {
  required bool perMemberAccentColors,
}) {
  if (!perMemberAccentColors) return null;

  final customHex = member.customColorHex?.trim();
  if (member.customColorEnabled && customHex != null && customHex.isNotEmpty) {
    return AppColors.fromHex(customHex);
  }

  return generatedMemberAccentColor(theme, member);
}

Color generatedMemberAccentColor(ThemeData theme, Member member) {
  return AppColors.generatedColor(
    stableMemberColorSeed(member),
    theme.colorScheme.primary,
    theme.brightness,
  );
}

@visibleForTesting
int stableMemberColorSeed(Member member) {
  if (member.id.isEmpty) return member.displayOrder;

  var hash = 0x811c9dc5;
  for (final codeUnit in member.id.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash % 9973;
}
