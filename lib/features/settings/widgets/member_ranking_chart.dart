import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Hero chart showing per-member fronting time as vertical bars sorted
/// descending by total time. Horizontally scrollable so 5+ active members
/// peek beyond the right edge as a scroll affordance.
///
/// Slot width is computed from the widest member name + ambient text scale
/// so labels never wrap or clip; the card height grows with text scale for
/// the same reason.
///
/// Tap any bar to toggle every bar's top label between percentage and total
/// time — chart-wide so the readout stays cohesive rather than mixed.
class MemberRankingChart extends ConsumerStatefulWidget {
  const MemberRankingChart({super.key, required this.memberStats});

  final List<MemberAnalytics> memberStats;

  static const double _barHeight = 120;
  static const double _avatarSize = 24;
  // Vertical gaps inside each slot.
  static const double _gapPctToBar = 4;
  static const double _gapBarToAvatar = 8;
  static const double _gapAvatarToName = 4;
  // Slot bounds: floor keeps the avatar (24px) plus minimal breathing room
  // visible; ceiling stops a single very long name from inflating every
  // column. Anything beyond the ceiling ellipsises rather than bloats.
  static const double _minSlotWidth = 40;
  static const double _maxSlotWidth = 88;
  // Horizontal padding inside each slot, applied to both sides of the
  // measured name width. Kept tight so columns sit close together.
  static const double _slotHorizontalPadding = 3;

  @override
  ConsumerState<MemberRankingChart> createState() =>
      _MemberRankingChartState();
}

class _MemberRankingChartState extends ConsumerState<MemberRankingChart> {
  // Time is the more concrete number — "10h" tells a reader more than
  // "60%" without a denominator in mind. Tap toggles to %.
  bool _showingTime = true;

  void _toggleLabel() => setState(() => _showingTime = !_showingTime);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memberStats = widget.memberStats;
    if (memberStats.isEmpty) return const SizedBox.shrink();

    final peakMinutes = memberStats.first.totalTime.inMinutes;

    // Batch-fetch members once for the whole chart instead of per-bar
    // subscriptions — fewer rebuilds, single network/db pass, and the same
    // map drives both name measurement and bar rendering.
    final ids = memberStats.map((s) => s.memberId).toList();
    final memberMapAsync =
        ref.watch(membersByIdsProvider(memberIdsKey(ids)));
    final memberMap =
        memberMapAsync.value ?? const <String, Member>{};

    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = theme.textTheme.labelSmall;

    // Slot width: measure each visible name with the actual label style and
    // ambient text scaler, take the widest, then add side padding. Names
    // that haven't loaded yet contribute "..." which is narrow — the chart
    // will rebuild and resize once the batch provider hydrates.
    double widestName = 0;
    for (final stat in memberStats) {
      final name = _displayName(memberMap[stat.memberId]);
      final width = _measureTextWidth(name, labelStyle, textScaler);
      if (width > widestName) widestName = width;
    }
    final slotWidth = (widestName +
            MemberRankingChart._slotHorizontalPadding * 2)
        .clamp(MemberRankingChart._minSlotWidth,
            MemberRankingChart._maxSlotWidth);

    // Compute the chart row height precisely from the scaled text + fixed
    // pieces, so the ListView is exactly as tall as one bar slot. No
    // outer cardHeight, no Expanded → no dead space above the bars when
    // bottom-anchored.
    final labelFontSize = labelStyle?.fontSize ?? 11;
    final labelLineMult = labelStyle?.height ?? 1.4;
    final scaledLabelHeight = textScaler.scale(labelFontSize) * labelLineMult;
    // 4px slack absorbs leading/baseline rounding so the column never
    // overflows the ListView; rendered text varies slightly by font.
    const overflowSlack = 4.0;
    final rowHeight = scaledLabelHeight // % label
        + MemberRankingChart._gapPctToBar
        + MemberRankingChart._barHeight
        + MemberRankingChart._gapBarToAvatar
        + MemberRankingChart._avatarSize
        + MemberRankingChart._gapAvatarToName
        + scaledLabelHeight // member name
        + overflowSlack;

    return PrismSurface(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              context.l10n.statisticsFrontingTimeByMember,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                // Drop built-in line-height padding so the title sits as
                // close to the bars as the SizedBox below allows.
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: rowHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: memberStats.length,
              // No right padding — last bar sits flush so the next bar
              // peeks past the viewport edge as a "scrollable" cue.
              padding: EdgeInsets.zero,
              itemBuilder: (context, idx) {
                final stat = memberStats[idx];
                return _MemberBar(
                  stat: stat,
                  member: memberMap[stat.memberId],
                  rowIndex: idx,
                  peakMinutes: peakMinutes,
                  barHeight: MemberRankingChart._barHeight,
                  slotWidth: slotWidth,
                  showingTime: _showingTime,
                  onTap: _toggleLabel,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _displayName(Member? m) {
  if (m == null) return '...';
  return m.displayName ?? m.name;
}

double _measureTextWidth(
  String text,
  TextStyle? style,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: scaler,
  )..layout();
  return painter.width;
}

class _MemberBar extends StatelessWidget {
  const _MemberBar({
    required this.stat,
    required this.member,
    required this.rowIndex,
    required this.peakMinutes,
    required this.barHeight,
    required this.slotWidth,
    required this.showingTime,
    required this.onTap,
  });

  final MemberAnalytics stat;
  final Member? member;
  final int rowIndex;
  final int peakMinutes;
  final double barHeight;
  final double slotWidth;
  final bool showingTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final name = _displayName(member);

    final color = (member?.customColorEnabled ?? false) &&
            member?.customColorHex != null
        ? AppColors.fromHex(member!.customColorHex!)
        : AppColors.generatedColor(
            rowIndex, theme.colorScheme.primary, brightness);

    final fraction =
        peakMinutes > 0 ? stat.totalTime.inMinutes / peakMinutes : 0.0;
    final filledHeight = (barHeight * fraction).clamp(2.0, barHeight);
    // Bar width scales with the slot so a wider column doesn't leave the
    // bar looking lonely in the middle. Floor + ceiling keep the geometry
    // recognisable across the slot's [48, 110] range.
    final barWidth = (slotWidth * 0.5).clamp(20.0, 48.0);

    final percentLabel = '${stat.percentageOfTotal.toStringAsFixed(0)}%';
    final timeLabel = stat.totalTime.toRoundedString();
    final activeLabel = showingTime ? timeLabel : percentLabel;

    return Semantics(
      label: '$name: $timeLabel ($percentLabel)',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        // Opaque so taps anywhere in the slot — including transparent gaps
        // around the bar — toggle the label.
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          key: ValueKey('member_ranking_slot_${stat.memberId}'),
          width: slotWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Text(
                  activeLabel,
                  // Key on the label content so AnimatedSwitcher detects the
                  // swap and runs the transition.
                  key: ValueKey('rank_label_${stat.memberId}_$activeLabel'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const SizedBox(height: MemberRankingChart._gapPctToBar),
              // Track + filled bar. Track shows the full ceiling so short
              // bars still read as "less than" rather than floating in space.
              SizedBox(
                height: barHeight,
                width: barWidth,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(2)),
                      ),
                    ),
                    Container(
                      height: filledHeight,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(2)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MemberRankingChart._gapBarToAvatar),
              MemberAvatar(
                avatarImageData: member?.avatarImageData,
                memberName: member?.name,
                emoji: member?.emoji ?? '',
                customColorEnabled: member?.customColorEnabled ?? false,
                customColorHex: member?.customColorHex,
                size: MemberRankingChart._avatarSize,
              ),
              const SizedBox(height: MemberRankingChart._gapAvatarToName),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  name,
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
