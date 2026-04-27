import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/add_comment_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Comments section shown on session detail screen.
///
/// Comments are now anchored to a timestamp (targetTime) rather than a
/// session ID. We watch comments in the session's time range as a proxy —
/// showing any comment whose targetTime falls within [session.startTime,
/// session.endTime ?? now). This is a Phase 2B.3 compile-pass implementation;
/// the full period-level comment threading is deferred to Phase 3 per §3.5.
///
/// TODO(§3.5): Phase 3 — replace range-proxy with period-aware comment routing.
class SessionCommentsSection extends ConsumerWidget {
  const SessionCommentsSection({super.key, required this.session});

  final FrontingSession session;

  // Fall back to session.startTime when building the range for an active session.
  DateTimeRange get _range => DateTimeRange(
        start: session.startTime,
        end: session.endTime ?? session.startTime.add(const Duration(days: 1)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(commentsForRangeProvider(_range));
    final theme = Theme.of(context);

    return commentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (comments) {
        return PrismSurface(
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
                  _CommentTile(comment: comments[i]),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  void _openAddSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddCommentSheet(
        // Default targetTime to the session's start time; user can edit it.
        targetTime: session.startTime,
        scrollController: scrollController,
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment});

  final FrontSessionComment comment;

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
        // Use comment's own targetTime (or timestamp as fallback) for editing.
        targetTime: comment.targetTime ?? comment.timestamp,
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
