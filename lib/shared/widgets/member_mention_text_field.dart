import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

class MemberMentionTextField extends ConsumerStatefulWidget {
  const MemberMentionTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.mentionCandidates,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode,
    this.enabled = true,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.minLines = 1,
    this.maxLines = 1,
    this.style,
    this.hintStyle,
    this.contentPadding,
    this.cursorColor,
    this.fieldStyle = PrismTextFieldStyle.standard,
    this.inputFormatters,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.prefixText,
    this.isDense,
    this.autocorrect,
    this.scrollPhysics,
    this.contextMenuBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Member>? mentionCandidates;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final bool enabled;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int? maxLines;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final EdgeInsetsGeometry? contentPadding;
  final Color? cursorColor;
  final PrismTextFieldStyle fieldStyle;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final TextAlign textAlign;
  final String? prefixText;
  final bool? isDense;
  final bool? autocorrect;
  final ScrollPhysics? scrollPhysics;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  @override
  ConsumerState<MemberMentionTextField> createState() =>
      _MemberMentionTextFieldState();
}

class _MemberMentionTextFieldState
    extends ConsumerState<MemberMentionTextField> {
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  final _overlayController = OverlayPortalController();
  final _overlayKey = GlobalKey<_MemberMentionOverlayState>();

  String _mentionFilter = '';
  bool _mentionMenuVisible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant MemberMentionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onTextChanged);
    widget.controller.addListener(_onTextChanged);
    _onTextChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final selection = widget.controller.selection;
    var nextMentionVisible = false;
    var nextMentionFilter = '';
    if (selection.isValid && selection.isCollapsed) {
      final trigger = detectMemberMentionTrigger(
        widget.controller.text,
        selection.baseOffset,
      );
      if (trigger != null) {
        nextMentionVisible = true;
        nextMentionFilter = trigger.filter;
      }
    }

    if (_mentionMenuVisible == nextMentionVisible &&
        _mentionFilter == nextMentionFilter) {
      return;
    }
    setState(() {
      _mentionMenuVisible = nextMentionVisible;
      _mentionFilter = nextMentionFilter;
    });
  }

  void _syncOverlayPortal(bool shouldShow) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldShow) {
        if (!_overlayController.isShowing) {
          _overlayController.show();
        }
      } else if (_overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  void _dismissOverlay() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    if (!_mentionMenuVisible && _mentionFilter.isEmpty) return;
    setState(() {
      _mentionMenuVisible = false;
      _mentionFilter = '';
    });
  }

  void _selectMember(Member member) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    final trigger = detectMemberMentionTrigger(text, cursorPos);
    if (trigger == null) return;

    final replacement = '@[${member.id}] ';
    final after = text.substring(cursorPos);
    final nextText = text.substring(0, trigger.atIndex) + replacement + after;
    final nextCursor = trigger.atIndex + replacement.length;
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    _dismissOverlay();
    widget.focusNode.requestFocus();
    widget.onChanged?.call(nextText);
  }

  double _overlayAvailableWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return screenWidth - 20;
    final anchorLeft = renderBox.localToGlobal(Offset.zero).dx;
    return (screenWidth - anchorLeft - 12)
        .clamp(0.0, screenWidth - 20)
        .toDouble();
  }

  bool _shouldOpenOverlayAbove(BuildContext context) {
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final top = renderBox.localToGlobal(Offset.zero).dy;
    final bottom = top + renderBox.size.height;
    final spaceBelow = screenHeight - bottom;
    final spaceAbove = top;
    return spaceBelow < 260 && spaceAbove > spaceBelow;
  }

  List<TextInputFormatter> _inputFormatters() {
    return [const AtomicMemberMentionFormatter(), ...?widget.inputFormatters];
  }

  void _updateControllerMentionMembers(Map<String, Member> memberMap) {
    final controller = widget.controller;
    if (controller is! MarkdownEditingController) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.controller, controller)) return;
      controller.updateMentionMembers(memberMap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final candidates =
        widget.mentionCandidates ??
        ref.watch(userVisibleMemberListProvider).value ??
        const <Member>[];
    final memberMap = {for (final member in candidates) member.id: member};
    _updateControllerMentionMembers(memberMap);

    final showOverlay = _mentionMenuVisible && candidates.isNotEmpty;
    _syncOverlayPortal(showOverlay);

    return Focus(
      onKeyEvent: showOverlay ? _handleKeyEvent : null,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) {
          final openAbove = _shouldOpenOverlayAbove(context);
          return CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor: openAbove
                ? Alignment.bottomLeft
                : Alignment.topLeft,
            offset: openAbove ? const Offset(0, -8) : const Offset(0, 8),
            child: TextFieldTapRegion(
              child: _MemberMentionOverlay(
                key: _overlayKey,
                members: candidates,
                filter: _mentionFilter,
                availableWidth: _overlayAvailableWidth(context),
                onSelect: _selectMember,
              ),
            ),
          );
        },
        child: CompositedTransformTarget(
          key: _fieldKey,
          link: _layerLink,
          child: PrismTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            labelText: widget.labelText,
            hintText: widget.hintText,
            helperText: widget.helperText,
            errorText: widget.errorText,
            prefixIcon: widget.prefixIcon,
            suffix: widget.suffix,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            validator: widget.validator,
            autovalidateMode: widget.autovalidateMode,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            textCapitalization: widget.textCapitalization,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            style: widget.style,
            hintStyle: widget.hintStyle,
            contentPadding: widget.contentPadding,
            cursorColor: widget.cursorColor,
            fieldStyle: widget.fieldStyle,
            inputFormatters: _inputFormatters(),
            maxLength: widget.maxLength,
            textAlign: widget.textAlign,
            prefixText: widget.prefixText,
            isDense: widget.isDense,
            autocorrect: widget.autocorrect,
            scrollPhysics: widget.scrollPhysics,
            contextMenuBuilder: widget.contextMenuBuilder,
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissOverlay();
      return KeyEventResult.handled;
    }
    final consumed = _overlayKey.currentState?.handleKeyEvent(event) ?? false;
    return consumed ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}

class _MemberMentionOverlay extends StatefulWidget {
  const _MemberMentionOverlay({
    super.key,
    required this.members,
    required this.filter,
    required this.availableWidth,
    required this.onSelect,
  });

  final List<Member> members;
  final String filter;
  final double availableWidth;
  final ValueChanged<Member> onSelect;

  @override
  State<_MemberMentionOverlay> createState() => _MemberMentionOverlayState();
}

class _MemberMentionOverlayState extends State<_MemberMentionOverlay> {
  int _selectedIndex = 0;

  List<Member> get _filtered {
    final lower = widget.filter.toLowerCase();
    if (lower.isEmpty) return widget.members;
    return widget.members
        .where((member) => member.name.toLowerCase().contains(lower))
        .toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant _MemberMentionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filter != oldWidget.filter) {
      _selectedIndex = 0;
    }
  }

  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final filtered = _filtered;
    if (filtered.isEmpty) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selectedIndex = (_selectedIndex + 1) % filtered.length);
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
      widget.onSelect(filtered[_selectedIndex]);
      return true;
    }
    return false;
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
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          key: const Key('memberMentionOverlaySurface'),
          width: popupWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(16),
            ),
            child: Container(
              constraints: BoxConstraints(minWidth: minWidth, maxHeight: 240),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.warmBlack.withValues(alpha: 0.88)
                    : theme.colorScheme.surface.withValues(alpha: 0.96),
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
                    color: AppColors.warmBlack.withValues(alpha: 0.18),
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
                  return Semantics(
                    label: member.name,
                    button: true,
                    child: Container(
                      color: isHighlighted
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onSelect(member),
                        child: SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
    );
  }
}
