import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

Color? resolveMemberNameColor(
  BuildContext context,
  Member member, {
  Color? defaultColor,
}) {
  return switch (member.nameStyleColorMode) {
    MemberNameColorMode.standard => defaultColor,
    MemberNameColorMode.accent => _memberAccentColor(context, member),
    MemberNameColorMode.custom =>
      _tryParseHex(member.nameStyleColorHex) ??
          _memberAccentColor(context, member),
  };
}

TextStyle resolveMemberNameTextStyle(
  BuildContext context,
  Member member,
  TextStyle baseStyle, {
  Color? defaultColor,
  List<Shadow>? shadows,
}) {
  final style = baseStyle.copyWith(
    color: resolveMemberNameColor(
      context,
      member,
      defaultColor: defaultColor ?? baseStyle.color,
    ),
    fontWeight: member.nameStyleBold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: member.nameStyleItalic ? FontStyle.italic : FontStyle.normal,
    shadows: shadows,
  );

  switch (member.nameStyleFont) {
    case MemberNameFont.standard:
      return style;
    case MemberNameFont.display:
      return style.copyWith(fontFamily: 'Unbounded');
    case MemberNameFont.serif:
      return style.copyWith(
        fontFamily: 'Georgia',
        fontFamilyFallback: const ['Cambria', 'Times New Roman', 'serif'],
      );
    case MemberNameFont.mono:
      return style.copyWith(
        fontFamily: 'ui-monospace',
        fontFamilyFallback: const [
          'SFMono-Regular',
          'Menlo',
          'Consolas',
          'monospace',
        ],
      );
    case MemberNameFont.rounded:
      return style.copyWith(
        fontFamily: 'ui-rounded',
        fontFamilyFallback: const [
          '.SF Pro Rounded',
          'SF Pro Rounded',
          'Roboto',
          'sans-serif',
        ],
      );
  }
}

String memberNameColorHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color _memberAccentColor(BuildContext context, Member member) {
  final memberColor = member.customColorEnabled
      ? _tryParseHex(member.customColorHex)
      : null;
  return memberColor ?? Theme.of(context).colorScheme.primary;
}

Color? _tryParseHex(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;
  final cleaned = hex.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return null;
  try {
    return AppColors.fromHex(cleaned);
  } catch (_) {
    return null;
  }
}
