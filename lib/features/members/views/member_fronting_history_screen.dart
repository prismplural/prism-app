import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

class MemberFrontingHistoryScreen extends ConsumerStatefulWidget {
  const MemberFrontingHistoryScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<MemberFrontingHistoryScreen> createState() =>
      _MemberFrontingHistoryScreenState();
}

class _MemberFrontingHistoryScreenState
    extends ConsumerState<MemberFrontingHistoryScreen> {
  final _scrollController = ScrollController();
  final _dayAnchors = <String, GlobalKey>{};
  var _dayKeys = const <String>[];
  String? _pendingJumpDayKey;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 300) return;

    final history = ref.read(memberFrontingHistoryProvider(widget.memberId));
    if (history.isLoading) return;
    if (history.value?.hasMore != true) return;
    _loadMore(announce: true);
  }

  void _loadMore({required bool announce}) {
    ref
        .read(memberFrontingHistoryLimitProvider(widget.memberId).notifier)
        .loadMore();
    if (announce) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.frontingLoadingOlderSessions,
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(activeMemberByIdProvider(widget.memberId));
    final frontingTerms = watchFrontingTerms(ref);

    ref.listen(memberFrontingHistoryProvider(widget.memberId), (_, next) {
      if (_pendingJumpDayKey == null || !next.hasValue) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolvePendingJump();
      });
    });

    return memberAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: '', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: '', showBackButton: true),
        body: Center(
          child: Text(
            'Error loading ${readTerminology(context, ref).singularLower}: $e',
          ),
        ),
      ),
      data: (member) {
        if (member == null) {
          return PrismPageScaffold(
            topBar: const PrismTopBar(title: '', showBackButton: true),
            body: Center(
              child: Text(
                '${readTerminology(context, ref).singular} not found',
              ),
            ),
          );
        }

        return PrismPageScaffold(
          topBar: PrismTopBar(
            title: memberFrontingHistoryTitleForWidth(
              context: context,
              memberName: member.effectiveName(
                preferDisplayName: ref.watch(memberNamePreferDisplayProvider),
              ),
              sessionPlural: frontingTerms.sessionPlural,
            ),
            showBackButton: true,
            actions: [
              Builder(
                builder: (anchorContext) => PrismTopBarAction(
                  icon: AppIcons.calendarTodayRounded,
                  tooltip: context.l10n.frontingTimelineJumpToDate,
                  onPressed: () => _pickDate(context, anchorContext),
                ),
              ),
            ],
          ),
          bodyPadding: EdgeInsets.zero,
          safeAreaBottom: false,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              MemberFrontingHistoryList(
                memberId: widget.memberId,
                dayAnchors: _dayAnchors,
                onDayKeysChanged: _onDayKeysChanged,
              ),
              Consumer(
                builder: (context, ref, _) {
                  final history = ref.watch(
                    memberFrontingHistoryProvider(widget.memberId),
                  );
                  final hasMore = history.value?.hasMore == true;
                  if (!hasMore) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: PrismLoadingState(),
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  key: const ValueKey('member-history-bottom-spacer'),
                  height: memberFrontingHistoryBottomSpacerHeight(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onDayKeysChanged(List<String> keys) {
    _dayKeys = keys;
    final known = keys.toSet();
    _dayAnchors.removeWhere((key, _) => !known.contains(key));
    if (_pendingJumpDayKey != null) _resolvePendingJump();
  }

  Future<void> _pickDate(
    BuildContext context,
    BuildContext anchorContext,
  ) async {
    final picked = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;

    _pendingJumpDayKey = DateTime(
      picked.year,
      picked.month,
      picked.day,
    ).toDayKey();
    _resolvePendingJump();
  }

  void _resolvePendingJump() {
    final dayKey = _pendingJumpDayKey;
    if (dayKey == null) return;

    final anchorContext = _dayAnchors[dayKey]?.currentContext;
    if (anchorContext != null) {
      _pendingJumpDayKey = null;
      Scrollable.ensureVisible(
        anchorContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      return;
    }

    final history = ref
        .read(memberFrontingHistoryProvider(widget.memberId))
        .value;
    if (history == null) return;

    final targetDay = DateTime.parse(dayKey);
    final oldest = history.oldestLoadedStart;
    if (history.hasMore && (oldest == null || oldest.isAfter(targetDay))) {
      _loadMore(announce: false);
      return;
    }

    final loadedIndex = _dayKeys.indexOf(dayKey);
    if (loadedIndex >= 0 && _scrollController.hasClients) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final denominator = (_dayKeys.length - 1).clamp(1, _dayKeys.length);
      final estimatedOffset = maxExtent * (loadedIndex / denominator);
      _scrollController
          .animateTo(
            estimatedOffset.clamp(0.0, maxExtent),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (mounted) _resolvePendingJump();
          });
      return;
    }

    _pendingJumpDayKey = null;
    final frontingTerms = readFrontingTerms(ref);
    PrismToast.show(
      context,
      message:
          'No ${frontingTerms.sessionPlural.toLowerCase()} found for that day.',
    );
  }
}

@visibleForTesting
double memberFrontingHistoryBottomSpacerHeight(BuildContext context) {
  return math.max(
        NavBarInset.of(context),
        MediaQuery.viewPaddingOf(context).bottom,
      ) +
      16;
}

@visibleForTesting
String memberFrontingHistoryTitleForWidth({
  required BuildContext context,
  required String memberName,
  required String sessionPlural,
}) {
  final fullTitle = "$memberName's $sessionPlural";
  final width = MediaQuery.sizeOf(context).width;
  final maxTitleWidth =
      width -
      PrismTokens.topBarPadding.horizontal -
      (PrismTokens.topBarActionSize * 2) -
      24;

  if (maxTitleWidth <= 0) return memberName;

  final theme = Theme.of(context);
  final isDesktop = width >= PrismTokens.desktopBreakpoint;
  final style =
      theme.textTheme.headlineLarge?.copyWith(
        fontSize: isDesktop ? 18 : 22,
        height: 1,
      ) ??
      TextStyle(fontSize: isDesktop ? 18 : 22, height: 1);

  final painter = TextPainter(
    text: TextSpan(text: fullTitle, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: double.infinity);

  return painter.width <= maxTitleWidth ? fullTitle : memberName;
}
