import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/features/members/providers/profile_entity_mentions_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/entity_mention_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

class EntityMentionTextField extends ConsumerStatefulWidget {
  const EntityMentionTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.minLines = 1,
    this.maxLines = 1,
    this.style,
    this.hintStyle,
    this.fieldStyle = PrismTextFieldStyle.standard,
    this.markdownEnabled = true,
  });

  final EntityMentionEditingController controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int? maxLines;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final PrismTextFieldStyle fieldStyle;
  final bool markdownEnabled;

  @override
  ConsumerState<EntityMentionTextField> createState() =>
      _EntityMentionTextFieldState();
}

class _EntityMentionTextFieldState
    extends ConsumerState<EntityMentionTextField> {
  final _fieldKey = GlobalKey();
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();

  late final FocusNode _focusNode;
  bool _ownsFocusNode = false;
  String _mentionFilter = '';
  bool _mentionMenuVisible = false;
  String _lastText = '';
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _lastText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant EntityMentionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      _lastText = widget.controller.text;
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    if (_overlayController.isShowing) _overlayController.hide();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final nextText = widget.controller.text;
    final selection = widget.controller.selection;
    var nextMentionVisible = false;
    var nextMentionFilter = '';
    if (selection.isValid && selection.isCollapsed) {
      final trigger = detectEntityMentionTrigger(
        nextText,
        selection.baseOffset,
      );
      if (trigger != null) {
        nextMentionVisible = true;
        nextMentionFilter = trigger.filter;
      }
    }

    if (_lastText == nextText &&
        _mentionMenuVisible == nextMentionVisible &&
        _mentionFilter == nextMentionFilter) {
      return;
    }

    setState(() {
      _lastText = nextText;
      _mentionMenuVisible = nextMentionVisible;
      _mentionFilter = nextMentionFilter;
      _highlightedIndex = 0;
    });
  }

  void _syncOverlay(bool shouldShow) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldShow) {
        if (!_overlayController.isShowing) _overlayController.show();
      } else if (_overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  _OverlayMetrics _overlayMetrics(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height - bottomInset;
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return _OverlayMetrics(
        availableWidth: screenWidth - 20,
        maxHeight: 280,
        showAbove: true,
      );
    }
    final anchor = renderBox.localToGlobal(Offset.zero);
    final anchorLeft = anchor.dx;
    final above = math.max(0.0, anchor.dy - mediaQuery.padding.top - 12);
    final below = math.max(
      0.0,
      screenHeight - (anchor.dy + renderBox.size.height) - 12,
    );
    final showAbove = above >= 180 || above >= below;
    return _OverlayMetrics(
      availableWidth: (screenWidth - anchorLeft - 12)
          .clamp(0.0, screenWidth - 20)
          .toDouble(),
      maxHeight: math.min(280, showAbove ? above : below),
      showAbove: showAbove,
    );
  }

  void _dismissOverlay() {
    if (_overlayController.isShowing) _overlayController.hide();
    if (!_mentionMenuVisible && _mentionFilter.isEmpty) return;
    setState(() {
      _mentionMenuVisible = false;
      _mentionFilter = '';
    });
  }

  void _selectCandidate(ProfileEntityMentionCandidate candidate) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    final trigger = detectEntityMentionTrigger(text, cursorPos);
    if (trigger == null) return;

    final replacement = '${candidate.token} ';
    final after = text.substring(cursorPos);
    final newText = text.substring(0, trigger.atIndex) + replacement + after;
    final newCursorPos = trigger.atIndex + replacement.length;

    widget.controller.removeListener(_onTextChanged);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
    widget.controller.addListener(_onTextChanged);

    widget.onChanged?.call(newText);
    _dismissOverlay();
    _focusNode.requestFocus();
    setState(() => _lastText = widget.controller.text);
  }

  void _moveHighlight(int delta, int candidateCount) {
    if (!_mentionMenuVisible || candidateCount == 0) return;
    setState(() {
      _highlightedIndex =
          (_highlightedIndex + delta + candidateCount) % candidateCount;
    });
  }

  void _selectHighlighted(List<ProfileEntityMentionCandidate> candidates) {
    if (!_mentionMenuVisible || candidates.isEmpty) return;
    final index = _highlightedIndex.clamp(0, candidates.length - 1);
    _selectCandidate(candidates[index]);
  }

  @override
  Widget build(BuildContext context) {
    widget.controller.updateTheme(context);
    final presentationChanged = widget.controller.updateMarkdownEnabled(
      widget.markdownEnabled,
      notify: false,
    );
    final resolutionsChanged = widget.controller.updateMentionResolutions(
      resolutions: ref.watch(
        profileEntityMentionResolutionsProvider(widget.controller.text),
      ),
      hiddenLabel: context.l10n.profileMentionPrivate,
      notify: false,
    );
    if (presentationChanged || resolutionsChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.notifyPresentationChanged();
      });
    }

    final candidatesAsync = ref.watch(
      profileEntityMentionCandidatesProvider(_mentionFilter),
    );
    final candidates = candidatesAsync.value ?? const [];
    if (_highlightedIndex >= candidates.length && candidates.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _highlightedIndex >= candidates.length) {
          setState(() => _highlightedIndex = 0);
        }
      });
    }
    final showOverlay =
        _mentionMenuVisible && _focusNode.hasFocus && candidates.isNotEmpty;
    _syncOverlay(showOverlay);
    final shortcutBindings = showOverlay
        ? <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveHighlight(1, candidates.length),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveHighlight(-1, candidates.length),
            const SingleActivator(LogicalKeyboardKey.enter): () =>
                _selectHighlighted(candidates),
            const SingleActivator(LogicalKeyboardKey.escape): _dismissOverlay,
          }
        : const <ShortcutActivator, VoidCallback>{};

    return CallbackShortcuts(
      bindings: shortcutBindings,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) {
          final metrics = _overlayMetrics(context);
          return CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: metrics.showAbove
                ? Alignment.topLeft
                : Alignment.bottomLeft,
            followerAnchor: metrics.showAbove
                ? Alignment.bottomLeft
                : Alignment.topLeft,
            offset: Offset(0, metrics.showAbove ? -8 : 8),
            child: TextFieldTapRegion(
              child: _EntityMentionOverlay(
                candidates: candidates,
                highlightedIndex: _highlightedIndex,
                availableWidth: metrics.availableWidth,
                maxHeight: metrics.maxHeight,
                onSelect: _selectCandidate,
              ),
            ),
          );
        },
        child: CompositedTransformTarget(
          key: _fieldKey,
          link: _layerLink,
          child: PrismTextField(
            controller: widget.controller,
            focusNode: _focusNode,
            labelText: widget.labelText,
            hintText: widget.hintText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            validator: widget.validator,
            autofocus: widget.autofocus,
            textCapitalization: widget.textCapitalization,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            style: widget.style,
            hintStyle: widget.hintStyle,
            fieldStyle: widget.fieldStyle,
            inputFormatters: const [AtomicEntityMentionFormatter()],
          ),
        ),
      ),
    );
  }
}

class _OverlayMetrics {
  const _OverlayMetrics({
    required this.availableWidth,
    required this.maxHeight,
    required this.showAbove,
  });

  final double availableWidth;
  final double maxHeight;
  final bool showAbove;
}

class _EntityMentionOverlay extends StatelessWidget {
  const _EntityMentionOverlay({
    required this.candidates,
    required this.highlightedIndex,
    required this.availableWidth,
    required this.maxHeight,
    required this.onSelect,
  });

  final List<ProfileEntityMentionCandidate> candidates;
  final int highlightedIndex;
  final double availableWidth;
  final double maxHeight;
  final ValueChanged<ProfileEntityMentionCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final popupWidth = math.min(availableWidth, 360.0);
    final minWidth = math.min(popupWidth, 240.0);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
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
                  maxHeight: math.max(72, maxHeight),
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.warmBlack.withValues(alpha: 0.65)
                      : AppColors.warmWhite.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(
                    PrismShapes.of(context).radius(16),
                  ),
                  border: Border.all(
                    color: isDark
                        ? AppColors.warmWhite.withValues(alpha: 0.12)
                        : AppColors.warmBlack.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.warmBlack.withValues(
                        alpha: isDark ? 0.4 : 0.12,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    return _EntityMentionCandidateRow(
                      candidate: candidate,
                      highlighted: index == highlightedIndex,
                      onTap: () => onSelect(candidate),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntityMentionCandidateRow extends StatelessWidget {
  const _EntityMentionCandidateRow({
    required this.candidate,
    required this.highlighted,
    required this.onTap,
  });

  final ProfileEntityMentionCandidate candidate;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (candidate.target.type) {
      EntityMentionType.member => AppIcons.person,
      EntityMentionType.group => AppIcons.group,
      EntityMentionType.note => AppIcons.notes,
      EntityMentionType.board => AppIcons.messageOutlined,
      EntityMentionType.conversation => AppIcons.chatOutlined,
    };
    final subtitle = switch (candidate.target.type) {
      EntityMentionType.member => context.l10n.profileMentionCandidateMember,
      EntityMentionType.group => context.l10n.profileMentionCandidateGroup,
      EntityMentionType.note => context.l10n.profileMentionCandidateNote,
      EntityMentionType.board => context.l10n.profileMentionCandidateBoard,
      EntityMentionType.conversation =>
        context.l10n.profileMentionCandidateConversation,
    };

    return Semantics(
      label: candidate.title,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: highlighted
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(10),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
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
