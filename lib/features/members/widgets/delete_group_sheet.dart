import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Bottom sheet shown when deleting a group that has sub-groups.
///
/// Presents two clearly weighted options:
/// - Promote direct children to root (safe default)
/// - Recursively delete everything (requires secondary confirmation)
class DeleteGroupSheet extends ConsumerStatefulWidget {
  const DeleteGroupSheet({super.key, required this.group});

  final MemberGroup group;

  @override
  ConsumerState<DeleteGroupSheet> createState() => _DeleteGroupSheetState();
}

class _DeleteGroupSheetState extends ConsumerState<DeleteGroupSheet> {
  bool _isLoading = false;

  Future<void> _promote() async {
    setState(() => _isLoading = true);
    Haptics.medium();
    unawaited(
      ref.read(groupNotifierProvider.notifier).promoteChildrenToRoot(widget.group.id),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    PrismToast.show(context, message: context.l10n.memberGroupPromoted);
  }

  Future<void> _deleteAll() async {
    final l10n = context.l10n;
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberGroupDeleteAllConfirmTitle,
      message: l10n.memberGroupDeleteAllConfirmMessage(widget.group.name),
      confirmLabel: l10n.memberGroupDeleteAll,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);
    Haptics.heavy();
    unawaited(
      ref
          .read(groupNotifierProvider.notifier)
          .deleteGroupWithDescendants(widget.group.id),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    PrismToast.show(
        context, message: context.l10n.memberGroupDeleted(widget.group.name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Group name
            Text(
              '"${widget.group.name}"',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.memberGroupDeleteCascadeSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            // Promote option (safe default)
            _OptionTile(
              title: l10n.memberGroupDeletePromote,
              subtitle: l10n.memberGroupDeletePromoteSubtitle,
              onTap: _isLoading ? null : _promote,
            ),
            const SizedBox(height: 10),
            // Delete all option (destructive)
            _OptionTile(
              title: l10n.memberGroupDeleteAll,
              subtitle: l10n.memberGroupDeleteAllSubtitle,
              destructive: true,
              onTap: _isLoading ? null : _deleteAll,
            ),
            const SizedBox(height: 8),
            // Cancel
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              child: Text(
                MaterialLocalizations.of(context).cancelButtonLabel,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: destructive
                  ? theme.colorScheme.error.withValues(alpha: 0.08)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.06),
              borderRadius:
                  BorderRadius.circular(PrismShapes.of(context).radius(14)),
              border: destructive
                  ? Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.25))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(AppIcons.chevronRight,
                    color: color.withValues(alpha: 0.4), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
