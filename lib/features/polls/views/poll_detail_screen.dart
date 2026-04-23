import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';

/// Detail screen for a single poll with voting and results.
class PollDetailScreen extends ConsumerWidget {
  const PollDetailScreen({super.key, required this.pollId});

  final String pollId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pollAsync = ref.watch(pollByIdProvider(pollId));
    final optionsAsync = ref.watch(pollOptionsProvider(pollId));

    return pollAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: '', showBackButton: true),
        bodyPadding: EdgeInsets.zero,
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: '', showBackButton: true),
        bodyPadding: EdgeInsets.zero,
        body: Center(child: Text(context.l10n.pollsDetailLoadError(e))),
      ),
      data: (poll) {
        if (poll == null) {
          return PrismPageScaffold(
            topBar: const PrismTopBar(title: '', showBackButton: true),
            bodyPadding: EdgeInsets.zero,
            body: Center(child: Text(context.l10n.pollsDetailNotFound)),
          );
        }

        final options = optionsAsync.value ?? poll.options;
        return _PollDetailBody(poll: poll, options: options);
      },
    );
  }
}

class _PollDetailBody extends ConsumerStatefulWidget {
  const _PollDetailBody({required this.poll, required this.options});

  final Poll poll;
  final List<PollOption> options;

  @override
  ConsumerState<_PollDetailBody> createState() => _PollDetailBodyState();
}

class _PollDetailBodyState extends ConsumerState<_PollDetailBody> {
  // For single-vote mode
  String? _selectedOptionId;
  // For multi-vote mode
  final Set<String> _selectedOptionIds = {};
  String? _syncedOptionId;
  Set<String> _syncedOptionIds = const {};
  String _syncedOtherText = '';
  String? _syncedVotingAs;
  // For "Other" option text
  final _otherTextController = TextEditingController();
  // Suppresses result display during multi-vote submission
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Auto-select voting-as member: prefer current fronter, fall back to first active member.
    ref.listenManual(activeMembersProvider, (_, next) {
      _queueDefaultVotingAs(next.value);
    }, fireImmediately: true);
    ref.listenManual<String?>(votingAsProvider, (_, next) {
      _syncSelectionFromVotes(votingAs: next, force: true);
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(covariant _PollDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelectionFromVotes(votingAs: ref.read(votingAsProvider));
  }

  @override
  void dispose() {
    _otherTextController.dispose();
    super.dispose();
  }

  bool get _isClosed {
    final now = DateTime.now();
    return widget.poll.isClosed ||
        (widget.poll.expiresAt != null && widget.poll.expiresAt!.isBefore(now));
  }

  int get _totalVotes {
    return widget.options.fold<int>(
      0,
      (sum, option) => sum + option.votes.length,
    );
  }

  bool get _hasCurrentMemberVoted {
    final votingAs = ref.read(votingAsProvider);
    if (votingAs == null) return false;
    return widget.options.any(
      (option) => option.votes.any((vote) => vote.memberId == votingAs),
    );
  }

  bool get _hasPendingVoteChanges {
    final votingAs = ref.read(votingAsProvider);
    if (votingAs == null) return false;
    final persistedOptionId = _persistedSelectedOptionId(votingAs);
    final persistedOptionIds = _persistedSelectedOptionIds(votingAs);
    final persistedOtherText = _persistedOtherText(votingAs);

    if (widget.poll.allowsMultipleVotes) {
      return !_setEquals(_selectedOptionIds, persistedOptionIds) ||
          _otherTextController.text.trim() != persistedOtherText;
    }

    return _selectedOptionId != persistedOptionId ||
        _otherTextController.text.trim() != persistedOtherText;
  }

  bool get _hasSelection {
    return widget.poll.allowsMultipleVotes
        ? _selectedOptionIds.isNotEmpty
        : _selectedOptionId != null;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  String? _persistedSelectedOptionId(String? memberId) {
    if (memberId == null) return null;

    PollVote? latestVote;
    String? selectedOptionId;
    for (final option in widget.options) {
      for (final vote in option.votes) {
        if (vote.memberId != memberId) continue;
        if (latestVote == null || vote.votedAt.isAfter(latestVote.votedAt)) {
          latestVote = vote;
          selectedOptionId = option.id;
        }
      }
    }
    return selectedOptionId;
  }

  Set<String> _persistedSelectedOptionIds(String? memberId) {
    if (memberId == null) return const {};

    final optionIds = <String>{};
    for (final option in widget.options) {
      if (option.votes.any((vote) => vote.memberId == memberId)) {
        optionIds.add(option.id);
      }
    }
    return optionIds;
  }

  String _persistedOtherText(String? memberId) {
    if (memberId == null) return '';

    PollVote? latestVote;
    for (final option in widget.options) {
      if (!option.isOtherOption) continue;
      for (final vote in option.votes) {
        if (vote.memberId != memberId) continue;
        if (latestVote == null || vote.votedAt.isAfter(latestVote.votedAt)) {
          latestVote = vote;
        }
      }
    }
    return latestVote?.responseText?.trim() ?? '';
  }

  bool _selectionMatchesSyncedVote() {
    return _selectedOptionId == _syncedOptionId &&
        _setEquals(_selectedOptionIds, _syncedOptionIds) &&
        _otherTextController.text.trim() == _syncedOtherText;
  }

  void _syncSelectionFromVotes({
    required String? votingAs,
    bool force = false,
  }) {
    final persistedOptionId = _persistedSelectedOptionId(votingAs);
    final persistedOptionIds = _persistedSelectedOptionIds(votingAs);
    final persistedOtherText = _persistedOtherText(votingAs);
    final shouldReplaceLocalState =
        force || _syncedVotingAs != votingAs || _selectionMatchesSyncedVote();

    _syncedVotingAs = votingAs;
    _syncedOptionId = persistedOptionId;
    _syncedOptionIds = persistedOptionIds;
    _syncedOtherText = persistedOtherText;

    if (!mounted || !shouldReplaceLocalState) return;

    final needsUpdate =
        _selectedOptionId != persistedOptionId ||
        !_setEquals(_selectedOptionIds, persistedOptionIds) ||
        _otherTextController.text != persistedOtherText;
    if (!needsUpdate) return;

    setState(() {
      _selectedOptionId = persistedOptionId;
      _selectedOptionIds
        ..clear()
        ..addAll(persistedOptionIds);
      _otherTextController.text = persistedOtherText;
    });
  }

  void _queueDefaultVotingAs(List<Member>? members) {
    if (members == null || members.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(votingAsProvider) != null) return;

      final fronter = ref.read(activeSessionProvider).value;
      final fronterId = fronter?.memberId;
      final defaultId =
          (fronterId != null && members.any((m) => m.id == fronterId))
          ? fronterId
          : members.first.id;
      ref.read(votingAsProvider.notifier).setMember(defaultId);
    });
  }

  /// Whether results (progress bars, percentages, vote counts, voter names)
  /// should be visible. Results are hidden until at least one system member
  /// has voted OR the poll is closed, and also hidden during multi-vote submission.
  bool get _shouldShowResults {
    if (_isSubmitting) return false;
    if (_isClosed) return true;
    final members = ref.read(activeMembersProvider).value;
    if (members == null || members.isEmpty) return false;
    final memberIds = members.map((m) => m.id).toSet();
    for (final option in widget.options) {
      for (final vote in option.votes) {
        if (memberIds.contains(vote.memberId)) return true;
      }
    }
    return false;
  }

  Future<void> _submitVote() async {
    final votingAs = ref.read(votingAsProvider);
    if (votingAs == null) {
      PrismToast.show(
        context,
        message: context.l10n.pollsVotingAsSelectPrompt(
          readTerminology(context, ref).singularLower,
        ),
      );
      return;
    }

    final notifier = ref.read(pollNotifierProvider.notifier);

    try {
      if (widget.poll.allowsMultipleVotes) {
        setState(() => _isSubmitting = true);
        for (final optionId in _selectedOptionIds) {
          final option = widget.options.firstWhere((o) => o.id == optionId);
          await notifier.addVote(
            pollId: widget.poll.id,
            optionId: optionId,
            memberId: votingAs,
            responseText: option.isOtherOption
                ? _otherTextController.text.trim()
                : null,
          );
        }
      } else if (_selectedOptionId != null) {
        final option = widget.options.firstWhere(
          (o) => o.id == _selectedOptionId,
        );
        await notifier.addVote(
          pollId: widget.poll.id,
          optionId: _selectedOptionId!,
          memberId: votingAs,
          responseText: option.isOtherOption
              ? _otherTextController.text.trim()
              : null,
        );
      }

      if (mounted) {
        PrismToast.show(
          context,
          message: context.l10n.pollsDetailVoteSubmitted,
        );
        setState(() {
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        PrismToast.error(
          context,
          message: context.l10n.pollsDetailVoteError(e),
        );
      }
    }
  }

  Future<void> _confirmClose() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.pollsDetailClosePollTitle,
      message: context.l10n.pollsDetailClosePollMessage,
      confirmLabel: context.l10n.pollsDetailClosePollConfirm,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(
        ref.read(pollNotifierProvider.notifier).closePoll(widget.poll.id),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.pollsDetailDeleteTitle,
      message: context.l10n.pollsDetailDeleteMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(
        ref.read(pollNotifierProvider.notifier).deletePoll(widget.poll.id),
      );
      if (mounted) context.go(AppRoutePaths.polls);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final votingAs = ref.watch(votingAsProvider);
    final hasCurrentMemberVoted = _hasCurrentMemberVoted;
    final hasPendingVoteChanges = _hasPendingVoteChanges;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          if (!_isClosed)
            PrismTopBarAction(
              icon: AppIcons.lockOutline,
              tooltip: context.l10n.pollsDetailClosePollTooltip,
              onPressed: _confirmClose,
            ),
          BlurPopupAnchor(
            trigger: BlurPopupTrigger.tap,
            preferredDirection: BlurPopupDirection.down,
            width: 180,
            maxHeight: 120,
            itemCount: 1,
            itemBuilder: (context, index, close) {
              final theme = Theme.of(context);
              final color = theme.colorScheme.error;
              return PrismListRow(
                dense: true,
                leading: Icon(AppIcons.deleteOutline, size: 20, color: color),
                title: Text(
                  context.l10n.delete,
                  style: TextStyle(fontSize: 14, color: color),
                ),
                onTap: () {
                  close();
                  _confirmDelete();
                },
              );
            },
            child: PrismTopBarAction(
              icon: AppIcons.moreVert,
              tooltip: context.l10n.pollsDetailMoreOptions,
              onPressed: null,
            ),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, NavBarInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Question
            Text(
              widget.poll.question,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            // Description
            if (widget.poll.description != null &&
                widget.poll.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              MarkdownText(
                data: widget.poll.description!,
                enabled: true,
                baseStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),

            // Metadata
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _MetadataChip(
                  icon: AppIcons.calendarToday,
                  label: widget.poll.createdAt.toDateString(),
                ),
                if (widget.poll.expiresAt != null)
                  _MetadataChip(
                    icon: AppIcons.schedule,
                    label: _isClosed
                        ? context.l10n.pollsDetailExpired
                        : context.l10n.pollsDetailExpiresLabel(
                            widget.poll.expiresAt!.toDateString(),
                          ),
                  ),
                if (widget.poll.isAnonymous)
                  _MetadataChip(
                    icon: AppIcons.visibilityOffOutlined,
                    label: context.l10n.pollsAnonymous,
                  ),
                if (widget.poll.allowsMultipleVotes)
                  _MetadataChip(
                    icon: AppIcons.checkBoxOutlined,
                    label: context.l10n.pollsMultiVote,
                  ),
                if (_isClosed)
                  _MetadataChip(
                    icon: AppIcons.lockOutline,
                    label: context.l10n.pollsClosed,
                  ),
              ],
            ),
            if (hasCurrentMemberVoted) ...[
              const SizedBox(height: 12),
              PrismPill(
                icon: AppIcons.checkCircleOutline,
                label: context.l10n.pollsDetailVoteSubmitted,
                tone: PrismPillTone.accent,
              ),
            ],

            const SizedBox(height: 24),

            // Voting-as picker
            if (!_isClosed) ...[
              Text(
                context.l10n.pollsDetailVoteAs,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              membersAsync.when(
                data: (members) {
                  if (members.isEmpty) {
                    return Text(
                      context.l10n.pollsDetailNoMembers,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return _VotingAsChipRow(
                    members: members,
                    votingAs: votingAs,
                    options: widget.options,
                    onSelectMember: (id) =>
                        ref.read(votingAsProvider.notifier).setMember(id),
                  );
                },
                loading: () => const PrismLoadingState(),
                error: (_, _) => Text(context.l10n.error),
              ),
              const SizedBox(height: 24),
            ],

            // Options / voting UI
            Text(
              _isClosed
                  ? context.l10n.pollsDetailResultsLabel
                  : context.l10n.pollsDetailOptionsLabel,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            ...widget.options.map((option) {
              return _OptionTile(
                option: option,
                totalVotes: _totalVotes,
                isClosed: _isClosed,
                showResults: _shouldShowResults,
                isAnonymous: widget.poll.isAnonymous,
                isMultiVote: widget.poll.allowsMultipleVotes,
                isSelected: widget.poll.allowsMultipleVotes
                    ? _selectedOptionIds.contains(option.id)
                    : _selectedOptionId == option.id,
                otherTextController: option.isOtherOption
                    ? _otherTextController
                    : null,
                onSelected: _isClosed
                    ? null
                    : () {
                        setState(() {
                          if (widget.poll.allowsMultipleVotes) {
                            if (_selectedOptionIds.contains(option.id)) {
                              _selectedOptionIds.remove(option.id);
                            } else {
                              _selectedOptionIds.add(option.id);
                            }
                          } else {
                            _selectedOptionId = _selectedOptionId == option.id
                                ? null
                                : option.id;
                          }
                        });
                      },
              );
            }),

            // Vote button
            if (!_isClosed &&
                (!_hasCurrentMemberVoted || hasPendingVoteChanges)) ...[
              const SizedBox(height: 16),
              PrismButton(
                label: context.l10n.pollsDetailSubmitVote,
                tone: PrismButtonTone.filled,
                expanded: true,
                enabled: _hasSelection && hasPendingVoteChanges,
                onPressed: _submitVote,
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Voting-as chip row ────────────────────────────────────────────────────

/// Horizontal scrolling chip row for selecting who is voting.
///
/// Order: [Select chip] → current fronter (if any) → others sorted by
/// fronting frequency descending.
///
/// Voted members show a checkmark overlay on their avatar to indicate
/// they have already cast a vote.
class _VotingAsChipRow extends ConsumerWidget {
  const _VotingAsChipRow({
    required this.members,
    required this.votingAs,
    required this.options,
    required this.onSelectMember,
  });

  final List<Member> members;
  final String? votingAs;
  final List<PollOption> options;
  final ValueChanged<String> onSelectMember;

  bool _hasVoted(String memberId) {
    return options.any(
      (option) => option.votes.any((vote) => vote.memberId == memberId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSession = ref.watch(activeSessionProvider).value;
    final currentFronterId = activeSession?.memberId;
    final frontingCountsAsync = ref.watch(memberFrontingCountsProvider);
    final frontingCounts = frontingCountsAsync.value ?? const {};
    final termPlural = watchTerminology(context, ref).pluralLower;

    // Build the ordered member list: fronter first, then by frequency desc.
    final fronterMember = currentFronterId != null
        ? members.where((m) => m.id == currentFronterId).firstOrNull
        : null;
    final others = members.where((m) => m.id != currentFronterId).toList()
      ..sort((a, b) {
        final countA = frontingCounts[a.id] ?? 0;
        final countB = frontingCounts[b.id] ?? 0;
        return countB.compareTo(countA);
      });

    final orderedMembers = [?fronterMember, ...others];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: orderedMembers.length + 1, // +1 for the Select chip
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          // First item: [Select] chip
          if (index == 0) {
            return _SelectChip(
              members: members,
              termPlural: termPlural,
              onSelectMember: onSelectMember,
            );
          }
          final member = orderedMembers[index - 1];
          final isSelected = votingAs == member.id;
          final voted = _hasVoted(member.id);
          return PrismChip(
            label: member.name,
            selected: isSelected,
            onTap: () => onSelectMember(member.id),
            avatar: Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  memberName: member.name,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 24,
                ),
                if (voted)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        AppIcons.check,
                        size: 8,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            selectedColor:
                member.customColorEnabled && member.customColorHex != null
                ? AppColors.fromHex(member.customColorHex!)
                : null,
          );
        },
      ),
    );
  }
}

/// The leading [Select] chip that opens the shared member search sheet.
class _SelectChip extends ConsumerWidget {
  const _SelectChip({
    required this.members,
    required this.termPlural,
    required this.onSelectMember,
  });

  final List<Member> members;
  final String termPlural;
  final ValueChanged<String> onSelectMember;

  Future<void> _openSearch(
    BuildContext context,
    List<MemberSearchGroup> groups,
  ) async {
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: termPlural,
      groups: groups,
    );
    if (result case MemberSearchResultSelected(:final memberId)) {
      onSelectMember(memberId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchGroups = watchMemberSearchGroups(ref, members);
    return PrismChip(
      label: context.l10n.search,
      selected: false,
      onTap: () => _openSearch(context, searchGroups),
      avatar: Icon(
        AppIcons.search,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ── Option tile ───────────────────────────────────────────────────────────

class _OptionTile extends ConsumerWidget {
  const _OptionTile({
    required this.option,
    required this.totalVotes,
    required this.isClosed,
    required this.showResults,
    required this.isAnonymous,
    required this.isMultiVote,
    required this.isSelected,
    this.otherTextController,
    this.onSelected,
  });

  final PollOption option;
  final int totalVotes;
  final bool isClosed;
  final bool showResults;
  final bool isAnonymous;
  final bool isMultiVote;
  final bool isSelected;
  final TextEditingController? otherTextController;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final voteCount = option.votes.length;
    final percentage = totalVotes > 0 ? voteCount / totalVotes : 0.0;

    return PrismSurface(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onSelected,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Selection indicator
              if (!isClosed)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: isMultiVote
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => onSelected?.call(),
                        )
                      : Icon(
                          isSelected
                              ? AppIcons.radioButtonChecked
                              : AppIcons.radioButtonUnchecked,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                ),

              // Option color dot
              if (option.colorHex != null && option.colorHex!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(
                        int.parse('FF${option.colorHex}', radix: 16),
                      ),
                    ),
                  ),
                ),

              Expanded(
                child: Text(
                  option.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),

              // Vote count (only when results are visible)
              if (showResults)
                Text(
                  '$voteCount',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),

          // "Other" text field
          if (option.isOtherOption &&
              isSelected &&
              !isClosed &&
              otherTextController != null) ...[
            const SizedBox(height: 8),
            PrismTextField(
              controller: otherTextController,
              hintText: context.l10n.pollsDetailOtherResponseHint,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              isDense: true,
            ),
          ],

          // Results bar
          if (showResults) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(4),
              ),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: option.colorHex != null && option.colorHex!.isNotEmpty
                    ? Color(int.parse('FF${option.colorHex}', radix: 16))
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(percentage * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          // Voter names (if not anonymous and results are visible)
          if (!isAnonymous && showResults && option.votes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _VoterNames(votes: option.votes),
          ],
        ],
      ),
    );
  }
}

// ── Voter names ───────────────────────────────────────────────────────────

class _VoterNames extends ConsumerWidget {
  const _VoterNames({required this.votes});

  final List<PollVote> votes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: votes.map((vote) {
        final memberAsync = ref.watch(memberByIdProvider(vote.memberId));
        final name = memberAsync.value?.name ?? 'Unknown';
        return PrismPill(
          label: vote.responseText != null && vote.responseText!.isNotEmpty
              ? '$name: ${vote.responseText}'
              : name,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        );
      }).toList(),
    );
  }
}

// ── Metadata chip ─────────────────────────────────────────────────────────

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
