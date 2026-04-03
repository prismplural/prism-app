import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// A list of recent sleep sessions with date, duration, quality, and notes.
class SleepHistoryList extends ConsumerWidget {
  const SleepHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(recentSleepSessionsProvider);

    return sessionsAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: PrismLoadingState(),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error loading sleep history: $e'),
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      AppIcons.bedtimeOutlined,
                      size: 48,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No sleep sessions recorded yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SliverList.builder(
          itemCount: sessions.length,
          itemBuilder: (context, index) =>
              _SleepSessionTile(session: sessions[index]),
        );
      },
    );
  }
}

class _SleepSessionTile extends ConsumerWidget {
  const _SleepSessionTile({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final startStr = session.startTime.toDateTimeString();
    final endStr = session.endTime?.toTimeString();
    final subtitle =
        endStr != null ? '$startStr - $endStr' : '$startStr - now';
    final qualityLabel =
        session.quality == null || session.quality == SleepQuality.unknown
            ? 'Unrated'
            : session.quality!.label;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        child: Icon(AppIcons.bedtimeRounded, size: 20),
      ),
      title: Text(session.startTime.toDateString()),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          Text(
            qualityLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (session.notes != null && session.notes!.isNotEmpty)
            Text(
              session.notes!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      trailing: session.isActive
          ? Chip(
              label: const Text('Sleeping'),
              backgroundColor: theme.colorScheme.tertiaryContainer,
              labelStyle: TextStyle(
                color: theme.colorScheme.tertiary,
                fontSize: 12,
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          : Text(
              session.duration.toShortString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      isThreeLine: session.notes != null && session.notes!.isNotEmpty,
      onTap: () {
        context.push(AppRoutePaths.session(session.id));
      },
      onLongPress: () {
        _showDeleteDialog(context, ref);
      },
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete Sleep Session',
      message: 'Are you sure you want to delete this sleep session?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      await ref.read(sleepNotifierProvider.notifier).deleteSleep(session.id);
      ref.invalidate(recentSleepSessionsProvider);
    }
  }
}
