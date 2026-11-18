import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/preferences/member_name_presentation.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/members/utils/birthday.dart';
import 'package:prism_plurality/features/members/utils/member_name_style.dart';
import 'package:prism_plurality/features/members/utils/member_profile_header_resolver.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Key for the single pronoun capsule in [MemberProfileHeader].
///
/// There is exactly one such capsule when the member has pronouns, and none
/// when the stored string is empty or whitespace.
const Key memberProfilePronounsCapsuleKey = Key('memberProfilePronounsCapsule');

/// How wide, in ems of the capsule's own text-scaled font size, the header must
/// be before the pronoun capsule stays in the avatar column.
///
/// At or below this width the capsule moves under the avatar and uses the full
/// header width, matching the selected design reference ("about 15 em of the
/// pronoun text size"). The em is measured through the ambient [TextScaler] at
/// the body-medium role, so large and nonlinear text settings move the capsule
/// instead of squeezing the text.
const double memberProfilePronounsBesideAvatarMinEm = 15;

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

class _CompactMemberProfileHeader extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasImage = imageData != null && imageData!.isNotEmpty;
    final resolvedName = member.effectiveName(
      preferDisplayName: ref.watch(memberNamePreferDisplayProvider),
    );

    final identity = _resolveMemberHeaderIdentity(
      context,
      ref,
      member: member,
      isFronting: isFronting,
      foregroundColor: hasImage ? Colors.white : null,
      secondaryColor: hasImage ? Colors.white.withValues(alpha: 0.82) : null,
      applyTextShadow: hasImage,
      onNameStyleTap: onNameStyleTap,
    );

    Widget child = Padding(
      padding: hasImage ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avatar = _MemberHeaderAvatar(
            member: member,
            size: 80,
            onTap: onAvatarTap,
            onRemove: onAvatarRemove,
          );
          final pronounsBelowAvatar =
              identity.pronouns != null &&
              _pronounsNeedFullHeaderWidth(context, constraints.maxWidth);

          if (!pronounsBelowAvatar) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                avatar,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      identity.nameBlock,
                      if (identity.pronouns != null) ...[
                        const SizedBox(height: 8),
                        identity.pronouns!,
                      ],
                      if (identity.statusChips != null) ...[
                        const SizedBox(height: 8),
                        identity.statusChips!,
                      ],
                    ],
                  ),
                ),
              ],
            );
          }

          // Narrow for the current text size: the capsule (and the status chips
          // under it) leave the avatar column and use the full header width.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(child: identity.nameBlock),
                ],
              ),
              const SizedBox(height: 12),
              identity.pronouns!,
              if (identity.statusChips != null) ...[
                const SizedBox(height: 8),
                identity.statusChips!,
              ],
            ],
          );
        },
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
              semanticLabel: context.l10n.profileHeaderSemantic(resolvedName),
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

class _ClassicMemberProfileHeader extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(PrismShapes.of(context).radius(20));
    final resolvedName = member.effectiveName(
      preferDisplayName: ref.watch(memberNamePreferDisplayProvider),
    );
    // The classic layout already gives the identity cluster the full header
    // width under the banner, so the capsule never needs to move.
    final identity = _resolveMemberHeaderIdentity(
      context,
      ref,
      member: member,
      isFronting: isFronting,
      titleStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      onNameStyleTap: onNameStyleTap,
    );

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
                  semanticLabel: context.l10n.profileHeaderSemantic(
                    resolvedName,
                  ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              identity.nameBlock,
              if (identity.pronouns != null) ...[
                const SizedBox(height: 8),
                identity.pronouns!,
              ],
              if (identity.statusChips != null) ...[
                const SizedBox(height: 8),
                identity.statusChips!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberHeaderAvatar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage =
        member.avatarImageData != null && member.avatarImageData!.isNotEmpty;
    final theme = Theme.of(context);

    final avatar = MemberAvatar(
      avatarImageData: member.avatarImageData,
      memberName: member.effectiveName(
        preferDisplayName: ref.watch(memberNamePreferDisplayProvider),
      ),
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

/// The pieces of the member identity cluster, resolved once per build so each
/// header layout can place them without repeating style or provider work.
class _MemberHeaderIdentity {
  const _MemberHeaderIdentity({
    required this.nameBlock,
    this.pronouns,
    this.statusChips,
  });

  /// The name line: primary name, alternate name, and the name-style button.
  final Widget nameBlock;

  /// The single pronoun display, or null when the member has no pronouns.
  final Widget? pronouns;

  /// Age, birthday, fronting, admin and inactive chips, or null when empty.
  final Widget? statusChips;
}

const List<Shadow> _onImageShadows = [
  Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 1)),
];

/// Resolves the identity cluster for [_CompactMemberProfileHeader] and
/// [_ClassicMemberProfileHeader].
///
/// Pronouns are always a single capsule under the name — never part of the
/// title text and never a status chip — so the header shows one complete,
/// wrapping string.
_MemberHeaderIdentity _resolveMemberHeaderIdentity(
  BuildContext context,
  WidgetRef ref, {
  required Member member,
  required bool isFronting,
  Color? foregroundColor,
  Color? secondaryColor,
  TextStyle? titleStyle,
  bool applyTextShadow = false,
  VoidCallback? onNameStyleTap,
}) {
  final theme = Theme.of(context);
  final primary = foregroundColor ?? theme.colorScheme.onSurface;
  final secondary = secondaryColor ?? theme.colorScheme.onSurfaceVariant;
  final birthday = _birthdayDisplay(context, member);
  final shadows = applyTextShadow ? _onImageShadows : null;
  final frontingTerms = watchFrontingTerms(context, ref);

  final namePresentation = ref.watch(memberNamePresentationProvider);
  final primaryTitle = primaryNameFor(member, namePresentation);
  final secondaryTitle = alternateNameFor(member, namePresentation);

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

  final title = Text.rich(
    TextSpan(
      children: [
        TextSpan(text: primaryTitle, style: headlineStyle),
        if (secondaryTitle != null)
          TextSpan(text: '  ($secondaryTitle)', style: secondaryTitleStyle),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );

  final nameBlock = onNameStyleTap == null
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
              onPressed: onNameStyleTap,
            ),
          ],
        );

  // Empty and whitespace-only pronouns render nothing at all, so no gap is
  // left behind where the capsule would have been.
  final trimmedPronouns = member.pronouns?.trim();
  final pronouns = trimmedPronouns == null || trimmedPronouns.isEmpty
      ? null
      : trimmedPronouns;

  // Over an image the capsule and chips sit on a dark gradient, so they use the
  // translucent white treatment instead of the theme's container colors.
  final infoBackground = applyTextShadow
      ? Colors.white.withValues(alpha: 0.16)
      : theme.colorScheme.surfaceContainerHighest;
  final infoForeground = applyTextShadow
      ? Colors.white.withValues(alpha: 0.92)
      : theme.colorScheme.onSurfaceVariant;

  return _MemberHeaderIdentity(
    nameBlock: nameBlock,
    pronouns: pronouns == null
        ? null
        : _PronounsCapsule(
            pronouns: pronouns,
            textStyle: _pronounsCapsuleTextStyle(
              theme: theme,
              color: infoForeground,
              shadows: shadows,
            ),
            backgroundColor: infoBackground,
          ),
    statusChips: _buildStatusChips(
      context: context,
      theme: theme,
      member: member,
      isFronting: isFronting,
      foregroundColor: foregroundColor,
      birthday: birthday,
      frontingLabel: frontingTerms.activeSectionLabel,
      infoBackground: infoBackground,
      infoForeground: infoForeground,
    ),
  );
}

/// The capsule text role. Body-medium is the readable body size on every
/// platform (14 on phones, the desktop role elsewhere) and is deliberately not
/// derived from the name's headline size.
TextStyle _pronounsCapsuleTextStyle({
  required ThemeData theme,
  required Color color,
  List<Shadow>? shadows,
}) {
  final base = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  return base.copyWith(
    color: color,
    fontWeight: FontWeight.w500,
    shadows: shadows,
  );
}

/// Whether the pronoun capsule has to leave the avatar column and use the full
/// header width.
///
/// [availableWidth] is the width the identity row actually receives from its
/// parent, and the capsule font size is resolved through the ambient
/// [TextScaler] at the body-medium role — so a nonlinear scaler is measured at
/// the role it is applied to, rather than through an assumed multiplier or a
/// UTF-16 character count.
bool _pronounsNeedFullHeaderWidth(BuildContext context, double availableWidth) {
  if (!availableWidth.isFinite) return false;
  final baseSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
  final scaledSize = MediaQuery.textScalerOf(context).scale(baseSize);
  if (scaledSize <= 0) return false;
  return availableWidth <= memberProfilePronounsBesideAvatarMinEm * scaledSize;
}

/// The single pronoun display: one wrapping capsule under the name.
///
/// The string is rendered by [FieldInlineMarkdownText] so inline formatting and
/// member mentions keep working exactly as they do in the rest of the profile,
/// and the capsule grows with its content: no line limit, ellipsis, shrink or
/// FittedBox. Body text is shown as typed — nothing splits on "/".
class _PronounsCapsule extends StatelessWidget {
  const _PronounsCapsule({
    required this.pronouns,
    required this.textStyle,
    required this.backgroundColor,
  });

  final String pronouns;
  final TextStyle textStyle;
  final Color backgroundColor;

  /// Fixed padding: one line reads as a pill, several lines as a soft block.
  /// The 16 pt radius keeps that reading at every length.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );

  @override
  Widget build(BuildContext context) {
    // A labelled container node keeps the pronoun role audible without excluding
    // the rendered text, so links and member mentions inside the capsule stay
    // their own accessible, tappable nodes.
    return Semantics(
      container: true,
      label: context.l10n.memberPronounsLabel,
      child: Container(
        key: memberProfilePronounsCapsuleKey,
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(16),
          ),
        ),
        child: FieldInlineMarkdownText(
          pronouns,
          style: textStyle,
          // Null text alignment opts into the markdown fit-content policy, so
          // the capsule hugs its text instead of stretching to the column.
          textAlign: null,
        ),
      ),
    );
  }
}

/// Age, birthday, fronting, admin and inactive chips. Pronouns are not chips;
/// they keep their own capsule and layout policy.
Widget? _buildStatusChips({
  required BuildContext context,
  required ThemeData theme,
  required Member member,
  required bool isFronting,
  required Color? foregroundColor,
  required String? birthday,
  required String frontingLabel,
  required Color infoBackground,
  required Color infoForeground,
}) {
  final chips = <Widget>[];

  if (member.age != null) {
    chips.add(
      _Chip(
        label: context.l10n.memberAgeDisplay(member.age!),
        backgroundColor: infoBackground,
        foregroundColor: infoForeground,
      ),
    );
  }
  if (birthday != null) {
    chips.add(
      _Chip(
        icon: AppIcons.calendarTodayOutlined,
        label: birthday,
        backgroundColor: infoBackground,
        foregroundColor: infoForeground,
      ),
    );
  }
  if (isFronting) {
    chips.add(
      _Chip(
        icon: AppIcons.flashOn,
        label: frontingLabel,
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

  if (chips.isEmpty) return null;
  return Wrap(spacing: 6, runSpacing: 6, children: chips);
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
      // See MemberAvatar — Drift re-emits member rows during PK sync with
      // fresh Uint8List instances; MemoryImage equality is identity-based,
      // so without gaplessPlayback every emit clears this frame briefly.
      gaplessPlayback: true,
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
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
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
