import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Data for a single member in a group avatar.
class GroupAvatarMember {
  final String? memberId;
  final Uint8List? avatarImageData;
  final String emoji;
  final bool customColorEnabled;
  final String? customColorHex;
  final bool deferAvatarLookup;

  const GroupAvatarMember({
    this.memberId,
    this.avatarImageData,
    this.emoji = '❔',
    this.customColorEnabled = false,
    this.customColorHex,
    this.deferAvatarLookup = false,
  });
}

/// A circular avatar that composites multiple member emoji/images inside
/// a single glass circle. Supports 1–4 members visually.
///
/// - 1 member: delegates to [MemberAvatar]
/// - 2 members: side-by-side, each taking half the circle
/// - 3 members: top row of 2, bottom row of 1 centered
/// - 4 members: 2×2 grid
///
/// Any members beyond 4 are ignored visually (data model supports unlimited).
class GroupMemberAvatar extends ConsumerWidget {
  const GroupMemberAvatar({
    super.key,
    required this.members,
    this.size = 40,
    this.tint,
  });

  final List<GroupAvatarMember> members;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (members.isEmpty) {
      return SizedBox.square(dimension: size);
    }
    final terms = watchTerminology(context, ref);

    final resolved = _resolveVisibleMembers(ref);

    if (resolved.length == 1) {
      final m = resolved.first;
      return MemberAvatar(
        avatarImageData: m.avatarImageData,
        memberId: m.memberId,
        deferAvatarLookup: m.deferAvatarLookup,
        emoji: m.emoji,
        customColorEnabled: m.customColorEnabled,
        customColorHex: m.customColorHex,
        size: size,
        tintOverride: tint,
      );
    }

    final visible = resolved.take(4).toList();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final avatarColors = _groupAvatarColors(context, visible);
    final accentBorderColor = avatarColors.border.withValues(
      alpha: isDark
          ? PrismTokens.avatarAccentBorderAlphaDark
          : PrismTokens.avatarAccentBorderAlphaLight,
    );

    final angular = PrismShapes.of(context).cornerStyle == CornerStyle.angular;
    final clipper = angular
        ? ClipRRect(
            borderRadius: BorderRadius.zero,
            child: SizedBox.square(
              dimension: size,
              child: _buildLayout(context, visible, size, terms),
            ),
          )
        : ClipOval(
            child: SizedBox.square(
              dimension: size,
              child: _buildLayout(context, visible, size, terms),
            ),
          );

    return TintedGlassSurface.circle(
      size: size,
      tint: avatarColors.tint,
      tintStrength: PrismTokens.avatarTintAlpha,
      borderColor: accentBorderColor,
      borderWidth: 1,
      child: clipper,
    );
  }

  List<GroupAvatarMember> _resolveVisibleMembers(WidgetRef ref) {
    return [
      for (final member in members)
        if (member.avatarImageData == null &&
            member.deferAvatarLookup &&
            member.memberId != null)
          GroupAvatarMember(
            memberId: member.memberId,
            avatarImageData: ref
                .watch(memberAvatarImageDataProvider(member.memberId!))
                .whenOrNull(data: (bytes) => bytes),
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            deferAvatarLookup: true,
          )
        else
          member,
    ];
  }

  ({Color tint, Color border}) _groupAvatarColors(
    BuildContext context,
    List<GroupAvatarMember> visible,
  ) {
    final theme = Theme.of(context);
    final rawTint =
        tint ?? _firstCustomColor(visible) ?? theme.colorScheme.primary;
    final rawBorder = _firstDistinctCustomColor(visible, rawTint) ?? rawTint;
    return (
      tint: _adjustGroupAccent(context, rawTint),
      border: _adjustGroupAccent(context, rawBorder),
    );
  }

  Color _adjustGroupAccent(BuildContext context, Color rawColor) {
    final theme = Theme.of(context);
    final adjustmentBackground = theme.brightness == Brightness.dark
        ? prismDarkAccentBackground
        : prismLightAccentBackground;
    return contrastAdjustedAccent(rawColor, adjustmentBackground);
  }

  Color? _firstCustomColor(List<GroupAvatarMember> visible) {
    for (final member in visible) {
      if (!member.customColorEnabled || member.customColorHex == null) {
        continue;
      }
      return AppColors.fromHex(member.customColorHex!);
    }
    return null;
  }

  Color? _firstDistinctCustomColor(
    List<GroupAvatarMember> visible,
    Color base,
  ) {
    final baseValue = base.toARGB32();
    for (final member in visible) {
      if (!member.customColorEnabled || member.customColorHex == null) {
        continue;
      }
      final color = AppColors.fromHex(member.customColorHex!);
      if (color.toARGB32() != baseValue) return color;
    }
    return null;
  }

  Widget _buildLayout(
    BuildContext context,
    List<GroupAvatarMember> visible,
    double containerSize,
    Terminology terms,
  ) {
    final itemSize = containerSize * 0.48;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    switch (visible.length) {
      case 2:
        // Diagonal overlap: first member top-left, second bottom-right
        final dualSize = containerSize * 0.6;
        final offset = containerSize * 0.18;
        return Stack(
          children: [
            Positioned(
              top: offset * 0.3,
              left: offset * 0.3,
              child: _miniAvatar(context, visible[0], dualSize, dpr, terms),
            ),
            Positioned(
              bottom: offset * 0.3,
              right: offset * 0.3,
              child: _miniAvatar(context, visible[1], dualSize, dpr, terms),
            ),
          ],
        );
      case 3:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniAvatar(context, visible[0], itemSize * 0.9, dpr, terms),
                _miniAvatar(context, visible[1], itemSize * 0.9, dpr, terms),
              ],
            ),
            _miniAvatar(context, visible[2], itemSize * 0.9, dpr, terms),
          ],
        );
      case 4:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniAvatar(context, visible[0], itemSize * 0.85, dpr, terms),
                _miniAvatar(context, visible[1], itemSize * 0.85, dpr, terms),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniAvatar(context, visible[2], itemSize * 0.85, dpr, terms),
                _miniAvatar(context, visible[3], itemSize * 0.85, dpr, terms),
              ],
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _miniAvatar(
    BuildContext context,
    GroupAvatarMember member,
    double itemSize,
    double devicePixelRatio,
    Terminology terms,
  ) {
    if (member.avatarImageData != null && member.avatarImageData!.isNotEmpty) {
      final pixelSize = (itemSize * devicePixelRatio).ceil();
      final image = Image.memory(
        member.avatarImageData!,
        width: itemSize,
        height: itemSize,
        fit: BoxFit.cover,
        cacheWidth: pixelSize,
        cacheHeight: pixelSize,
        // See MemberAvatar — Drift re-emits member rows during PK sync with
        // fresh Uint8List instances; MemoryImage equality is identity-based,
        // so without gaplessPlayback every emit clears this frame briefly.
        gaplessPlayback: true,
        semanticLabel: context.l10n.groupMemberAvatarSemantics(
          terms.singularLower,
        ),
        errorBuilder: (_, _, _) => _miniEmoji(member.emoji, itemSize),
      );
      final angular =
          PrismShapes.of(context).cornerStyle == CornerStyle.angular;
      return angular
          ? ClipRRect(borderRadius: BorderRadius.zero, child: image)
          : ClipOval(child: image);
    }
    return _miniEmoji(member.emoji, itemSize);
  }

  Widget _miniEmoji(String emoji, double itemSize) {
    return SizedBox.square(
      dimension: itemSize,
      child: Center(
        child: MemberAvatar.centeredEmoji(emoji, fontSize: itemSize * 0.6),
      ),
    );
  }
}
