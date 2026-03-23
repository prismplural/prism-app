import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
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

  Future<void> _submitVote() async {
    final votingAs = ref.read(votingAsProvider);
    if (votingAs == null) {
      PrismToast.show(context, message: '${ref.read(terminologyProvider).selectText} to vote as');
      return;
    }

    final notifier = ref.read(pollNotifierProvider.notifier);

    try {
      if (widget.poll.allowsMultipleVotes) {
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
          _selectedOptionId = null;
          _selectedOptionIds.clear();
          _otherTextController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
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

    // Auto-select voting-as if not set
    membersAsync.whenData((members) {
      if (votingAs == null && members.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(votingAsProvider.notifier).setMember(members.first.id);
        });
      }
    });

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Poll',
        showBackButton: true,
        actions: [
          if (!_isClosed)
            PrismTopBarAction(
              icon: Icons.lock_outline,
              tooltip: 'Close poll',
              onPressed: _confirmClose,
            ),
          PrismPopupMenu<String>(
            items: [
              const PrismMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline, destructive: true),
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
                  icon: Icons.calendar_today,
                  label: _formatDate(widget.poll.createdAt),
                ),
                if (widget.poll.expiresAt != null)
                  _MetadataChip(
                    icon: Icons.schedule,
                    label: _isClosed
                        ? 'Expired'
                        : 'Expires ${_formatDate(widget.poll.expiresAt!)}',
                  ),
                if (widget.poll.isAnonymous)
                  const _MetadataChip(
                    icon: Icons.visibility_off_outlined,
                    label: 'Anonymous',
                  ),
                if (widget.poll.allowsMultipleVotes)
                  const _MetadataChip(
                    icon: Icons.check_box_outlined,
                    label: 'Multi-vote',
                  ),
                if (_isClosed)
                  const _MetadataChip(
                    icon: Icons.lock_outline,
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
                        return ChoiceChip(
                          avatar: MemberAvatar(
                            avatarImageData: member.avatarImageData,
                            emoji: member.emoji,
                            customColorEnabled: member.customColorEnabled,
                            customColorHex: member.customColorHex,
                            size: 24,
                          ),
                          label: Text(member.name),
                          selected: isSelected,
                          onSelected: (_) {
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
    required this.isAnonymous,
    required this.isMultiVote,
    required this.isSelected,
    this.otherTextController,
    this.onSelected,
  });

  final PollOption option;
  final int totalVotes;
  final bool isClosed;
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
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
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

                  // Vote count
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
              if (isClosed || totalVotes > 0) ...[
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

              // Voter names (if not anonymous and poll is closed or has votes)
              if (!isAnonymous && option.votes.isNotEmpty) ...[
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
