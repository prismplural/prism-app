import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Surface-backed expandable section with a Prism-styled header row.
class PrismExpandableSection extends StatefulWidget {
  const PrismExpandableSection({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.children = const [],
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.enabled = true,
    this.dense = false,
    this.headerPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
    this.contentPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.contentSpacing = 12,
    this.margin = EdgeInsets.zero,
    this.tone = PrismSurfaceTone.subtle,
    this.accentColor,
    this.fillColor,
    this.borderColor,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final bool enabled;
  final bool dense;
  final EdgeInsets headerPadding;
  final EdgeInsets contentPadding;
  final double contentSpacing;
  final EdgeInsets margin;
  final PrismSurfaceTone tone;
  final Color? accentColor;
  final Color? fillColor;
  final Color? borderColor;

  @override
  State<PrismExpandableSection> createState() => _PrismExpandableSectionState();
}

class _PrismExpandableSectionState extends State<PrismExpandableSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant PrismExpandableSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  void _toggleExpanded() {
    if (!widget.enabled || widget.children.isEmpty) return;
    final nextValue = !_expanded;
    setState(() => _expanded = nextValue);
    widget.onExpansionChanged?.call(nextValue);
  }

  List<Widget> _buildContentChildren() {
    final content = <Widget>[];
    for (var index = 0; index < widget.children.length; index++) {
      if (index > 0 && widget.contentSpacing > 0) {
        content.add(SizedBox(height: widget.contentSpacing));
      }
      content.add(widget.children[index]);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = widget.children.isNotEmpty;
    final canToggle = widget.enabled && hasChildren;
    final chevronColor = widget.enabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85)
        : theme.disabledColor;

    Widget? trailing;
    if (widget.trailing != null || hasChildren) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.trailing != null) widget.trailing!,
          if (widget.trailing != null && hasChildren) const SizedBox(width: 8),
          if (hasChildren)
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: Anim.md,
              curve: Curves.easeOutCubic,
              child: Icon(AppIcons.expandMore, size: 18, color: chevronColor),
            ),
        ],
      );
    }

    return PrismSurface(
      padding: EdgeInsets.zero,
      margin: widget.margin,
      tone: widget.tone,
      accentColor: widget.accentColor,
      fillColor: widget.fillColor,
      borderColor: widget.borderColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrismListRow(
            title: widget.title,
            subtitle: widget.subtitle,
            leading: widget.leading,
            trailing: trailing,
            padding: widget.headerPadding,
            enabled: widget.enabled,
            dense: widget.dense,
            onTap: canToggle ? _toggleExpanded : null,
          ),
          if (hasChildren)
            ClipRect(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _expanded ? 1 : 0),
                duration: Anim.md,
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: widget.contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildContentChildren(),
                  ),
                ),
                builder: (context, value, child) {
                  if (value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment: Alignment.topCenter,
                    heightFactor: value,
                    child: Opacity(opacity: value.clamp(0, 1), child: child),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
