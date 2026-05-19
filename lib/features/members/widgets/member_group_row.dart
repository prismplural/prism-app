import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

class MemberGroupRow extends StatelessWidget {
  const MemberGroupRow({
    super.key,
    required this.group,
    required this.memberCount,
    required this.onTap,
    this.depth = 0,
    this.reorderIndex,
    this.onDelete,
    this.showChevron = true,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  final MemberGroup group;
  final int memberCount;
  final VoidCallback onTap;
  final int depth;
  final int? reorderIndex;
  final VoidCallback? onDelete;
  final bool showChevron;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final leftOffset = depth > 0 ? depth * 10.0 : 0.0;
    final row = Semantics(
      label: _semanticLabel(context),
      button: true,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(left: leftOffset),
        child: _dismissibleIfNeeded(
          context,
          child: _GroupRowSurface(
            group: group,
            memberCount: memberCount,
            margin: margin,
            showChevron: showChevron,
            reorderIndex: reorderIndex,
            onTap: onTap,
          ),
        ),
      ),
    );

    return row;
  }

  String _semanticLabel(BuildContext context) {
    final l10n = context.l10n;
    final subGroup = depth > 0 ? ', ${l10n.memberGroupSubGroupSemantic}' : '';
    final hasAvatar =
        group.avatarImageData != null && group.avatarImageData!.isNotEmpty;
    final visualHint = hasAvatar ? ', ${l10n.memberGroupRowPhotoSemantic}' : '';
    return '${group.name}$subGroup$visualHint, '
        '${l10n.memberGroupMemberCountSemantic(memberCount)}, '
        '${l10n.memberGroupOpenSemantic}';
  }

  Widget _dismissibleIfNeeded(BuildContext context, {required Widget child}) {
    if (onDelete == null) return child;
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('dismiss_${group.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.error,
        child: Icon(AppIcons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        onDelete!();
        return false;
      },
      child: child,
    );
  }
}

class _GroupRowSurface extends StatelessWidget {
  const _GroupRowSurface({
    required this.group,
    required this.memberCount,
    required this.margin,
    required this.showChevron,
    required this.reorderIndex,
    required this.onTap,
  });

  final MemberGroup group;
  final int memberCount;
  final EdgeInsets margin;
  final bool showChevron;
  final int? reorderIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;
    final borderRadius = BorderRadius.circular(shapes.radius(14));

    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: borderRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            if (hasColor) Container(width: 4, height: 64, color: accentColor),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: hasColor ? 12 : 16,
                  right: 16,
                  top: 12,
                  bottom: 12,
                ),
                child: Row(
                  children: [
                    _GroupAvatar(group: group, accentColor: accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        group.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (memberCount > 0) _CountChip(memberCount: memberCount),
                    if (reorderIndex != null) ...[
                      const SizedBox(width: 4),
                      ReorderableDragStartListener(
                        index: reorderIndex!,
                        child: Tooltip(
                          message: context.l10n.reorder,
                          child: Icon(
                            AppIcons.dragHandle,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ] else if (showChevron) ...[
                      const SizedBox(width: 4),
                      Icon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.group, required this.accentColor});

  final MemberGroup group;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accentColor ?? theme.colorScheme.primary;
    final hasAvatar =
        group.avatarImageData != null && group.avatarImageData!.isNotEmpty;
    final hasEmoji = group.emoji != null && group.emoji!.isNotEmpty;

    return TintedGlassSurface.circle(
      size: 44,
      tint: tint,
      child: Center(
        child: hasAvatar
            ? ClipOval(
                child: Image.memory(
                  group.avatarImageData!,
                  fit: BoxFit.cover,
                  width: 44,
                  height: 44,
                  cacheWidth: 88,
                  cacheHeight: 88,
                  errorBuilder: (_, _, _) => hasEmoji
                      ? Text(group.emoji!, style: const TextStyle(fontSize: 22))
                      : Icon(AppIcons.folderOutlined, size: 22, color: tint),
                ),
              )
            : hasEmoji
                ? Text(group.emoji!, style: const TextStyle(fontSize: 22))
                : Icon(AppIcons.folderOutlined, size: 22, color: tint),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.memberCount});

  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Text(
        '$memberCount',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
