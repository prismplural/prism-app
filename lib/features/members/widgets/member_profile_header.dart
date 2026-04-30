import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/birthday.dart';
import 'package:prism_plurality/features/members/utils/member_profile_header_resolver.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

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
  });

  final Member member;
  final bool isFronting;
  final MemberProfileHeaderSource? source;
  final MemberProfileHeaderLayout? layout;
  final bool? visible;
  final Uint8List? prismHeaderImageData;
  final Uint8List? pluralKitHeaderImageData;

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
      );
    }

    return _ClassicMemberProfileHeader(
      member: member,
      isFronting: isFronting,
      imageData: resolution.activeImageData!,
    );
  }
}

class _CompactMemberProfileHeader extends StatelessWidget {
  const _CompactMemberProfileHeader({
    required this.member,
    required this.isFronting,
    required this.imageData,
  });

  final Member member;
  final bool isFronting;
  final Uint8List? imageData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imageData != null && imageData!.isNotEmpty;

    Widget child = Padding(
      padding: hasImage ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MemberHeaderAvatar(member: member, size: 80),
          const SizedBox(width: 16),
          Expanded(
            child: _MemberHeaderMetadata(
              member: member,
              isFronting: isFronting,
              foregroundColor: hasImage ? Colors.white : null,
              secondaryColor: hasImage
                  ? Colors.white.withValues(alpha: 0.82)
                  : null,
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
  });

  final Member member;
  final bool isFronting;
  final Uint8List imageData;

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
            Positioned.fill(
              child: ClipRRect(
                borderRadius: radius,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: -42,
              child: _MemberHeaderAvatar(member: member, size: 96),
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
          ),
        ),
      ],
    );
  }
}

class _MemberHeaderAvatar extends StatelessWidget {
  const _MemberHeaderAvatar({required this.member, required this.size});

  final Member member;
  final double size;

  @override
  Widget build(BuildContext context) {
    return MemberAvatar(
      avatarImageData: member.avatarImageData,
      memberName: member.name,
      emoji: member.emoji,
      customColorEnabled: member.customColorEnabled,
      customColorHex: member.customColorHex,
      size: size,
      showBorder: true,
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
  });

  final Member member;
  final bool isFronting;
  final Color? foregroundColor;
  final Color? secondaryColor;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = foregroundColor ?? theme.colorScheme.onSurface;
    final secondary = secondaryColor ?? theme.colorScheme.onSurfaceVariant;
    final birthday = _birthdayDisplay(context, member);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          member.name,
          style:
              titleStyle ??
              theme.textTheme.headlineSmall?.copyWith(
                color: primary,
                fontWeight: FontWeight.bold,
              ),
        ),
        if (member.displayName != null &&
            member.displayName!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            member.displayName!.trim(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: secondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (member.pronouns != null && member.pronouns!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            member.pronouns!,
            style: theme.textTheme.titleMedium?.copyWith(color: secondary),
          ),
        ],
        if (member.age != null) ...[
          const SizedBox(height: 2),
          Text(
            context.l10n.memberAgeDisplay(member.age!),
            style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
          ),
        ],
        if (birthday != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.calendarTodayOutlined, size: 16, color: secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  birthday,
                  style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _statusChips(context, theme, primary),
        ),
      ],
    );
  }

  List<Widget> _statusChips(
    BuildContext context,
    ThemeData theme,
    Color foreground,
  ) {
    final chips = <Widget>[];
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
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
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
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 4),
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
