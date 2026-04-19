import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// Glassmorphism autocomplete overlay for @mentions.
///
/// Shows conversation participants filtered by the text after `@`.
/// Mobile: tap to select. Desktop: arrow keys + Enter/Tab to confirm.
class MentionOverlay extends StatefulWidget {
  const MentionOverlay({
    super.key,
    required this.members,
    required this.filter,
    required this.onSelect,
    required this.layerLink,
  });

  /// Members to show (conversation participants).
  final List<Member> members;

  /// Current filter text (partial name after `@`).
  final String filter;

  /// Called when a member is selected.
  final ValueChanged<Member> onSelect;

  /// Layer link to position relative to the text field.
  final LayerLink layerLink;

  @override
  State<MentionOverlay> createState() => MentionOverlayState();
}

class MentionOverlayState extends State<MentionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  int _selectedIndex = 0;

  List<Member> get _filtered {
    if (widget.filter.isEmpty) return widget.members;
    final lower = widget.filter.toLowerCase();
    return widget.members
        .where((m) => m.name.toLowerCase().contains(lower))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MentionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filter != oldWidget.filter) {
      // Reset selection when filter changes.
      _selectedIndex = 0;
    }
  }

  /// Handle keyboard navigation. Returns true if the event was consumed.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final filtered = _filtered;
    if (filtered.isEmpty) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % filtered.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + filtered.length) % filtered.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_selectedIndex < filtered.length) {
        widget.onSelect(filtered[_selectedIndex]);
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return true; // Caller handles dismissal.
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (filtered.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CompositedTransformFollower(
      link: widget.layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -8),
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.bottomLeft,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(16)),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: PrismTokens.glassBlurStrong,
                  sigmaY: PrismTokens.glassBlurStrong,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.warmBlack.withValues(alpha: 0.65)
                        : AppColors.warmWhite.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(16)),
                    border: Border.all(
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.12)
                          : AppColors.warmBlack.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.warmBlack.withValues(alpha: isDark ? 0.4 : 0.12),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      final isHighlighted = index == _selectedIndex;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onSelect(member),
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: isHighlighted
                              ? theme.colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              MemberAvatar(
                                avatarImageData: member.avatarImageData,
                                memberName: member.name,
                                emoji: member.emoji,
                                customColorEnabled: member.customColorEnabled,
                                customColorHex: member.customColorHex,
                                size: 32,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isHighlighted
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
