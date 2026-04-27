import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/utils/member_frequency_sort.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Top 4 most-frequently-fronting members as quick-switch buttons.
class QuickFrontSection extends ConsumerWidget {
  const QuickFrontSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(activeMembersProvider);
    final sessionsAsync = ref.watch(activeSessionsProvider);
    final countsAsync = ref.watch(memberFrontingCountsProvider);

    return membersAsync.when(
      loading: () => const SizedBox(
        height: 100,
        child: PrismLoadingState(),
      ),
      error: (_, _) => Text(context.l10n.error),
      data: (members) {
        final activeSessions = sessionsAsync.value ?? [];
        // Collect all member IDs with an open session — each session is one
        // member's continuous presence; co-fronting is emergent overlap.
        final frontingIds = <String>{};
        for (final s in activeSessions) {
          if (s.memberId != null) frontingIds.add(s.memberId!);
        }
        final counts = countsAsync.value ?? <String, int>{};

        // Pin the most-recently-started fronter at the head of quick tiles.
        final currentMemberId = activeSessions.isNotEmpty
            ? activeSessions.reduce((a, b) =>
                a.startTime.isAfter(b.startTime) ? a : b).memberId
            : null;

        final top = sortMembersByFrequency(
          members,
          counts,
          pinnedMemberId: currentMemberId,
          take: 4,
        );

        return _AnimatedQuickFrontRow(
          members: top,
          frontingIds: frontingIds,
        );
      },
    );
  }
}

/// Animates members sliding into new positions when the order changes.
class _AnimatedQuickFrontRow extends StatelessWidget {
  const _AnimatedQuickFrontRow({
    required this.members,
    required this.frontingIds,
  });

  final List<Member> members;
  final Set<String> frontingIds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / 4;
        return SizedBox(
          height: _kRingSize + 28, // ring + label
          child: Stack(
            children: [
              for (int i = 0; i < members.length; i++)
                AnimatedPositioned(
                  key: ValueKey(members[i].id),
                  duration: Anim.md,
                  curve: Anim.standard,
                  left: i * slotWidth + (slotWidth - _kRingSize) / 2,
                  top: 0,
                  child: SizedBox(
                    width: _kRingSize,
                    child: _QuickFrontButton(
                      member: members[i],
                      isFronting: frontingIds.contains(members[i].id),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

const _kAvatarSize = 62.0;
const _kRingSize = 76.0;
const _kRingWidth = 3.5;

/// Quick-front tile for a single member.
///
/// A tap toggles this member's session: starts a new per-member session when
/// not fronting, or ends the active session when fronting. Other members'
/// sessions are unaffected — co-fronting is emergent overlap, not a field.
///
/// Long-hold behavior from the old model ("second tap is a co-front") has been
/// removed; co-fronts are now initiated by opening the add-front sheet with
/// multiple members selected per spec §2.5.
class _QuickFrontButton extends ConsumerStatefulWidget {
  const _QuickFrontButton({
    required this.member,
    required this.isFronting,
  });

  final Member member;
  final bool isFronting;

  @override
  ConsumerState<_QuickFrontButton> createState() => _QuickFrontButtonState();
}

class _QuickFrontButtonState extends ConsumerState<_QuickFrontButton> {
  bool _isPressed = false;

  void _onTap() {
    unawaited(_toggleFronting());
  }

  Future<void> _toggleFronting() async {
    Haptics.light();
    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      if (widget.isFronting) {
        await notifier.endFronting([widget.member.id]);
      } else {
        // Single-member start — passes [memberId] so exactly one session row
        // is created. Use .sessions.single if you need the result.
        await notifier.startFronting([widget.member.id]);
      }
      if (mounted) Haptics.success();
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSwitchingFronter(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = widget.member;
    final accentColor = member.customColorEnabled && member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;

    return Semantics(
      button: true,
      enabled: true,
      label: context.l10n.frontingQuickFrontLabel(member.name),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _kRingSize,
                height: _kRingSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Static ring for active fronter
                    if (widget.isFronting)
                      Container(
                        width: _kRingSize,
                        height: _kRingSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(_kRingSize / 2),
                          ),
                          border: Border.all(
                            color: accentColor,
                            width: _kRingWidth,
                          ),
                        ),
                      ),
                    // Avatar
                    MemberAvatar(
                      avatarImageData: member.avatarImageData,
                      memberName: member.name,
                      emoji: member.emoji,
                      customColorEnabled: member.customColorEnabled,
                      customColorHex: member.customColorHex,
                      size: _kAvatarSize,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                member.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight:
                      widget.isFronting ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

