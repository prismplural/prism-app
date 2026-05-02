import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/utils/member_frequency_sort.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
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
      loading: () => const SizedBox(height: 100, child: PrismLoadingState()),
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
            ? activeSessions
                  .reduce((a, b) => a.startTime.isAfter(b.startTime) ? a : b)
                  .memberId
            : null;

        final top = sortMembersByFrequency(
          members,
          counts,
          pinnedMemberId: currentMemberId,
          take: 4,
        );

        return _AnimatedQuickFrontRow(members: top, frontingIds: frontingIds);
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
const _kHoldDuration = Duration(milliseconds: 800);

/// Quick-front tile for a single member.
///
/// A completed hold toggles this member's session: starts a new per-member
/// session when not fronting, or ends the active session when fronting.
/// Other members' sessions are affected only when the user's quick-front
/// preference is `replace`.
class _QuickFrontButton extends ConsumerStatefulWidget {
  const _QuickFrontButton({required this.member, required this.isFronting});

  final Member member;
  final bool isFronting;

  @override
  ConsumerState<_QuickFrontButton> createState() => _QuickFrontButtonState();
}

class _QuickFrontButtonState extends ConsumerState<_QuickFrontButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isPressed = false;
  bool _pendingToggle = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kHoldDuration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onHoldComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPressStart() {
    setState(() => _isPressed = true);
    Haptics.light();
    _pendingToggle = false;
    _controller.forward(from: 0);
  }

  void _onPressEnd(FrontStartBehavior pref) {
    setState(() => _isPressed = false);
    if (_pendingToggle) {
      _pendingToggle = false;
      unawaited(_toggleFronting(pref));
    }
    if (_controller.value != 0) {
      _controller.reset();
    }
  }

  void _onHoldComplete() {
    Haptics.success();
    _pendingToggle = true;
  }

  Future<void> _toggleFronting(FrontStartBehavior pref) async {
    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      if (widget.isFronting) {
        // An already-fronting member always ends, regardless of the
        // `quick_front_default_behavior` preference. The preference only
        // affects what happens when starting a non-fronting member.
        await notifier.endFronting([widget.member.id]);
      } else {
        switch (pref) {
          case FrontStartBehavior.additive:
            // Single-member start — exactly one session row is created.
            await notifier.startFronting([widget.member.id]);
          case FrontStartBehavior.replace:
            // Atomic: ends all current normal fronts AND starts this member
            // in one transaction with a single captured `now`.
            await notifier.replaceFronting([widget.member.id]);
        }
      }
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
    final accentColor =
        member.customColorEnabled && member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;

    // Watch the persisted default for the non-fronting hold path. Watching
    // (rather than reading on tap) ensures the StreamProvider is subscribed
    // before the user presses — otherwise the first hold may fire while the
    // stream is still in `AsyncLoading`, silently falling back to additive
    // even when the synced setting says replace.
    final pref =
        ref
            .watch(systemSettingsProvider)
            .whenOrNull(data: (s) => s.quickFrontDefaultBehavior) ??
        FrontStartBehavior.additive;

    return Semantics(
      button: true,
      enabled: true,
      label: context.l10n.frontingQuickFrontLabel(member.name),
      onLongPressHint: context.l10n.frontingQuickFrontHoldHint,
      child: GestureDetector(
        onLongPressStart: (_) => _onPressStart(),
        onLongPressEnd: (_) => _onPressEnd(pref),
        onLongPressCancel: () => _onPressEnd(pref),
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
                    if (!widget.isFronting)
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          if (_controller.value == 0) {
                            return const SizedBox.shrink();
                          }
                          return CustomPaint(
                            size: const Size(_kRingSize, _kRingSize),
                            painter: _ProgressRingPainter(
                              progress: _controller.value,
                              color: accentColor,
                              strokeWidth: _kRingWidth,
                              cornerRadius: PrismShapes.of(
                                context,
                              ).radius(_kRingSize / 2),
                            ),
                          );
                        },
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
                  fontWeight: widget.isFronting
                      ? FontWeight.bold
                      : FontWeight.normal,
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

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.cornerRadius = 0,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;

    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final innerRadius = (cornerRadius - inset).clamp(0.0, double.infinity);
    final fullPath = innerRadius > 0
        ? (Path()..addRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(innerRadius)),
          ))
        : (Path()..addRect(rect));
    final metrics = fullPath.computeMetrics().first;
    final totalLength = metrics.length;
    final startOffset = ((size.width - strokeWidth) / 2 - innerRadius).clamp(
      0.0,
      double.infinity,
    );
    final sweepLength = totalLength * progress;
    final endOffset = startOffset + sweepLength;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;

    if (endOffset <= totalLength) {
      canvas.drawPath(metrics.extractPath(startOffset, endOffset), paint);
    } else {
      canvas.drawPath(metrics.extractPath(startOffset, totalLength), paint);
      canvas.drawPath(metrics.extractPath(0, endOffset - totalLength), paint);
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      cornerRadius != oldDelegate.cornerRadius;
}
