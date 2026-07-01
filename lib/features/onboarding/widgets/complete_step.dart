import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

class CompleteStep extends ConsumerWidget {
  const CompleteStep({super.key});

  static const _maxDisplayMembers = 18;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final members = ref
        .watch(userVisibleMemberListProvider)
        .value
        ?.take(_maxDisplayMembers)
        .toList(growable: false);
    final systemName = onboarding.systemName.trim().isNotEmpty
        ? onboarding.systemName.trim()
        : context.l10n.settingsFallbackSystemName;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? AppColors.warmWhite : AppColors.warmBlack;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.85);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final memberCount = members?.length ?? 0;
        final densityScale = memberCount > 12
            ? 0.84
            : memberCount > 8
            ? 0.92
            : 1.0;
        final baseAvatarSize = math.max(
          30.0,
          math.min(48.0, shortestSide * 0.115) * densityScale,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              if (members != null)
                ExcludeSemantics(
                  child: _MemberCloud(
                    members: members,
                    baseAvatarSize: baseAvatarSize,
                  ),
                ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.onboardingCompleteWelcomeTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: textColor,
                          fontSize: 34,
                          height: 1.12,
                          letterSpacing: 0,
                          shadows: [
                            Shadow(
                              color: shadowColor,
                              blurRadius: 18,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          systemName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: textColor.withValues(alpha: 0.86),
                            fontSize: 26,
                            height: 1.12,
                            letterSpacing: 0,
                            shadows: [
                              Shadow(
                                color: shadowColor,
                                blurRadius: 14,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _MemberCloud extends StatelessWidget {
  const _MemberCloud({required this.members, required this.baseAvatarSize});

  final List<Member> members;
  final double baseAvatarSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final placements = _resolvePlacements(canvasSize);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < placements.length; i++)
              _CloudAvatar(member: members[i], placement: placements[i]),
          ],
        );
      },
    );
  }

  List<_AvatarPlacement> _resolvePlacements(Size canvasSize) {
    if (members.isEmpty) return const [];

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final textZone = Rect.fromCenter(
      center: center,
      width: math.min(canvasSize.width * 0.96, 420),
      height: math.min(230, math.max(170, canvasSize.height * 0.27)),
    );

    final topCount = (members.length + 1) ~/ 2;
    final bottomCount = members.length - topCount;
    final maxRowCount = math.max(topCount, bottomCount);
    final gap = maxRowCount > 7 ? 8.0 : 12.0;
    final rowSize = maxRowCount <= 1
        ? baseAvatarSize
        : ((canvasSize.width - gap * (maxRowCount - 1)) / maxRowCount).clamp(
            28.0,
            baseAvatarSize,
          );
    final rowGap = math.max(28.0, rowSize * 0.72);
    final topY = (textZone.top - rowGap - rowSize / 2)
        .clamp(rowSize / 2, canvasSize.height - rowSize / 2)
        .toDouble();
    final bottomY = (textZone.bottom + rowGap + rowSize / 2)
        .clamp(rowSize / 2, canvasSize.height - rowSize / 2)
        .toDouble();

    return [
      ..._rowPlacements(
        startIndex: 0,
        count: topCount,
        y: topY,
        size: rowSize,
        gap: gap,
        centerX: center.dx,
      ),
      ..._rowPlacements(
        startIndex: topCount,
        count: bottomCount,
        y: bottomY,
        size: rowSize,
        gap: gap,
        centerX: center.dx,
      ),
    ];
  }

  double _opacityFor(int index) {
    const opacities = [0.84, 0.72, 0.78, 0.68, 0.80, 0.64, 0.74, 0.70, 0.66];
    return opacities[index % opacities.length];
  }

  List<_AvatarPlacement> _rowPlacements({
    required int startIndex,
    required int count,
    required double y,
    required double size,
    required double gap,
    required double centerX,
  }) {
    if (count == 0) return const [];

    final rowWidth = count * size + (count - 1) * gap;
    final firstX = centerX - rowWidth / 2 + size / 2;
    return [
      for (var i = 0; i < count; i++)
        _AvatarPlacement(
          center: Offset(firstX + i * (size + gap), y),
          size: size,
          opacity: _opacityFor(startIndex + i),
        ),
    ];
  }
}

class _CloudAvatar extends StatelessWidget {
  const _CloudAvatar({required this.member, required this.placement});

  final Member member;
  final _AvatarPlacement placement;

  @override
  Widget build(BuildContext context) {
    final size = placement.size;
    final left = placement.center.dx - size / 2;
    final top = placement.center.dy - size / 2;

    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: MemberAvatar(
        memberId: member.id,
        avatarImageData: member.avatarImageData,
        memberName: member.name,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: size,
        opacity: placement.opacity,
        showBorder: true,
        deferAvatarLookup: true,
      ),
    );
  }
}

class _AvatarPlacement {
  const _AvatarPlacement({
    required this.center,
    required this.size,
    required this.opacity,
  });

  final Offset center;
  final double size;
  final double opacity;

  double get radius => size / 2;

  _AvatarPlacement copyWith({Offset? center}) {
    return _AvatarPlacement(
      center: center ?? this.center,
      size: size,
      opacity: opacity,
    );
  }
}
