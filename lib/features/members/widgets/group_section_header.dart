import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Section header for a member group (or the ungrouped section) in the
/// grouped sections members list.
class GroupSectionHeader extends StatelessWidget {
  const GroupSectionHeader({
    super.key,
    required this.group,
    required this.depth,
    required this.memberCount,
    required this.isCollapsed,
    required this.canCollapse,
    required this.onToggle,
  });

  /// The group this header represents. `null` indicates the ungrouped section.
  final MemberGroup? group;

  /// Depth level: 0 = root, then increases by 1 per nested level.
  final int depth;
  final int memberCount;
  final bool isCollapsed;
  final bool canCollapse;
  final VoidCallback? onToggle;

  static const double _avatarSize = 28.0;
  static const double _barHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final name = group?.name ?? l10n.memberGroupFilterUngrouped;
    final leftIndent = depth * 30.0;

    Color? groupColor;
    if (group?.colorHex != null && group!.colorHex!.isNotEmpty) {
      groupColor = AppColors.fromHex(group!.colorHex!);
    }
    final tint = groupColor ?? theme.colorScheme.primary;
    final hasEmoji = group?.emoji != null && group!.emoji!.isNotEmpty;

    final avatar = TintedGlassSurface.circle(
      size: _avatarSize,
      tint: tint,
      child: Center(
        child: hasEmoji
            ? Text(group!.emoji!, style: const TextStyle(fontSize: 14))
            : Icon(AppIcons.folderOutlined, size: 14, color: tint),
      ),
    );

    final titleStyle =
        (depth == 0 ? theme.textTheme.labelLarge : theme.textTheme.labelMedium)
            ?.copyWith(fontWeight: FontWeight.w600);

    return Semantics(
      button: canCollapse,
      label:
          '$name, $memberCount members, '
          '${isCollapsed ? 'collapsed' : 'expanded'}'
          '${canCollapse ? ', double-tap to toggle' : ''}',
      excludeSemantics: true,
      child: Material(
        color: theme.cardColor,
        child: InkWell(
          onTap: canCollapse ? onToggle : null,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16 + leftIndent,
              right: 16,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                if (groupColor != null) ...[
                  Container(width: 4, height: _barHeight, color: groupColor),
                  const SizedBox(width: 12),
                ],
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: titleStyle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (memberCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        PrismShapes.of(context).radius(12),
                      ),
                    ),
                    child: Text(
                      '$memberCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (canCollapse) ...[
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isCollapsed ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
