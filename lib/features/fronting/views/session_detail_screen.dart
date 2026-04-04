import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/views/edit_sleep_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/features/fronting/ui/delete_strategy_dialog.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/fronting/widgets/session_comments_section.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Full-screen view showing all details of a single fronting session.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionByIdProvider(sessionId));
    final session = sessionAsync.value;
    final isSleep = session?.isSleep ?? false;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: session == null
            ? const []
            : [
                PrismTopBarAction(
                  icon: AppIcons.editOutlined,
                  tooltip: 'Edit',
                  onPressed: isSleep
                      ? () => _editSleep(context, session)
                      : () => context.go(AppRoutePaths.sessionEdit(sessionId)),
                ),
                PrismTopBarAction(
                  icon: AppIcons.deleteOutline,
                  tooltip: 'Delete',
                  onPressed: isSleep
                      ? () => _confirmSleepDelete(context, ref, session)
                      : () => _confirmDelete(context, ref),
                ),
              ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: sessionAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('Session not found'));
          }
          if (session.isSleep) {
            return _SleepSessionBody(session: session);
          }
          return _SessionDetailBody(session: session);
        },
      ),
    );
  }

  Future<void> _editSleep(BuildContext context, FrontingSession session) async {
    await EditSleepSheet.show(context, session);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(frontingSessionRepositoryProvider);
    final session = await repo.getSessionById(sessionId);
    if (session == null) return;
    final allSessions = await repo.getAllSessions();

    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);

    // Convert to snapshots
    final sessionSnapshot = FrontingSanitizerService.toSnapshot(session);
    final allSnapshots =
        allSessions.map(FrontingSanitizerService.toSnapshot).toList();

    // Build delete context
    final deleteCtx =
        editGuard.getDeleteContext(sessionSnapshot, allSnapshots);

    // Show strategy dialog
    if (!context.mounted) return;
    final strategy = await showDeleteStrategyDialog(
      context,
      deleteContext: deleteCtx,
    );
    if (strategy == null || !context.mounted) return;

    // Compute and execute changes
    Haptics.heavy();
    final changes = resolutionService.computeDeleteChanges(deleteCtx, strategy);
    await changeExecutor.execute(changes);

    // Fire-and-forget rescan to update the issue banner
    triggerPostEditRescan(ref, sessionStart: session.startTime, sessionEnd: session.endTime);

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmSleepDelete(
    BuildContext context,
    WidgetRef ref,
    FrontingSession session,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete Sleep Session',
      message: 'Are you sure you want to delete this sleep session?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(sleepNotifierProvider.notifier).deleteSleep(session.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _SleepSessionBody extends StatelessWidget {
  const _SleepSessionBody({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quality = session.quality ?? SleepQuality.unknown;
    final navBarInset = NavBarInset.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + navBarInset),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      AppIcons.bedtimeRounded,
                      size: 28,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        session.isActive ? 'Sleeping now' : 'Sleep session',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _InfoRow(
                  label: 'Started',
                  value: session.startTime.toDateTimeString(),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Ended',
                  value: session.endTime?.toDateTimeString() ?? 'Active',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Duration',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (session.isActive)
                      FrontingDurationText(
                        startTime: session.startTime,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        session.duration.toLongString(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Quality',
                  value: quality == SleepQuality.unknown
                      ? 'Unrated'
                      : quality.label,
                ),
                if (session.notes != null && session.notes!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Notes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.notes!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SessionCommentsSection(sessionId: session.id),
      ],
    );
  }
}

class _SessionDetailBody extends ConsumerWidget {
  const _SessionDetailBody({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final navBarInset = NavBarInset.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + navBarInset),
      children: [
        // Fronter info
        _FronterSection(session: session),
        const SizedBox(height: 24),

        // Co-fronters
        if (session.coFronterIds.isNotEmpty) ...[
          Text(
            'Co-Fronters',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...session.coFronterIds.map((id) => _CoFronterTile(memberId: id)),
          const SizedBox(height: 24),
        ],

        // Time info
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Started',
                  value: session.startTime.toDateTimeString(),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Ended',
                  value: session.endTime?.toDateTimeString() ?? 'Active',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Duration',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (session.isActive)
                      FrontingDurationText(
                        startTime: session.startTime,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        session.duration.toLongString(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Confidence
        if (session.confidence != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confidence',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ConfidenceDisplay(confidence: session.confidence!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Comments
        SessionCommentsSection(sessionId: session.id),
        const SizedBox(height: 16),

        // Notes
        if (session.notes != null && session.notes!.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(session.notes!, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FronterSection extends ConsumerWidget {
  const _FronterSection({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (session.memberId == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                AppIcons.helpOutline,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Unknown',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final memberAsync = ref.watch(memberByIdProvider(session.memberId!));

    return memberAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: PrismLoadingState(),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (member) {
        if (member == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => context.go(AppRoutePaths.settingsMember(member.id)),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  MemberAvatar(
                    avatarImageData: member.avatarImageData,
                    emoji: member.emoji,
                    customColorEnabled: member.customColorEnabled,
                    customColorHex: member.customColorHex,
                    size: 80,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (member.pronouns != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            member.pronouns!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoFronterTile extends ConsumerWidget {
  const _CoFronterTile({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));

    return memberAsync.when(
      loading: () => const PrismListRow(
        leading: SizedBox(width: 40, height: 40),
        title: Text('Loading...'),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (member) {
        if (member == null) return const SizedBox.shrink();

        return PrismListRow(
          leading: MemberAvatar(
            avatarImageData: member.avatarImageData,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            size: 40,
          ),
          title: Text(member.name),
          subtitle: member.pronouns != null ? Text(member.pronouns!) : null,
          onTap: () => context.go(AppRoutePaths.settingsMember(member.id)),
          padding: EdgeInsets.zero,
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ConfidenceDisplay extends StatelessWidget {
  const _ConfidenceDisplay({required this.confidence});

  final FrontConfidence confidence;

  static const _labels = {
    FrontConfidence.unsure: 'Unsure',
    FrontConfidence.strong: 'Strong',
    FrontConfidence.certain: 'Certain',
  };

  int get _level => confidence.index + 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        ...List.generate(3, (i) {
          final filled = i < _level;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              filled ? AppIcons.circle : AppIcons.circleOutlined,
              size: 16,
              color: filled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          _labels[confidence]!,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
