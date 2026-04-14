import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Displays reactions on a message and allows toggling them.
class ReactionBar extends ConsumerWidget {
  const ReactionBar({
    super.key,
    required this.messageId,
    required this.reactions,
  });

  final String messageId;
  final List<MessageReaction> reactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final speakingAs = ref.watch(speakingAsProvider);

    // Group reactions by emoji
    final grouped = <String, List<MessageReaction>>{};
    for (final reaction in reactions) {
      grouped.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: grouped.entries.map((entry) {
        final emoji = entry.key;
        final reactionList = entry.value;
        final count = reactionList.length;
        final hasReacted = speakingAs != null &&
            reactionList.any((r) => r.memberId == speakingAs);

        return Semantics(
          button: true,
          label: 'Add reaction $emoji',
          child: GestureDetector(
          onTap: () {
            if (speakingAs == null) return;
            Haptics.light();
            ref.read(chatNotifierProvider.notifier).toggleReaction(
                  messageId: messageId,
                  emoji: emoji,
                  memberId: speakingAs,
                );
          },
          onLongPress: () =>
              _showReactors(context, ref, emoji, reactionList),
          child: _ScalePulse(
            // Re-trigger animation when reaction count changes
            key: ValueKey('$emoji-$count'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: hasReacted
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                border: hasReacted
                    ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MemberAvatar.centeredEmoji(emoji, fontSize: 14),
                  if (count > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hasReacted
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        );
      }).toList(),
    );
  }

  void _showReactors(
    BuildContext context,
    WidgetRef ref,
    String emoji,
    List<MessageReaction> reactionList,
  ) {
    // Collect all unique member IDs for batch loading.
    final uniqueIds = reactionList.map((r) => r.memberId).toSet();
    final idsKey = memberIdsKey(uniqueIds);

    PrismDialog.show<void>(
      context: context,
      title: '$emoji Reactions',
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final membersAsync = ref.watch(membersByIdsProvider(idsKey));
            return membersAsync.when(
              data: (memberMap) => Column(
                mainAxisSize: MainAxisSize.min,
                children: reactionList
                    .map((reaction) {
                      final member = memberMap[reaction.memberId];
                      return PrismListRow(
                        dense: true,
                        padding: EdgeInsets.zero,
                        leading: MemberAvatar.centeredEmoji(
                          member?.emoji ?? '?',
                          fontSize: 24,
                        ),
                        title: Text(member?.name ?? context.l10n.unknown),
                      );
                    })
                    .toList(),
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => Text(context.l10n.error),
            );
          },
        );
      },
    );
  }
}

/// Brief scale pulse animation on mount (key change).
class _ScalePulse extends StatefulWidget {
  const _ScalePulse({super.key, required this.child});

  final Widget child;

  @override
  State<_ScalePulse> createState() => _ScalePulseState();
}

class _ScalePulseState extends State<_ScalePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward().then((_) {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Quick-reaction picker shown when long-pressing a message.
class QuickReactionPicker extends StatelessWidget {
  const QuickReactionPicker({
    super.key,
    required this.onReactionSelected,
  });

  final ValueChanged<String> onReactionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.warmBlack.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppConstants.quickReactions.map((emoji) {
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onReactionSelected(emoji),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: MemberAvatar.centeredEmoji(emoji, fontSize: 22),
            ),
          );
        }).toList(),
      ),
    );
  }
}
