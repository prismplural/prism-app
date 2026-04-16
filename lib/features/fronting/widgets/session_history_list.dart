import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/ui/delete_strategy_dialog.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';


/// A day-grouped list of fronting sessions. Active sessions appear naturally
/// at the top of today's group with a live duration timer.
///
/// Each day is rendered as a centered header followed by a card containing
/// all sessions for that day, matching the SwiftUI design.
class SessionHistoryList extends ConsumerWidget {
  const SessionHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(unifiedHistoryProvider);

    return historyAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: PrismLoadingState(),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.frontingErrorLoadingHistory(e)),
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
                      AppIcons.historyOutlined,
                      size: 48,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.frontingNoSessionHistory,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Batch-load all members referenced by sessions in a single query.
        final allMemberIds = <String>{};
        for (final session in sessions) {
          if (session.memberId != null) allMemberIds.add(session.memberId!);
          allMemberIds.addAll(session.coFronterIds);
        }
        final key = memberIdsKey(allMemberIds);
        final membersAsync = ref.watch(membersByIdsProvider(key));
        final membersMap = membersAsync.whenOrNull(data: (m) => m) ?? {};

        final grouped = groupSessionsByDay(sessions);

        return SliverList.builder(
          itemCount: grouped.length,
          itemBuilder: (context, index) =>
              _DayGroupWidget(
                group: grouped[index],
                isFirstGroup: index == 0,
                membersMap: membersMap,
              ),
        );
      },
    );
  }

}

/// Renders a day header + a card containing all sessions for that day.
class _DayGroupWidget extends StatelessWidget {
  const _DayGroupWidget({
    required this.group,
    this.isFirstGroup = false,
    required this.membersMap,
  });

  final DayGroup group;
  final bool isFirstGroup;
  final Map<String, Member> membersMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Centered day header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: DateChip(
            date: DateTime.parse(group.dayKey),
          ),
        ),
        // Sessions card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                for (var i = 0; i < group.sessions.length; i++) ...[
                  if (group.sessions[i].session.isSleep)
                    _InlineSleepTile(displaySession: group.sessions[i])
                  else
                    _SessionTile(
                      displaySession: group.sessions[i],
                      isLatest: isFirstGroup && i == 0,
                      membersMap: membersMap,
                    ),
                  if (i < group.sessions.length - 1)
                    Divider(
                      height: 1,
                      indent: 64,
                      endIndent: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({
    required this.displaySession,
    this.isLatest = false,
    required this.membersMap,
  });

  final DisplaySession displaySession;
  final bool isLatest;
  final Map<String, Member> membersMap;

  FrontingSession get session => displaySession.session;

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(frontingSessionRepositoryProvider);
    final allSessions = await repo.getAllSessions();
    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);

    final sessionSnapshot = FrontingSanitizerService.toSnapshot(session);
    final allSnapshots =
        allSessions.map(FrontingSanitizerService.toSnapshot).toList();

    final deleteCtx =
        editGuard.getDeleteContext(sessionSnapshot, allSnapshots);

    if (!context.mounted) return false;
    final strategy = await showDeleteStrategyDialog(
      context,
      deleteContext: deleteCtx,
    );
    if (strategy == null || !context.mounted) return false;

    Haptics.heavy();
    final changes = resolutionService.computeDeleteChanges(deleteCtx, strategy);
    await changeExecutor.execute(changes);
    invalidateFrontingProviders(ref);

    triggerPostEditRescan(
      ref,
      sessionStart: session.startTime,
      sessionEnd: session.endTime,
    );

    ref.invalidate(frontingHistoryProvider);
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memberId = session.memberId;
    final isUnknown = memberId == null;

    final member = memberId != null ? membersMap[memberId] : null;
    final emoji = member?.emoji ?? '?';

    // Resolve co-fronter members from the pre-loaded map
    final coFronterMembers = <Member>[
      for (final coId in session.coFronterIds)
        if (membersMap[coId] != null)
          membersMap[coId]!,
    ];

    // Build display name: "Alice & Bob" or "Alice, Bob & Carol"
    final String name;
    if (isUnknown) {
      name = 'Unknown';
    } else {
      final names = [
        member?.name ?? 'Unknown',
        ...coFronterMembers.map((m) => m.name),
      ];
      if (names.length == 1) {
        name = names.first;
      } else if (names.length == 2) {
        name = '${names[0]} & ${names[1]}';
      } else {
        name = '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
      }
    }

    final accentColor =
        member != null &&
            member.customColorEnabled &&
            member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;

    final timeRange = displaySession.timeRangeString(context.dateLocale);

    final Widget leadingWidget;
    if (isUnknown) {
      leadingWidget = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Icon(
          AppIcons.helpOutline,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    } else if (coFronterMembers.isNotEmpty) {
      final groupMembers = [
        GroupAvatarMember(
          avatarImageData: member?.avatarImageData,
          emoji: emoji,
          customColorEnabled: member?.customColorEnabled ?? false,
          customColorHex: member?.customColorHex,
        ),
        ...coFronterMembers.map((m) => GroupAvatarMember(
          avatarImageData: m.avatarImageData,
          emoji: m.emoji,
          customColorEnabled: m.customColorEnabled,
          customColorHex: m.customColorHex,
        )),
      ];
      leadingWidget = GroupMemberAvatar(
        members: groupMembers,
        size: 40,
      );
    } else {
      leadingWidget = MemberAvatar(
        avatarImageData: member?.avatarImageData,
        memberName: member?.name,
        emoji: emoji,
        customColorEnabled: member?.customColorEnabled ?? false,
        customColorHex: member?.customColorHex,
        size: 40,
      );
    }

    // Build the subtitle with colored duration + time range
    // Only the latest (most recent) session gets accent-colored duration
    final durationColor = isLatest ? accentColor : null;
    final showLiveTimer =
        displaySession.isActive && !displaySession.continuesNextDay;
    final subtitleWidget = showLiveTimer
        ? _ActiveSubtitle(
            startTime: displaySession.displayStart,
            timeRange: timeRange,
            accentColor: accentColor,
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: displaySession.displayDuration.toShortString(),
                  style: TextStyle(
                    color: durationColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: '  \u00b7  $timeRange',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );

    const dimAlpha = 0.6;
    final tileContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(AppRoutePaths.session(session.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              leadingWidget,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: isUnknown
                          ? theme.textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: dimAlpha),
                            )
                          : theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: (theme.textTheme.bodySmall ?? const TextStyle())
                          .copyWith(
                        color: isUnknown
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: dimAlpha)
                            : null,
                      ),
                      child: subtitleWidget,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                AppIcons.chevronRightRounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: isUnknown ? 0.4 * dimAlpha : 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final sliceKey = displaySession.isContinuation
        ? '${session.id}-cont-${displaySession.displayStart.toDayKey()}'
        : session.id;

    return Dismissible(
      key: ValueKey(sliceKey),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.2),
        ),
        child: Icon(AppIcons.delete, color: AppColors.error),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref),
      child: showLiveTimer
          ? AnimatedSwitcher(
              duration: Anim.lg,
              switchInCurve: Anim.enter,
              switchOutCurve: Anim.exit,
              child: KeyedSubtree(
                key: ValueKey('${session.id}-${session.memberId}'),
                child: tileContent,
              ),
            )
          : tileContent,
    );
  }
}

/// Inline sleep session tile with tinted background.
class _InlineSleepTile extends ConsumerWidget {
  const _InlineSleepTile({required this.displaySession});

  final DisplaySession displaySession;

  FrontingSession get session => displaySession.session;

  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.frontingDeleteSleepTitle,
      message: context.l10n.frontingDeleteSleepMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      await ref.read(sleepNotifierProvider.notifier).deleteSleep(session.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final timeRange = displaySession.timeRangeString(context.dateLocale);

    final quality = session.quality;
    final hasQuality = quality != null && quality != SleepQuality.unknown;

    final trailing = hasQuality
        ? Text(
            quality.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.sleep(theme.brightness),
              fontWeight: FontWeight.w500,
            ),
          )
        : Icon(
            AppIcons.chevronRightRounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          );

    return Semantics(
      label: context.l10n.frontingSleepSessionSemantics(
            displaySession.displayDuration.toShortString(), timeRange),
      child: Container(
        color: AppColors.sleep(theme.brightness).withValues(alpha: 0.12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go(AppRoutePaths.session(session.id)),
            onLongPress: () => _showDeleteDialog(context, ref),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.sleep(theme.brightness).withValues(alpha: 0.2),
                    ),
                    child: PhosphorIcon(
                      AppIcons.duotoneSleep,
                      size: 20,
                      color: AppColors.sleep(theme.brightness),
                      semanticLabel: context.l10n.frontingSleeping,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.frontingSleeping,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: displaySession.displayDuration
                                    .toShortString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: '  \u00b7  $timeRange',
                                style: TextStyle(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtitle for active sessions with live-updating duration.
class _ActiveSubtitle extends StatelessWidget {
  const _ActiveSubtitle({
    required this.startTime,
    required this.timeRange,
    required this.accentColor,
  });

  final DateTime startTime;
  final String timeRange;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        FrontingDurationText(
          startTime: startTime,
          rounded: true,
          style: theme.textTheme.bodySmall?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w600,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        Text(
          '  \u00b7  $timeRange',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
