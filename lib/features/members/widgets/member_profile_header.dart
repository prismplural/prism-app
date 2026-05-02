import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/birthday.dart';
import 'package:prism_plurality/features/members/utils/member_name_style.dart';
import 'package:prism_plurality/features/members/utils/member_profile_header_resolver.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

class MemberProfileHeader extends StatelessWidget {
  const MemberProfileHeader({
    super.key,
    required this.member,
    this.isFronting = false,
    this.source,
    this.layout,
    this.visible,
    this.prismHeaderImageData,
    this.pluralKitHeaderImageData,
    this.onAvatarTap,
    this.onAvatarRemove,
    this.onNameStyleTap,
  });

  final Member member;
  final bool isFronting;
  final MemberProfileHeaderSource? source;
  final MemberProfileHeaderLayout? layout;
  final bool? visible;
  final Uint8List? prismHeaderImageData;
  final Uint8List? pluralKitHeaderImageData;
  final VoidCallback? onNameStyleTap;

  /// When set, tapping the avatar invokes this callback and a camera badge
  /// is shown to indicate the avatar is editable.
  final VoidCallback? onAvatarTap;

  /// When set and the member has an avatar image, a small remove control is
  /// rendered in the corner of the avatar.
  final VoidCallback? onAvatarRemove;

  @override
  Widget build(BuildContext context) {
    final resolution = resolveMemberProfileHeader(
      member,
      sourceOverride: source,
      layoutOverride: layout,
      visibleOverride: visible,
      prismImageDataOverride: prismHeaderImageData,
      pluralKitImageDataOverride: pluralKitHeaderImageData,
    );

    if (!resolution.hasImage ||
        resolution.layout == MemberProfileHeaderLayout.compactBackground) {
      return _CompactMemberProfileHeader(
        member: member,
        isFronting: isFronting,
        imageData: resolution.activeImageData,
        onAvatarTap: onAvatarTap,
        onAvatarRemove: onAvatarRemove,
        onNameStyleTap: onNameStyleTap,
      );
    }

    return _ClassicMemberProfileHeader(
      member: member,
      isFronting: isFronting,
      imageData: resolution.activeImageData!,
      onAvatarTap: onAvatarTap,
      onAvatarRemove: onAvatarRemove,
      onNameStyleTap: onNameStyleTap,
    );
  }
}

class _CompactMemberProfileHeader extends StatelessWidget {
  const _CompactMemberProfileHeader({
    required this.member,
    required this.isFronting,
    required this.imageData,
    this.onAvatarTap,
    this.onAvatarRemove,
    this.onNameStyleTap,
  });

  final Member member;
  final bool isFronting;
  final Uint8List? imageData;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onAvatarRemove;
  final VoidCallback? onNameStyleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imageData != null && imageData!.isNotEmpty;

    Widget child = Padding(
      padding: hasImage ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MemberHeaderAvatar(
            member: member,
            size: 80,
            onTap: onAvatarTap,
            onRemove: onAvatarRemove,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _MemberHeaderMetadata(
              member: member,
              isFronting: isFronting,
              foregroundColor: hasImage ? Colors.white : null,
              secondaryColor: hasImage
                  ? Colors.white.withValues(alpha: 0.82)
                  : null,
              applyTextShadow: hasImage,
              onNameStyleTap: onNameStyleTap,
            ),
          ),
        ],
      ),
    );

    if (!hasImage) return child;

    child = ClipRRect(
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(20)),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: _HeaderImage(
              imageData: imageData!,
              semanticLabel: '${member.name} profile header',
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.62),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(20)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ClassicMemberProfileHeader extends StatelessWidget {
  const _ClassicMemberProfileHeader({
    required this.member,
    required this.isFronting,
    required this.imageData,
    this.onAvatarTap,
    this.onAvatarRemove,
    this.onNameStyleTap,
  });

  final Member member;
  final bool isFronting;
  final Uint8List imageData;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onAvatarRemove;
  final VoidCallback? onNameStyleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(PrismShapes.of(context).radius(20));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: AspectRatio(
                aspectRatio: 3,
                child: _HeaderImage(
                  imageData: imageData,
                  semanticLabel: '${member.name} profile header',
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: -42,
              child: _MemberHeaderAvatar(
                member: member,
                size: 96,
                onTap: onAvatarTap,
                onRemove: onAvatarRemove,
              ),
            ),
          ],
        ),
        const SizedBox(height: 54),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _MemberHeaderMetadata(
            member: member,
            isFronting: isFronting,
            titleStyle: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            onNameStyleTap: onNameStyleTap,
          ),
        ),
      ],
    );
  }
}

class _MemberHeaderAvatar extends StatelessWidget {
  const _MemberHeaderAvatar({
    required this.member,
    required this.size,
    this.onTap,
    this.onRemove,
  });

  final Member member;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        member.avatarImageData != null && member.avatarImageData!.isNotEmpty;
    final theme = Theme.of(context);

    final avatar = MemberAvatar(
      avatarImageData: member.avatarImageData,
      memberName: member.name,
      emoji: member.emoji,
      customColorEnabled: member.customColorEnabled,
      customColorHex: member.customColorHex,
      size: size,
      showBorder: true,
      flushImage: true,
    );

    if (onTap == null && onRemove == null) return avatar;

    final badgeSize = (size * 0.28).clamp(24.0, 36.0);

    final Widget tappable = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        tappable,
        if (onTap != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: IgnorePointer(
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  AppIcons.cameraAlt,
                  size: badgeSize * 0.55,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        if (onRemove != null && hasImage)
          Positioned(
            right: -4,
            top: -4,
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    AppIcons.close,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemberHeaderMetadata extends StatelessWidget {
  const _MemberHeaderMetadata({
    required this.member,
    required this.isFronting,
    this.foregroundColor,
    this.secondaryColor,
    this.titleStyle,
    this.applyTextShadow = false,
    this.onNameStyleTap,
  });

  final Member member;
  final bool isFronting;
  final Color? foregroundColor;
  final Color? secondaryColor;
  final TextStyle? titleStyle;
  final bool applyTextShadow;
  final VoidCallback? onNameStyleTap;

  static const List<Shadow> _onImageShadows = [
    Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = foregroundColor ?? theme.colorScheme.onSurface;
    final secondary = secondaryColor ?? theme.colorScheme.onSurfaceVariant;
    final birthday = _birthdayDisplay(context, member);
    final shadows = applyTextShadow ? _onImageShadows : null;

    final displayName = member.displayName?.trim();
    final hasDisplayName = displayName != null && displayName.isNotEmpty;
    final primaryTitle = hasDisplayName ? displayName : member.name;
    final secondaryTitle = hasDisplayName ? member.name : null;

    final pronouns = member.pronouns?.trim();
    final hasPronouns = pronouns != null && pronouns.isNotEmpty;
    final titleCharBudget =
        primaryTitle.length +
        (secondaryTitle != null ? secondaryTitle.length + 3 : 0);
    final pronounsInline =
        hasPronouns && titleCharBudget + pronouns.length + 3 <= 30;

    final baseHeadlineStyle =
        titleStyle ??
        theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold) ??
        const TextStyle(fontSize: 24, fontWeight: FontWeight.bold);
    final headlineStyle = resolveMemberNameTextStyle(
      context,
      member,
      baseHeadlineStyle,
      defaultColor: primary,
      shadows: shadows,
    );
    final secondaryTitleStyle = headlineStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: secondary,
    );
    final inlinePronounsStyle = theme.textTheme.titleMedium?.copyWith(
      color: secondary,
      shadows: shadows,
    );

    final chips = _buildChips(
      context: context,
      theme: theme,
      foreground: primary,
      secondary: secondary,
      pronouns: pronounsInline ? null : pronouns,
      birthday: birthday,
      shadows: shadows,
    );

    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: primaryTitle, style: headlineStyle),
          if (secondaryTitle != null)
            TextSpan(text: '  ($secondaryTitle)', style: secondaryTitleStyle),
          if (pronounsInline)
            TextSpan(text: '  · $pronouns', style: inlinePronounsStyle),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final titleRow = onNameStyleTap == null
        ? title
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 6),
              PrismIconButton(
                icon: AppIcons.textFields,
                tooltip: context.l10n.memberNameStyleTooltip,
                semanticLabel: context.l10n.memberNameStyleTooltip,
                size: 32,
                iconSize: 17,
                color: primary,
                onPressed: onNameStyleTap!,
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ],
    );
  }

  List<Widget> _buildChips({
    required BuildContext context,
    required ThemeData theme,
    required Color foreground,
    required Color secondary,
    required String? pronouns,
    required String? birthday,
    required List<Shadow>? shadows,
  }) {
    final chips = <Widget>[];

    final infoBg = applyTextShadow
        ? Colors.white.withValues(alpha: 0.16)
        : theme.colorScheme.surfaceContainerHighest;
    final infoFg = applyTextShadow
        ? Colors.white.withValues(alpha: 0.92)
        : theme.colorScheme.onSurfaceVariant;

    if (pronouns != null && pronouns.isNotEmpty) {
      chips.add(
        _Chip(
          label: pronouns,
          backgroundColor: infoBg,
          foregroundColor: infoFg,
        ),
      );
    }
    if (member.age != null) {
      chips.add(
        _Chip(
          label: context.l10n.memberAgeDisplay(member.age!),
          backgroundColor: infoBg,
          foregroundColor: infoFg,
        ),
      );
    }
    if (birthday != null) {
      chips.add(
        _Chip(
          icon: AppIcons.calendarTodayOutlined,
          label: birthday,
          backgroundColor: infoBg,
          foregroundColor: infoFg,
        ),
      );
    }
    if (isFronting) {
      chips.add(
        _Chip(
          icon: AppIcons.flashOn,
          label: context.l10n.memberFrontingChip,
          backgroundColor: AppColors.fronting(
            theme.brightness,
          ).withValues(alpha: 0.15),
          foregroundColor:
              foregroundColor ?? AppColors.fronting(theme.brightness),
        ),
      );
    }
    if (member.isAdmin) {
      chips.add(
        _Chip(
          icon: AppIcons.shieldOutlined,
          label: context.l10n.memberAdminChip,
          backgroundColor: theme.colorScheme.tertiaryContainer,
          foregroundColor: theme.colorScheme.onTertiaryContainer,
        ),
      );
    }
    if (!member.isActive) {
      chips.add(
        _Chip(
          icon: AppIcons.visibilityOffOutlined,
          label: context.l10n.memberInactiveChip,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          foregroundColor: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return chips;
  }
}

class _HeaderImage extends StatelessWidget {
  const _HeaderImage({required this.imageData, required this.semanticLabel});

  final Uint8List imageData;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pixelWidth = (width * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Image.memory(
      imageData,
      fit: BoxFit.cover,
      width: double.infinity,
      cacheWidth: pixelWidth,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData? icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(999),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String? _birthdayDisplay(BuildContext context, Member member) {
  final parsed = parseBirthday(member.birthday);
  if (parsed == null) return null;
  return formatBirthdayDisplay(
    parsed,
    Localizations.localeOf(context).toString(),
  );
}
