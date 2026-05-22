import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/member_accent_color.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

Member _member({
  String id = 'member-1',
  bool customColorEnabled = false,
  String? customColorHex,
}) {
  return Member(
    id: id,
    name: 'Alice',
    createdAt: DateTime(2026, 5, 9),
    customColorEnabled: customColorEnabled,
    customColorHex: customColorHex,
  );
}

void main() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.prismPurpleLight),
  );

  group('resolveMemberAccentColor', () {
    test('automatic setting off still uses a custom profile color', () {
      final color = resolveMemberAccentColor(
        theme,
        _member(customColorEnabled: true, customColorHex: '#FF0000'),
        perMemberAccentColors: false,
      );

      expect(color, AppColors.fromHex('#FF0000'));
    });

    test('automatic setting off suppresses generated accents', () {
      final color = resolveMemberAccentColor(
        theme,
        _member(),
        perMemberAccentColors: false,
      );

      expect(color, isNull);
    });

    test('global setting on uses a custom profile color when enabled', () {
      final color = resolveMemberAccentColor(
        theme,
        _member(customColorEnabled: true, customColorHex: '#FF0000'),
        perMemberAccentColors: true,
      );

      expect(color, AppColors.fromHex('#FF0000'));
    });

    test('global setting on generates an accent without profile reticking', () {
      final member = _member();
      final color = resolveMemberAccentColor(
        theme,
        member,
        perMemberAccentColors: true,
      );

      expect(color, generatedMemberAccentColor(theme, member));
      expect(color, isNot(theme.colorScheme.primary));
    });

    test('disabled custom profile color falls back to generated accent', () {
      final member = _member(
        customColorEnabled: false,
        customColorHex: '#FF0000',
      );
      final color = resolveMemberAccentColor(
        theme,
        member,
        perMemberAccentColors: true,
      );

      expect(color, generatedMemberAccentColor(theme, member));
    });
  });
}
