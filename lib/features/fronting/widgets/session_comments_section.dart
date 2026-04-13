import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/add_comment_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Comments section shown on session detail screen.
class SessionCommentsSection extends ConsumerWidget {
  const SessionCommentsSection({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(sessionCommentsProvider(sessionId));
    final theme = Theme.of(context);

    return commentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (comments) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      context.l10n.frontingCommentsTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    PrismInlineIconButton(
                      icon: AppIcons.addCommentOutlined,
                      iconSize: 20,
                      color: theme.colorScheme.primary,
                      onPressed: () => _openAddSheet(context),
                      tooltip: context.l10n.frontingAddCommentTooltip,
                    ),
                  ],
                ),
                if (comments.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.frontingNoCommentsYet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  for (var i = 0; i < comments.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _CommentTile(comment: comments[i], sessionId: sessionId),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openAddSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddCommentSheet(
        sessionId: sessionId,
        scrollController: scrollController,
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.sessionId});

  final FrontSessionComment comment;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timeStr = DateFormat.jm(context.dateLocale).format(comment.timestamp);
    final dateStr = DateFormat.MMMd(context.dateLocale).format(comment.timestamp);

    return BlurPopupAnchor(
      trigger: BlurPopupTrigger.longPress,
      itemCount: 2,
      itemBuilder: (context, index, close) {
        if (index == 0) {
          return PrismListRow(
            leading: Icon(AppIcons.editOutlined),
            title: Text(context.l10n.edit),
            onTap: () {
              close();
              _openEditSheet(context);
            },
          );
        }
        return PrismListRow(
          leading: Icon(AppIcons.deleteOutline, color: theme.colorScheme.error),
          title: Text(
            context.l10n.delete,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          onTap: () {
            close();
            _confirmDelete(context, ref);
          },
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(
                timeStr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                dateStr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(comment.body, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  void _openEditSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddCommentSheet(
        sessionId: sessionId,
        comment: comment,
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.frontingDeleteCommentTitle,
      message: context.l10n.frontingDeleteCommentMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      unawaited(ref.read(commentNotifierProvider.notifier).deleteComment(comment.id));
    }
  }
}
