import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/views/add_front_session_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/features/fronting/views/edit_front_session_screen.dart';
import 'package:prism_plurality/features/fronting/views/edit_sleep_sheet.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/fronting/ui/delete_strategy_dialog.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_profile_header_resolver.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/fronting/widgets/session_comments_section.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

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
                  tooltip: context.l10n.frontingSessionDetailEditTooltip,
                  onPressed: isSleep
                      ? () => _editSleep(context, session)
                      : () => _editFrontSession(context),
                ),
                PrismTopBarAction(
                  icon: AppIcons.deleteOutline,
                  tooltip: context.l10n.frontingSessionDetailDeleteTooltip,
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
            return Center(child: Text(context.l10n.frontingSessionNotFound));
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

  void _editFrontSession(BuildContext context) {
    showAdaptiveDetailSurface<void>(
      context: context,
      builder: (_) => EditFrontSessionScreen(sessionId: sessionId),
      route: (context) => context.push(AppRoutePaths.sessionEdit(sessionId)),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(frontingSessionRepositoryProvider);
    final session = await repo.getSessionById(sessionId);
    if (session == null) return;
    final allSessions = await repo.getAllSessions();

    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);

    final sessionSnapshot = session.toSnapshot();
    final allSnapshots = allSessions.map((s) => s.toSnapshot()).toList();

    // Build delete context
    final deleteCtx = editGuard.getDeleteContext(sessionSnapshot, allSnapshots);

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
    final result = await changeExecutor.execute(changes);
    if (!context.mounted) return;
    result.when(
      success: (_) {
        if (context.mounted) Navigator.of(context).pop();
      },
      failure: (error) {
        if (context.mounted) {
          PrismToast.error(
            context,
            message: context.l10n.frontingErrorSavingSession(error),
          );
        }
      },
    );
  }

  Future<void> _confirmSleepDelete(
    BuildContext context,
    WidgetRef ref,
    FrontingSession session,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.frontingDeleteSleepTitle,
      message: context.l10n.frontingDeleteSleepMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(sleepNotifierProvider.notifier).deleteSleep(session.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

void _openMemberDetail(BuildContext context, String memberId) {
  showAdaptiveDetailSurface<void>(
    context: context,
    builder: (_) => MemberDetailScreen(
      memberId: memberId,
      branch: MemberNavigationBranch.settings,
    ),
    route: (context) => context.push(AppRoutePaths.settingsMember(memberId)),
  );
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
        PrismSurface(
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
                      session.isActive
                          ? context.l10n.frontingSleepingNow
                          : context.l10n.frontingSleepSession,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _InfoRow(
                label: context.l10n.frontingInfoStarted,
                value: context.formatDateTime(session.startTime),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: context.l10n.frontingInfoEnded,
                value:
                    (session.endTime == null
                        ? null
                        : context.formatDateTime(session.endTime!)) ??
                    context.l10n.frontingInfoActive,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      context.l10n.frontingInfoDuration,
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
                label: context.l10n.frontingInfoQuality,
                value: quality == SleepQuality.unknown
                    ? context.l10n.frontingInfoQualityUnrated
                    : quality.localizedLabel(context.l10n),
              ),
              if (session.notes != null && session.notes!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  context.l10n.frontingNotesSection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(session.notes!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SessionCommentsSection(session: session),
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
    final memberAsync = session.memberId != null
        ? ref.watch(activeMemberByIdProvider(session.memberId!))
        : null;
    final member = memberAsync?.value;
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final memberName = member?.effectiveName(preferDisplayName: prefer) ?? '';
    final showPill =
        session.isActive && !session.isSleep && session.memberId != null;
    final bottomReserve = showPill ? navBarInset + 84 : 24 + navBarInset;

    // Pre-resolve active sessions so the value is available synchronously
    // when the end-session button is tapped.
    final activeSessions = showPill
        ? ref.watch(activeSessionsProvider).value
        : null;

    final list = ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomReserve),
      children: [
        // Fronter info
        _FronterSection(session: session),
        const SizedBox(height: 24),

        // Co-fronters section removed — each session is one member's continuous
        // presence. Period-level detail (showing all members active during a
        // time span) is deferred to Phase 3 per spec §3.1 and §3.2.

        // Time info
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.frontingTimeSection,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: context.l10n.frontingInfoStarted,
                value: context.formatDateTime(session.startTime),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: context.l10n.frontingInfoEnded,
                value:
                    (session.endTime == null
                        ? null
                        : context.formatDateTime(session.endTime!)) ??
                    context.l10n.frontingInfoActive,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      context.l10n.frontingInfoDuration,
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
        const SizedBox(height: 16),

        // Confidence
        if (session.confidence != null) ...[
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.frontingConfidenceSection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _ConfidenceDisplay(confidence: session.confidence!),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Comments
        SessionCommentsSection(session: session),
        const SizedBox(height: 16),

        // Notes
        if (session.notes != null && session.notes!.isNotEmpty) ...[
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.frontingNotesSection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(session.notes!, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ],
    );

    if (!showPill) return list;

    final tint =
        (member != null &&
            member.customColorEnabled &&
            member.customColorHex != null)
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;

    return Stack(
      children: [
        list,
        Positioned(
          left: 16,
          right: 16,
          bottom: navBarInset + 16,
          child: Center(
            child: _FloatingEndSessionButton(
              memberName: memberName,
              tintColor: tint,
              onPressed: () => _handleEndSession(
                context,
                ref,
                session,
                memberName,
                activeSessions: activeSessions,
              ),
            ),
          ),
        ),
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
      return PrismSurface(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              AppIcons.helpOutline,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.unknown,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final memberAsync = ref.watch(activeMemberByIdProvider(session.memberId!));
    final prefer = ref.watch(memberNamePreferDisplayProvider);

    return memberAsync.when(
      loading: () => const PrismSurface(
        padding: EdgeInsets.all(32),
        child: PrismLoadingState(),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (member) {
        if (member == null) return const SizedBox.shrink();
        final memberName = member.effectiveName(preferDisplayName: prefer);
        final header = resolveMemberProfileHeader(
          member,
          layoutOverride: MemberProfileHeaderLayout.compactBackground,
        );

        if (header.hasImage) {
          return PrismSurface(
            onTap: () => _openMemberDetail(context, member.id),
            padding: EdgeInsets.zero,
            borderColor: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(
                    header.activeImageData!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    cacheWidth:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .ceil(),
                    semanticLabel: context.l10n.profileHeaderSemantic(
                      memberName,
                    ),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.28),
                          Colors.black.withValues(alpha: 0.64),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _FronterMemberRow(
                    member: member,
                    memberName: memberName,
                    titleColor: Colors.white,
                    subtitleColor: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          );
        }

        return PrismSurface(
          onTap: () => _openMemberDetail(context, member.id),
          padding: const EdgeInsets.all(20),
          child: _FronterMemberRow(member: member, memberName: memberName),
        );
      },
    );
  }
}

class _FronterMemberRow extends StatelessWidget {
  const _FronterMemberRow({
    required this.member,
    required this.memberName,
    this.titleColor,
    this.subtitleColor,
  });

  final Member member;
  final String memberName;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        MemberAvatar(
          avatarImageData: member.avatarImageData,
          memberName: memberName,
          emoji: member.emoji,
          customColorEnabled: member.customColorEnabled,
          customColorHex: member.customColorHex,
          size: 80,
          showBorder: titleColor != null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memberName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (member.pronouns != null) ...[
                const SizedBox(height: 4),
                Text(
                  member.pronouns!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// End-session pill + dialog
// ─────────────────────────────────────────────────────────────────────────────

enum _NextFronterChoice { pickFronter, unknown, endWithoutFronting }

Future<_NextFronterChoice?> _showNextFronterDialog(
  BuildContext context, {
  required String pickLabel,
  required String endLabel,
}) {
  // Capture l10n strings before entering the dialog so we can reference them
  // from the builder context without holding onto the outer BuildContext.
  final l10n = context.l10n;

  return PrismDialog.show<_NextFronterChoice>(
    context: context,
    title: l10n.frontingNextFronterTitle,
    message: l10n.frontingNextFronterBody,
    actions: [
      Builder(
        builder: (ctx) => PrismButton(
          label: pickLabel,
          tone: PrismButtonTone.filled,
          onPressed: () =>
              Navigator.of(ctx).pop(_NextFronterChoice.pickFronter),
        ),
      ),
      Builder(
        builder: (ctx) => PrismButton(
          label: l10n.frontingNextFronterUnknown,
          tone: PrismButtonTone.outlined,
          onPressed: () => Navigator.of(ctx).pop(_NextFronterChoice.unknown),
        ),
      ),
      Builder(
        builder: (ctx) => PrismButton(
          label: endLabel,
          tone: PrismButtonTone.outlined,
          onPressed: () =>
              Navigator.of(ctx).pop(_NextFronterChoice.endWithoutFronting),
        ),
      ),
    ],
    builder: (_) => const SizedBox.shrink(),
  );
}

Future<void> _handleEndSession(
  BuildContext context,
  WidgetRef ref,
  FrontingSession session,
  String memberName, {
  List<FrontingSession>? activeSessions,
  Future<bool?> Function(BuildContext)? showAddSheetOverride,
}) async {
  final memberId = session.memberId;
  if (memberId == null) return;

  // Use the pre-resolved value passed from the widget; fall back to reading
  // from the provider (used in tests that call the handler directly).
  final active = activeSessions ?? ref.read(activeSessionsProvider).value;
  if (active == null) return;

  final notifier = ref.read(frontingNotifierProvider.notifier);
  final frontingTerms = readFrontingTerms(context, ref);
  Haptics.medium();

  Future<bool> safeEnd() async {
    try {
      await notifier.endFronting([memberId]);
      return true;
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSavingSession(e),
        );
      }
      return false;
    }
  }

  Future<void> safeStartUnknown() async {
    try {
      await notifier.startFronting([unknownSentinelMemberId]);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorCreatingSession(e),
        );
      }
    }
  }

  void showEndedToast() {
    if (!context.mounted) return;
    PrismToast.success(
      context,
      message: context.l10n.frontingEndSessionEndedToast(memberName),
    );
  }

  void popIfAble() {
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  if (active.length > 1) {
    if (await safeEnd()) {
      showEndedToast();
      popIfAble();
    }
    return;
  }

  final choice = await _showNextFronterDialog(
    context,
    pickLabel: frontingTerms.setAsAction,
    endLabel: frontingTerms.endWithoutAction,
  );
  if (choice == null || !context.mounted) return;

  final showSheet = showAddSheetOverride ?? AddFrontSessionSheet.show;

  switch (choice) {
    case _NextFronterChoice.pickFronter:
      final started = await showSheet(context);
      if (started == true && context.mounted && await safeEnd()) {
        showEndedToast();
        popIfAble();
      }
    case _NextFronterChoice.unknown:
      if (await safeEnd()) {
        await safeStartUnknown();
        showEndedToast();
        popIfAble();
      }
    case _NextFronterChoice.endWithoutFronting:
      if (await safeEnd()) {
        showEndedToast();
        popIfAble();
      }
  }
}

class _FloatingEndSessionButton extends ConsumerWidget {
  const _FloatingEndSessionButton({
    required this.memberName,
    required this.tintColor,
    required this.onPressed,
  });

  final String memberName;
  final Color tintColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pillRadius = BorderRadius.circular(PrismTokens.radiusPill);
    final label = watchFrontingTerms(context, ref).endCurrentAction;

    return Semantics(
      button: true,
      enabled: true,
      label: memberName.isEmpty
          ? label
          : context.l10n.frontingActionFor(label, memberName),
      child: GlassSurface(
        borderRadius: pillRadius,
        tint: tintColor,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: pillRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.exitToApp,
                    size: 18,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfidenceDisplay extends StatelessWidget {
  const _ConfidenceDisplay({required this.confidence});

  final FrontConfidence confidence;

  int get _level => confidence.index + 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final labels = {
      FrontConfidence.unsure: l10n.frontingConfidenceUnsure,
      FrontConfidence.strong: l10n.frontingConfidenceStrong,
      FrontConfidence.certain: l10n.frontingConfidenceCertain,
    };

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
          labels[confidence]!,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
