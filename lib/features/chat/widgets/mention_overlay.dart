import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart'
    as mention_utils;
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

final _broadcastMentionDisplayAliases = mention_utils.broadcastMentionAliases
    .map((alias) => '@$alias')
    .toList(growable: false);

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
    required this.onBroadcastSelect,
    required this.availableWidth,
  });

  /// Members to show (conversation participants).
  final List<Member> members;

  /// Current filter text (partial name after `@`).
  final String filter;

  /// Called when a member is selected.
  final ValueChanged<Member> onSelect;

  /// Called when a broadcast mention alias is selected.
  final ValueChanged<String> onBroadcastSelect;

  /// Width available from the anchored composer field.
  final double availableWidth;

  static bool hasBroadcastAliasMatches(String filter) {
    return _broadcastAliasesForFilter(filter).isNotEmpty;
  }

  @override
  State<MentionOverlay> createState() => MentionOverlayState();
}

class _MentionOverlayEntry {
  const _MentionOverlayEntry.member(this.member) : alias = null;

  const _MentionOverlayEntry.broadcast(this.alias) : member = null;

  final Member? member;
  final String? alias;

  bool get isBroadcast => alias != null;
}

List<String> _broadcastAliasesForFilter(String filter) {
  final lower = filter.toLowerCase();
  if (lower.isEmpty) return _broadcastMentionDisplayAliases;
  return _broadcastMentionDisplayAliases
      .where((alias) => alias.substring(1).startsWith(lower))
      .toList(growable: false);
}

class MentionOverlayState extends State<MentionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  int _selectedIndex = 0;

  List<_MentionOverlayEntry> get _filtered {
    final broadcastEntries = _broadcastAliasesForFilter(
      widget.filter,
    ).map(_MentionOverlayEntry.broadcast);
    final lower = widget.filter.toLowerCase();
    final memberEntries =
        (widget.filter.isEmpty
                ? widget.members
                : widget.members.where(
                    (m) => m.name.toLowerCase().contains(lower),
                  ))
            .map(_MentionOverlayEntry.member);
    return [...memberEntries, ...broadcastEntries];
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
        _selectedIndex =
            (_selectedIndex - 1 + filtered.length) % filtered.length;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_selectedIndex < filtered.length) {
        _select(filtered[_selectedIndex]);
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return true; // Caller handles dismissal.
    }
    return false;
  }

  void _select(_MentionOverlayEntry entry) {
    if (entry.isBroadcast) {
      widget.onBroadcastSelect(entry.alias!);
      return;
    }
    widget.onSelect(entry.member!);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (filtered.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final popupWidth = math.min(widget.availableWidth, 320.0);
    final minWidth = math.min(popupWidth, 220.0);

    return Align(
      alignment: Alignment.bottomLeft,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.bottomLeft,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              key: const Key('mentionOverlaySurface'),
              width: popupWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(16),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: PrismTokens.glassBlurStrong,
                    sigmaY: PrismTokens.glassBlurStrong,
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: minWidth,
                      maxHeight: 240,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(
                        alpha: isDark ? 0.92 : 0.96,
                      ),
                      borderRadius: BorderRadius.circular(
                        PrismShapes.of(context).radius(16),
                      ),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(
                            alpha: 0.18,
                          ),
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
                        final entry = filtered[index];
                        final isHighlighted = index == _selectedIndex;
                        if (entry.isBroadcast) {
                          return _BroadcastMentionRow(
                            alias: entry.alias!,
                            isHighlighted: isHighlighted,
                            onTap: () => _select(entry),
                          );
                        }
                        final member = entry.member!;
                        return Semantics(
                          label: member.name,
                          button: true,
                          child: Container(
                            color: isHighlighted
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : Colors.transparent,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _select(entry),
                              child: SizedBox(
                                height: 48,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      MemberAvatar(
                                        avatarImageData: member.avatarImageData,
                                        memberName: member.name,
                                        emoji: member.emoji,
                                        customColorEnabled:
                                            member.customColorEnabled,
                                        customColorHex: member.customColorHex,
                                        size: 32,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          member.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: isHighlighted
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
      ),
    );
  }
}

class _BroadcastMentionRow extends StatelessWidget {
  const _BroadcastMentionRow({
    required this.alias,
    required this.isHighlighted,
    required this.onTap,
  });

  final String alias;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      label: '$alias, ${context.l10n.chatMentionEveryoneSemantics}',
      button: true,
      child: Container(
        color: isHighlighted
            ? primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary.withValues(alpha: 0.14),
                    ),
                    child: Icon(AppIcons.group, size: 18, color: primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isHighlighted
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        Text(
                          context.l10n.chatMentionEveryoneSemantics,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
