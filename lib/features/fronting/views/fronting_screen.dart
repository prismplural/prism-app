import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/add_front_session_sheet.dart';
import 'package:prism_plurality/features/fronting/views/empty_system_view.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/polls/views/create_poll_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';

class FrontingScreen extends ConsumerStatefulWidget {
  const FrontingScreen({super.key});

  @override
  ConsumerState<FrontingScreen> createState() => _FrontingScreenState();
}

class _FrontingScreenState extends ConsumerState<FrontingScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);

    // Scroll to top when the home tab is re-tapped.
    ref.listen(tabRetapProvider, (_, _) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });

    final isEmpty = membersAsync.whenOrNull(data: (members) => members.isEmpty);

    final settingsAsync = ref.watch(systemSettingsProvider);
    final systemName =
        settingsAsync.whenOrNull(data: (s) => s.systemName) ?? 'Prism';

    if (isEmpty == true) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            PrismTopBar(title: systemName),
            const Expanded(child: EmptySystemView()),
          ],
        ),
      );
    }

    final sleepAsync = ref.watch(activeSleepSessionProvider);
    final isSleeping = sleepAsync.value != null;
    final isTimelineView = ref.watch(timelineViewActiveProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isTimelineView
          ? _buildTimelineView(theme, systemName, isSleeping, sleepAsync.value)
          : _buildListView(theme, systemName, isSleeping, sleepAsync.value),
    );
  }

  List<Widget> _buildActions(bool isSleeping, SleepSession? sleepSession) {
    final isTimelineView = ref.watch(timelineViewActiveProvider);
    return [
      PrismTopBarAction(
        icon: isTimelineView
            ? Icons.view_list_rounded
            : Icons.timeline_rounded,
        tooltip: isTimelineView ? 'List view' : 'Timeline view',
        onPressed: () => ref
            .read(timelineViewActiveProvider.notifier)
            .toggle(),
      ),
      _AddButton(
        isSleeping: isSleeping,
        sleepSession: sleepSession,
      ),
    ];
  }

  Widget _buildListView(
    ThemeData theme,
    String systemName,
    bool isSleeping,
    SleepSession? sleepSession,
  ) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPinnedTopBar(
          child: PrismTopBar(
            title: systemName,
            actions: _buildActions(isSleeping, sleepSession),
          ),
        ),

        // 1. Quick Front (always at top, matching SwiftUI)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: QuickFrontSection(),
          ),
        ),

        // 2b. Timeline issue banner (shown when post-edit or post-sync
        //     rescan detects validation issues).
        SliverToBoxAdapter(
          child: _TimelineIssueBanner(theme: theme),
        ),

        // 3. Sessions grouped by day (active session naturally at top)
        const SessionHistoryList(limit: 30),

        // Bottom padding to clear floating nav bar
        SliverPadding(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        ),
      ],
    );
  }

  Widget _buildTimelineView(
    ThemeData theme,
    String systemName,
    bool isSleeping,
    SleepSession? sleepSession,
  ) {
    return Column(
      children: [
        PrismTopBar(
          title: systemName,
          actions: _buildActions(isSleeping, sleepSession),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: NavBarInset.of(context),
            ),
            child: const TimelineView(),
          ),
        ),
      ],
    );
  }
}

/// Displays a warning banner when the post-edit (or future post-sync) rescan
/// detects timeline validation issues. Hidden when the count is zero.
class _TimelineIssueBanner extends ConsumerWidget {
  const _TimelineIssueBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issueCount = ref.watch(frontingIssueCountProvider);
    if (issueCount <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InfoBanner(
        icon: Icons.warning_amber_rounded,
        iconColor: theme.colorScheme.error,
        title: 'Timeline issues found',
        message:
            '$issueCount timeline issue${issueCount > 1 ? 's' : ''} found. Tap to review.',
        buttonText: 'Review',
        onButtonPressed: () =>
            context.push('/settings/timeline-sanitization'),
      ),
    );
  }
}

/// App bar action button: tap for Log Front, long-press for context menu.
class _AddButton extends ConsumerStatefulWidget {
  const _AddButton({required this.isSleeping, required this.sleepSession});

  final bool isSleeping;
  final SleepSession? sleepSession;

  @override
  ConsumerState<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends ConsumerState<_AddButton> {
  final _popupKey = GlobalKey<BlurPopupAnchorState>();

  bool get isSleeping => widget.isSleeping;
  SleepSession? get sleepSession => widget.sleepSession;

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(terminologyProvider);

    // Build menu items for the blur popup.
    final menuItems = <_MenuItem>[];

    if (isSleeping && sleepSession != null) {
      menuItems.add(
        _MenuItem(
          icon: Icons.wb_sunny_rounded,
          label: 'Wake Up As...',
          onTap: (close) {
            close();
            _showWakeUpPicker(context, ref);
          },
        ),
      );
    }

    menuItems.addAll([
      _MenuItem(
        icon: Icons.person_outline,
        label: 'Log Front',
        onTap: (close) {
          close();
          _openAddSessionSheet(context);
        },
      ),
      _MenuItem(
        icon: Icons.person_add_outlined,
        label: terms.addButtonText,
        onTap: (close) {
          close();
          PrismSheet.showFullScreen(
            context: context,
            builder: (context, scrollController) => AddEditMemberSheet(
              scrollController: scrollController,
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.poll_outlined,
        label: 'New Poll',
        onTap: (close) {
          close();
          PrismSheet.showFullScreen(
            context: context,
            builder: (context, scrollController) => CreatePollSheet(
              scrollController: scrollController,
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.bedtime_rounded,
        label: 'Start Sleep',
        enabled: !isSleeping,
        onTap: (close) {
          close();
          PrismSheet.showFullScreen(
            context: context,
            useRootNavigator: true,
            builder: (ctx, sc) => StartSleepSheet(scrollController: sc),
          );
        },
      ),
    ]);

    return BlurPopupAnchor(
      key: _popupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: BlurPopupDirection.down,
      width: 200,
      maxHeight: 320,
      itemCount: menuItems.length,
      itemBuilder: (context, index, close) {
        final item = menuItems[index];
        final theme = Theme.of(context);
        return ListTile(
          dense: true,
          leading: Icon(
            item.icon,
            size: 20,
            color: item.enabled
                ? theme.colorScheme.onSurface
                : theme.disabledColor,
          ),
          title: Text(
            item.label,
            style: TextStyle(
              fontSize: 14,
              color: item.enabled
                  ? theme.colorScheme.onSurface
                  : theme.disabledColor,
            ),
          ),
          enabled: item.enabled,
          onTap: item.enabled ? () => item.onTap(close) : null,
        );
      },
      child: PrismTopBarAction(
        icon: Icons.add,
        tooltip: 'Add fronting entry',
        onPressed: () => _openAddSessionSheet(context),
        onLongPress: () => _popupKey.currentState?.show(),
      ),
    );
  }

  void _openAddSessionSheet(BuildContext context) {
    AddFrontSessionSheet.show(context);
  }

  void _showWakeUpPicker(BuildContext context, WidgetRef ref) {
    final members = ref.read(activeMembersProvider).value ?? [];

    PrismDialog.show<void>(
      context: context,
      title: 'Wake Up As...',
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: members
              .map(
                (member) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    member.emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(member.name),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref
                        .read(sleepNotifierProvider.notifier)
                        .endSleep(sleepSession!.id);
                    ref
                        .read(frontingNotifierProvider.notifier)
                        .startFronting(member.id);
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final void Function(VoidCallback close) onTap;
  final bool enabled;
}
