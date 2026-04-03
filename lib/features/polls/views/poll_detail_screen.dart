import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
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
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

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
        topBar: PrismTopBar(title: 'Poll', showBackButton: true),
        bodyPadding: EdgeInsets.zero,
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: 'Poll', showBackButton: true),
        bodyPadding: EdgeInsets.zero,
        body: Center(child: Text('Error loading poll: $e')),
      ),
      data: (poll) {
        if (poll == null) {
          return const PrismPageScaffold(
            topBar: PrismTopBar(title: 'Poll', showBackButton: true),
            bodyPadding: EdgeInsets.zero,
            body: Center(child: Text('Poll not found')),
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
  // For "Other" option text
  final _otherTextController = TextEditingController();
  // Suppresses result display during multi-vote submission
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Auto-select voting-as member: prefer current fronter, fall back to first active member.
    ref.listenManual(activeMembersProvider, (_, next) {
      final members = next.value;
      if (members != null &&
          members.isNotEmpty &&
          ref.read(votingAsProvider) == null) {
        final fronter = ref.read(activeSessionProvider).value;
        final fronterId = fronter?.memberId;
        // Use the current fronter if they are in the active members list.
        final defaultId = (fronterId != null &&
                members.any((m) => m.id == fronterId))
            ? fronterId
            : members.first.id;
        ref.read(votingAsProvider.notifier).setMember(defaultId);
      }
    }, fireImmediately: true);
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
      PrismToast.show(context, message: '${ref.read(terminologyProvider).selectText} to vote as');
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
        PrismToast.show(context, message: 'Vote submitted');
        setState(() {
          _isSubmitting = false;
          _selectedOptionId = null;
          _selectedOptionIds.clear();
          _otherTextController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        PrismToast.error(context, message: 'Failed to vote: $e');
      }
    }
  }

  Future<void> _confirmClose() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Close poll?',
      message: 'No more votes can be cast once the poll is closed. '
          'This cannot be undone.',
      confirmLabel: 'Close Poll',
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      ref.read(pollNotifierProvider.notifier).closePoll(widget.poll.id);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete poll?',
      message: 'This will permanently delete the poll and all votes. '
          'This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      ref.read(pollNotifierProvider.notifier).deletePoll(widget.poll.id);
      if (mounted) context.go(AppRoutePaths.polls);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final votingAs = ref.watch(votingAsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Poll',
        showBackButton: true,
        actions: [
          if (!_isClosed)
            PrismTopBarAction(
              icon: AppIcons.lockOutline,
              tooltip: 'Close poll',
              onPressed: _confirmClose,
            ),
          PrismPopupMenu<String>(
            items: [
              PrismMenuItem(value: 'delete', label: 'Delete', icon: AppIcons.deleteOutline, destructive: true),
            ],
            onSelected: (action) {
              if (action == 'delete') _confirmDelete();
            },
            tooltip: 'More options',
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
                  label: _formatDate(widget.poll.createdAt),
                ),
                if (widget.poll.expiresAt != null)
                  _MetadataChip(
                    icon: AppIcons.schedule,
                    label: _isClosed
                        ? 'Expired'
                        : 'Expires ${_formatDate(widget.poll.expiresAt!)}',
                  ),
                if (widget.poll.isAnonymous)
                  _MetadataChip(
                    icon: AppIcons.visibilityOffOutlined,
                    label: 'Anonymous',
                  ),
                if (widget.poll.allowsMultipleVotes)
                  _MetadataChip(
                    icon: AppIcons.checkBoxOutlined,
                    label: 'Multi-vote',
                  ),
                if (_isClosed)
                  _MetadataChip(
                    icon: AppIcons.lockOutline,
                    label: 'Closed',
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // Voting-as picker
            if (!_isClosed) ...[
              Text('Vote as', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              membersAsync.when(
                data: (members) {
                  if (members.isEmpty) {
                    return Text(
                      'No members available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: members.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final isSelected = votingAs == member.id;
                        return _VotingAsMemberChip(
                          member: member,
                          isSelected: isSelected,
                          onTap: () {
                            ref
                                .read(votingAsProvider.notifier)
                                .setMember(member.id);
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const PrismLoadingState(),
                error: (e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: 24),
            ],

            // Options / voting UI
            Text(
              _isClosed ? 'Results' : 'Options',
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
            if (!_isClosed) ...[
              const SizedBox(height: 16),
              PrismButton(
                label: 'Submit Vote',
                tone: PrismButtonTone.filled,
                expanded: true,
                enabled: _selectedOptionId != null ||
                    _selectedOptionIds.isNotEmpty,
                onPressed: _submitVote,
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: Padding(
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
                  if (option.colorHex != null &&
                      option.colorHex!.isNotEmpty)
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
                  hintText: 'Enter your response...',
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
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: option.colorHex != null &&
                            option.colorHex!.isNotEmpty
                        ? Color(
                            int.parse('FF${option.colorHex}', radix: 16),
                          )
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
        ),
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
    final theme = Theme.of(context);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: votes.map((vote) {
        final memberAsync = ref.watch(memberByIdProvider(vote.memberId));
        final name = memberAsync.value?.name ?? 'Unknown';
        return Chip(
          label: Text(
            vote.responseText != null && vote.responseText!.isNotEmpty
                ? '$name: ${vote.responseText}'
                : name,
            style: theme.textTheme.labelSmall,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }
}

// ── Voting-as member chip ──────────────────────────────────────────────────

class _VotingAsMemberChip extends StatelessWidget {
  const _VotingAsMemberChip({
    required this.member,
    required this.isSelected,
    required this.onTap,
  });

  final Member member;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: isSelected
              ? Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MemberAvatar(
              avatarImageData: member.avatarImageData,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 28,
            ),
            const SizedBox(width: 6),
            Text(
              member.name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
