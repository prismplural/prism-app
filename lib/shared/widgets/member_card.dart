import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// A Material 3 card for displaying a member in a list.
///
/// Shows the member's avatar, name, pronouns, and an optional trailing widget
/// (e.g., a fronting indicator). When the member has a custom color enabled,
/// a thin accent strip is shown on the leading edge of the card.
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.member,
    this.trailing,
    this.onTap,
  });

  final Member member;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCustomColor =
        member.customColorEnabled && member.customColorHex != null;
    final accentColor =
        hasCustomColor ? AppColors.fromHex(member.customColorHex!) : null;

    const radius = BorderRadius.all(Radius.circular(14));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: member.name,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Row(
              children: [
                // Custom color accent strip
                if (hasCustomColor)
                  Container(
                    width: 4,
                    height: 64,
                    color: accentColor,
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: hasCustomColor ? 12 : 16,
                      right: 16,
                      top: 12,
                      bottom: 12,
                    ),
                    child: Row(
                      children: [
                        MemberAvatar(
                          avatarImageData: member.avatarImageData,
                          memberName: member.name,
                          emoji: member.emoji,
                          customColorEnabled: member.customColorEnabled,
                          customColorHex: member.customColorHex,
                          size: 44,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                member.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (member.pronouns != null &&
                                  member.pronouns!.isNotEmpty)
                                Text(
                                  member.pronouns!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
