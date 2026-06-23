import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/quick_front_hint_provider.dart';
import 'package:prism_plurality/features/fronting/utils/current_fronters_order.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

const _quickFrontRecentSessionLimit = 50;
const _quickFrontSuggestionLimit = 12;
const _frontingPlaceholderDelay = Duration(milliseconds: 800);

final quickFrontCandidateMembersProvider =
    StreamProvider.autoDispose<List<Member>>((ref) {
      final repo = ref.watch(memberRepositoryProvider);
      if (repo is DriftMemberRepository) {
        return _markQuickFrontCandidateStream(
          repo.watchQuickFrontMembersForList(
            recentLimit: _quickFrontRecentSessionLimit,
            suggestionLimit: _quickFrontSuggestionLimit,
            excludedSuggestionMemberId: unknownSentinelMemberId,
          ),
        );
      }

      return _markQuickFrontCandidateStream(repo.watchActiveMembers());
    });

Stream<List<Member>> _markQuickFrontCandidateStream(
  Stream<List<Member>> stream,
) {
  return stream.map((members) {
    BootTimings.markOnce(
      'quickFront candidates first emit',
      'count=${members.length}',
    );
    return members;
  });
}

/// Horizontal strip of member tiles for quick-switching the front.
///
/// Composition: `[current fronters] + [frequent non-fronters]`. Current
/// fronters first (startTime-DESC, [Member.displayOrder] breaking ties so
/// simultaneous co-fronts don't read as database-rowid order).
///
/// Packs into [_slotCountForWidth] tiles when current fronters leave at
/// least [_frequentPadWhenNotScrolling] slots free; otherwise scrolls
/// horizontally so every fronter still has a quick-remove tile.
class QuickFrontSection extends ConsumerWidget {
  const QuickFrontSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(quickFrontCandidateMembersProvider);
    final sessionsAsync = ref.watch(activeSessionsProvider);
    final quickFrontBehavior = ref.watch(quickFrontDefaultBehaviorProvider);

    return membersAsync.when(
      skipLoadingOnReload: true,
      loading: () => const _QuickFrontLoadingPlaceholder(),
      error: (_, _) => Text(context.l10n.error),
      data: (members) {
        final activeSessions = sessionsAsync.value ?? const <FrontingSession>[];
        if (sessionsAsync.hasValue) {
          BootTimings.markOnce(
            'quickFront active sessions first emit',
            'count=${activeSessions.length}',
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final slotCount = _slotCountForWidth(constraints.maxWidth);
            final currentFronters = orderCurrentFronters(
              activeSessions,
              members,
            );
            final currentFronterIds = <String>{
              for (final m in currentFronters) m.id,
            };

            // Suggest only real members. Unknown is a placeholder you'd
            // never deliberately switch *to*, and it can accumulate high
            // frequency counts in imported data that would otherwise
            // dominate suggestions. It still appears in the current-
            // fronters group if a session is active, so there's a
            // quick-remove tile for it.
            final nonFronters = [
              for (final m in members)
                if (!currentFronterIds.contains(m.id) &&
                    m.id != unknownSentinelMemberId)
                  m,
            ];

            final List<Member> tiles;
            final bool scrolls;
            if (currentFronters.length <=
                slotCount - _frequentPadWhenNotScrolling) {
              final frequentSlots = slotCount - currentFronters.length;
              final frequent = nonFronters.take(frequentSlots);
              tiles = [...currentFronters, ...frequent];
              scrolls = false;
            } else {
              // Show every current fronter so co-fronts always have a
              // quick-remove tile.
              final frequent = nonFronters.take(_frequentTilesWhenScrolling);
              tiles = [...currentFronters, ...frequent];
              scrolls = true;
            }
            BootTimings.markOnce(
              'quickFront row first ready',
              'tiles=${tiles.length} current=${currentFronters.length} '
                  'scrolls=$scrolls',
            );

            return _AnimatedQuickFrontRow(
              members: tiles,
              frontingIds: currentFronterIds,
              slotCount: slotCount,
              scrolls: scrolls,
              maxWidth: constraints.maxWidth,
              quickFrontBehavior: quickFrontBehavior,
            );
          },
        );
      },
    );
  }
}

class _QuickFrontLoadingPlaceholder extends StatefulWidget {
  const _QuickFrontLoadingPlaceholder();

  @override
  State<_QuickFrontLoadingPlaceholder> createState() =>
      _QuickFrontLoadingPlaceholderState();
}

class _QuickFrontLoadingPlaceholderState
    extends State<_QuickFrontLoadingPlaceholder> {
  Timer? _timer;
  bool _showSkeleton = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_frontingPlaceholderDelay, () {
      if (mounted) setState(() => _showSkeleton = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotCount = _slotCountForWidth(constraints.maxWidth);
        final slotWidth = constraints.maxWidth / slotCount;
        final ringSize = slotWidth < quickFrontRingSize
            ? slotWidth
            : quickFrontRingSize;
        final labelHeight = _quickFrontLabelHeight(context);
        final rowHeight = ringSize + _kQuickFrontLabelGap + labelHeight;

        if (!_showSkeleton) return SizedBox(height: rowHeight);

        final theme = Theme.of(context);
        final color = theme.colorScheme.onSurface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.11 : 0.07,
        );
        final radius = PrismShapes.of(context).radius(999);

        return ExcludeSemantics(
          child: SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                for (var i = 0; i < slotCount; i++)
                  SizedBox(
                    width: slotWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: ringSize,
                          height: ringSize,
                          decoration: BoxDecoration(
                            shape: PrismShapes.of(context).avatarShape(),
                            borderRadius: PrismShapes.of(
                              context,
                            ).avatarBorderRadius(),
                            color: color,
                          ),
                        ),
                        const SizedBox(height: _kQuickFrontLabelGap + 2),
                        Container(
                          width: slotWidth * 0.58,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(radius),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Packed mode uses [AnimatedPositioned] for a smooth slide on reorder.
/// Scroll mode uses a plain `Row` wrapped in a [ShaderMask] that fades
/// whichever edge has content past it, plus a decorative right chevron
/// that's visible only at the start (a first-impression hint that
/// scroll exists). Animating positions inside a scroll view isn't worth
/// the complexity.
class _AnimatedQuickFrontRow extends StatefulWidget {
  const _AnimatedQuickFrontRow({
    required this.members,
    required this.frontingIds,
    required this.slotCount,
    required this.scrolls,
    required this.maxWidth,
    required this.quickFrontBehavior,
  });

  final List<Member> members;
  final Set<String> frontingIds;
  final int slotCount;
  final bool scrolls;
  final double maxWidth;
  final FrontStartBehavior quickFrontBehavior;

  @override
  State<_AnimatedQuickFrontRow> createState() => _AnimatedQuickFrontRowState();
}

class _AnimatedQuickFrontRowState extends State<_AnimatedQuickFrontRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // ScrollController doesn't notify its listeners on initial attach, so
    // the AnimatedBuilder below would render with maxScrollExtent==0 on the
    // first frame — no fade visible until the user scrolls. Force one
    // post-frame rebuild so the right-edge fade appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Single-position guard. `hasClients` only checks `length >= 1`, so
  /// during reconciliation when a new scroll view briefly co-exists with
  /// the old one the `.position` getter throws. Returns null instead so
  /// the strength helpers can fall through to 0.
  ScrollPosition? _attachedPosition() {
    if (_scrollController.positions.length != 1) return null;
    final pos = _scrollController.positions.first;
    if (!pos.hasContentDimensions) return null;
    return pos;
  }

  /// 0 when the left edge is at the start, 1 once the user has scrolled
  /// past [_kEdgeFadeWidth]. Linear ramp so the fade-in is continuous
  /// rather than popping on at the first pixel of scroll.
  double _leftFadeStrength() {
    final pos = _attachedPosition();
    if (pos == null) return 0;
    if (pos.pixels <= 0) return 0;
    return (pos.pixels / _kEdgeFadeWidth).clamp(0.0, 1.0);
  }

  double _rightFadeStrength() {
    final pos = _attachedPosition();
    if (pos == null) return 0;
    if (pos.maxScrollExtent <= 0) return 0;
    final remaining = pos.maxScrollExtent - pos.pixels;
    if (remaining <= 0) return 0;
    return (remaining / _kEdgeFadeWidth).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final slotWidth = widget.maxWidth / widget.slotCount;
    final ringSize = slotWidth < quickFrontRingSize
        ? slotWidth
        : quickFrontRingSize;
    final labelHeight = _quickFrontLabelHeight(context);
    final rowHeight = ringSize + _kQuickFrontLabelGap + labelHeight;

    if (widget.scrolls) {
      final scrollView = SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final member in widget.members)
              SizedBox(
                key: ValueKey(member.id),
                width: slotWidth,
                height: rowHeight,
                child: _QuickFrontButton(
                  member: member,
                  isFronting: widget.frontingIds.contains(member.id),
                  ringSize: ringSize,
                  quickFrontBehavior: widget.quickFrontBehavior,
                ),
              ),
          ],
        ),
      );

      final maskedScroll = AnimatedBuilder(
        animation: _scrollController,
        builder: (context, child) {
          final leftAlpha = _leftFadeStrength();
          final rightAlpha = _rightFadeStrength();
          // Both edges flush: nothing to fade. Skipping ShaderMask avoids
          // the offscreen layer cost for cases where content briefly fits.
          if (leftAlpha == 0 && rightAlpha == 0) return child!;
          return ShaderMask(
            shaderCallback: (bounds) {
              // Cap fade at half the bar so narrow viewports still leave an
              // opaque middle band.
              final fadeFraction = (_kEdgeFadeWidth / bounds.width).clamp(
                0.0,
                0.5,
              );
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 1.0 - leftAlpha),
                  Colors.black,
                  Colors.black,
                  Colors.black.withValues(alpha: 1.0 - rightAlpha),
                ],
                stops: [0.0, fadeFraction, 1.0 - fadeFraction, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: child,
          );
        },
        child: scrollView,
      );

      // Decorative chevron — never tappable, just a first-impression hint
      // that there's more to scroll to. Fades out as soon as the user
      // starts scrolling (its job is done once they know), tied to the
      // left-edge scroll strength so the fade tracks the same pixel
      // distance as the gradient ramps. Kept in the tree at opacity 0
      // so its element doesn't churn during scroll.
      final chevron = IgnorePointer(
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, child) {
            final opacity =
                ((1.0 - _leftFadeStrength()) * _kScrollChevronMaxOpacity).clamp(
                  0.0,
                  1.0,
                );
            return Icon(
              AppIcons.chevronRight,
              size: _kScrollChevronSize,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: opacity),
            );
          },
        ),
      );

      return SizedBox(
        height: rowHeight,
        child: Stack(
          children: [
            Positioned.fill(child: maskedScroll),
            Positioned(
              right: 0,
              top: (ringSize - _kScrollChevronSize) / 2,
              child: chevron,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: [
          for (int i = 0; i < widget.members.length; i++)
            AnimatedPositioned(
              key: ValueKey(widget.members[i].id),
              duration: Anim.md,
              curve: Anim.standard,
              left: i * slotWidth,
              top: 0,
              child: SizedBox(
                width: slotWidth,
                height: rowHeight,
                child: _QuickFrontButton(
                  member: widget.members[i],
                  isFronting: widget.frontingIds.contains(widget.members[i].id),
                  ringSize: ringSize,
                  quickFrontBehavior: widget.quickFrontBehavior,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _kAvatarSize = 62.0;
const quickFrontRingSize = 76.0;
const _kAvatarRingInset = quickFrontRingSize - _kAvatarSize;
const _kQuickFrontLabelGap = 6.0;
const _kQuickFrontLabelMaxLines = 2;
const _kRingWidth = 3.5;
const _kHoldDuration = Duration(milliseconds: 800);

/// Target tile width. At 88px a 360-wide phone gets 4 slots, a 600-wide
/// foldable gets 6.
const _kTargetTileWidth = 88.0;

/// Mobile baseline.
const _kMinSlotCount = 4;

/// Hard cap so ultra-wide windows don't sprout a wall of tiles.
const _kMaxSlotCount = 10;

/// Minimum frequent-pick slots in packed mode. Scroll mode kicks in once
/// `currentFronters > slotCount - _frequentPadWhenNotScrolling`.
const _frequentPadWhenNotScrolling = 2;

/// Frequent tiles appended after fronters in scroll mode — fixed, not
/// scaled to slot count.
const _frequentTilesWhenScrolling = 4;

/// Width of the scroll-edge gradient in scroll mode. The fade ramps to
/// full opacity over this many pixels of scroll movement.
const _kEdgeFadeWidth = 36.0;

/// Diameter of the right-edge chevron decoration shown in scroll mode.
const _kScrollChevronSize = 20.0;

/// Max opacity of the right-edge chevron when fully on. Scaled down by
/// the right-edge fade strength so the chevron crossfades with the
/// gradient — it's only a discoverability hint, not a fixed UI element.
const _kScrollChevronMaxOpacity = 0.55;

int _slotCountForWidth(double width) {
  if (width <= 0) return _kMinSlotCount;
  final raw = (width / _kTargetTileWidth).floor();
  if (raw < _kMinSlotCount) return _kMinSlotCount;
  if (raw > _kMaxSlotCount) return _kMaxSlotCount;
  return raw;
}

double _quickFrontLabelHeight(BuildContext context) {
  final theme = Theme.of(context);
  final baseStyle =
      theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
  final labelStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
  final fontSize = labelStyle.fontSize ?? 14.0;
  final lineHeight = labelStyle.height ?? 1.2;
  final scaledFontSize = MediaQuery.textScalerOf(context).scale(fontSize);
  return scaledFontSize * lineHeight * _kQuickFrontLabelMaxLines;
}

/// Quick-front tile for a single member.
///
/// A completed hold toggles this member's session: starts a new per-member
/// session when not fronting, or ends the active session when fronting.
/// Other members' sessions are affected only when the user's quick-front
/// preference is `replace`.
class _QuickFrontButton extends ConsumerStatefulWidget {
  const _QuickFrontButton({
    required this.member,
    required this.isFronting,
    required this.ringSize,
    required this.quickFrontBehavior,
  });

  final Member member;
  final bool isFronting;
  final double ringSize;
  final FrontStartBehavior quickFrontBehavior;

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
        await ref
            .read(quickFrontHoldInstructionVisibleProvider.notifier)
            .markSeen();
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
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final memberName = member.effectiveName(preferDisplayName: prefer);
    final ringSize = widget.ringSize;
    final avatarSize = (ringSize - _kAvatarRingInset).clamp(0.0, ringSize);
    final accentColor =
        member.customColorEnabled && member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;

    return Semantics(
      button: true,
      enabled: true,
      label: context.l10n.frontingQuickFrontLabel(memberName),
      onLongPressHint: context.l10n.frontingQuickFrontHoldHint,
      child: GestureDetector(
        onLongPressStart: (_) => _onPressStart(),
        onLongPressEnd: (_) => _onPressEnd(widget.quickFrontBehavior),
        onLongPressCancel: () => _onPressEnd(widget.quickFrontBehavior),
        child: AnimatedScale(
          scale: _isPressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Static ring for active fronter
                    if (widget.isFronting)
                      Container(
                        width: ringSize,
                        height: ringSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(ringSize / 2),
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
                            size: Size(ringSize, ringSize),
                            painter: _ProgressRingPainter(
                              progress: _controller.value,
                              color: accentColor,
                              strokeWidth: _kRingWidth,
                              cornerRadius: PrismShapes.of(
                                context,
                              ).radius(ringSize / 2),
                            ),
                          );
                        },
                      ),
                    // Avatar
                    MemberAvatar(
                      avatarImageData: member.avatarImageData,
                      memberId: member.id,
                      deferAvatarLookup: true,
                      memberName: memberName,
                      emoji: member.emoji,
                      customColorEnabled: member.customColorEnabled,
                      customColorHex: member.customColorHex,
                      size: avatarSize,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _kQuickFrontLabelGap),
              Text(
                memberName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: widget.isFronting
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                maxLines: _kQuickFrontLabelMaxLines,
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
