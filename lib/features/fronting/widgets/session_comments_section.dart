import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/add_comment_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/comments_for_range_section.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Comments section shown on session detail screen.
class SessionCommentsSection extends ConsumerWidget {
  const SessionCommentsSection({super.key, required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(commentsForSessionProvider(session.id));
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
                  FrontSessionCommentTile(comment: comments[i]),
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
        sessionId: session.id,
        timestamp: session.startTime,
        scrollController: scrollController,
      ),
    );
  }
}
