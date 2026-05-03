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
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Comments section for a derived period.
///
/// Periods are not persisted rows, so this aggregates comments attached to the
/// physical [sessionIds] that make up the period and whose timestamp falls in
/// the half-open [range].
class CommentsForRangeSection extends ConsumerWidget {
  const CommentsForRangeSection({
    super.key,
    required this.sessionIds,
    required this.range,
  });

  final List<String> sessionIds;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(
      commentsForPeriodProvider(
        PeriodCommentsQuery(sessionIds: sessionIds, range: range),
      ),
    );
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
                  FrontSessionCommentTile(comment: comments[i]),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class FrontSessionCommentTile extends ConsumerWidget {
  const FrontSessionCommentTile({super.key, required this.comment});

  final FrontSessionComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timeStr = DateFormat.jm(context.dateLocale).format(comment.timestamp);
    final dateStr = DateFormat.MMMd(
      context.dateLocale,
    ).format(comment.timestamp);

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
    final sessionId = comment.sessionId;
    if (sessionId.trim().isEmpty) return;
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddCommentSheet(
        sessionId: sessionId,
        timestamp: comment.timestamp,
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
      unawaited(
        ref.read(commentNotifierProvider.notifier).deleteComment(comment.id),
      );
    }
  }
}
