import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/add_comment_sheet.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';

/// Comments section for a derived period.
///
/// Periods are not persisted rows, so this aggregates comments attached to the
/// physical [sessionIds] that make up the period and whose timestamp falls in
/// the half-open [range].
class CommentsForRangeSection extends ConsumerWidget {
  const CommentsForRangeSection({
    super.key,
    required this.sessionIds,
    required this.range,
  });

  final List<String> sessionIds;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(
      commentsForPeriodProvider(
        PeriodCommentsQuery(sessionIds: sessionIds, range: range),
      ),
    );
    final theme = Theme.of(context);

    return commentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (comments) {
        return PrismSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.l10n.frontingCommentsTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (comments.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  context.l10n.frontingNoCommentsYet,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                for (var i = 0; i < comments.length; i++) ...[
                  if (i > 0) const Divider(height: 16),
                  FrontSessionCommentTile(comment: comments[i]),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

enum _CommentAction { edit, delete }

class FrontSessionCommentTile extends ConsumerWidget {
  const FrontSessionCommentTile({super.key, required this.comment});

  final FrontSessionComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timeStr = context.formatTime(comment.timestamp);
    final dateStr = DateFormat.MMMd(
      context.dateLocale,
    ).format(comment.timestamp);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // Long press (and secondary click) on the comment itself keeps
          // opening the action menu that predates the visible overflow
          // affordance.
          child: BlurPopupAnchor(
            trigger: BlurPopupTrigger.longPress,
            itemCount: _CommentAction.values.length,
            itemBuilder: (_, index, close) {
              final action = _CommentAction.values[index];
              return _CommentActionRow(
                action: action,
                close: close,
                onActivate: () => _runCommentAction(
                  context: context,
                  ref: ref,
                  action: action,
                  comment: comment,
                ),
              );
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Text(
                      timeStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(comment.body, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
        _CommentActionsMenu(comment: comment),
      ],
    );
  }
}

/// Visible overflow affordance for a single comment.
///
/// Opens the same edit/delete actions as the long-press menu through a
/// [BlurPopupAnchor], so the actions are reachable by touch, mouse, keyboard,
/// and screen reader instead of only by a hidden gesture. Arrow keys move the
/// highlighted action while the menu is open and Enter/Space activates it.
class _CommentActionsMenu extends ConsumerStatefulWidget {
  const _CommentActionsMenu({required this.comment});

  final FrontSessionComment comment;

  @override
  ConsumerState<_CommentActionsMenu> createState() =>
      _CommentActionsMenuState();
}

class _CommentActionsMenuState extends ConsumerState<_CommentActionsMenu> {
  final GlobalKey<BlurPopupAnchorState> _popupKey = GlobalKey();

  /// Index of the action highlighted from the keyboard, or -1.
  final ValueNotifier<int> _highlightedAction = ValueNotifier<int>(-1);

  /// Number of action rows currently mounted by the open popup, and the
  /// dismissal callback of that popup while open.
  int _mountedRows = 0;
  VoidCallback? _closeMenu;

  @override
  void dispose() {
    _highlightedAction.dispose();
    super.dispose();
  }

  bool get _menuOpen => _mountedRows > 0;

  void _showMenu() {
    _highlightedAction.value = -1;
    _popupKey.currentState?.show();
  }

  void _handleRowMounted(VoidCallback close) {
    _mountedRows += 1;
    _closeMenu = close;
  }

  void _handleRowUnmounted() {
    if (_mountedRows > 0) _mountedRows -= 1;
    if (_mountedRows == 0) _closeMenu = null;
  }

  void _runAction(_CommentAction action) {
    _highlightedAction.value = -1;
    _runCommentAction(
      context: context,
      ref: ref,
      action: action,
      comment: widget.comment,
    );
  }

  void _moveHighlight(int delta) {
    final last = _CommentAction.values.length - 1;
    final current = _highlightedAction.value;
    if (current < 0) {
      _highlightedAction.value = delta > 0 ? 0 : last;
      return;
    }
    _highlightedAction.value = (current + delta).clamp(0, last).toInt();
  }

  void _activateHighlighted() {
    final index = _highlightedAction.value;
    if (index < 0 || index >= _CommentAction.values.length) return;
    final close = _closeMenu;
    final action = _CommentAction.values[index];
    close?.call();
    _runAction(action);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // While the menu is closed every key keeps its default behaviour; the
    // popup renders in an overlay outside this route's focus scope, so the
    // open menu is navigated here instead of by the ambient focus traversal.
    if (!_menuOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (_highlightedAction.value < 0) return KeyEventResult.ignored;
      _activateHighlighted();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      includeSemantics: false,
      onKeyEvent: _handleKeyEvent,
      child: BlurPopupAnchor(
        key: _popupKey,
        trigger: BlurPopupTrigger.manual,
        preferredDirection: BlurPopupDirection.down,
        width: 200,
        maxHeight: 168,
        itemCount: _CommentAction.values.length,
        itemBuilder: (_, index, close) {
          final action = _CommentAction.values[index];
          return ValueListenableBuilder<int>(
            valueListenable: _highlightedAction,
            builder: (_, highlighted, _) => _CommentActionRow(
              action: action,
              close: close,
              onActivate: () => _runAction(action),
              highlighted: highlighted == index,
              onMounted: _handleRowMounted,
              onUnmounted: _handleRowUnmounted,
            ),
          );
        },
        child: PrismInlineIconButton(
          icon: AppIcons.moreVert,
          tooltip: context.l10n.moreOptions,
          onPressed: _showMenu,
          onSecondaryTap: _showMenu,
        ),
      ),
    );
  }
}

/// Single row of the comment action menus, shared by the long-press menu and
/// the visible overflow menu.
///
/// [highlighted] marks the row the keyboard is currently on; when the menu
/// reports [onMounted]/[onUnmounted] the owner uses it to know whether the
/// popup is on screen.
class _CommentActionRow extends StatefulWidget {
  const _CommentActionRow({
    required this.action,
    required this.close,
    required this.onActivate,
    this.highlighted = false,
    this.onMounted,
    this.onUnmounted,
  });

  final _CommentAction action;
  final VoidCallback close;
  final VoidCallback onActivate;
  final bool highlighted;
  final ValueChanged<VoidCallback>? onMounted;
  final VoidCallback? onUnmounted;

  @override
  State<_CommentActionRow> createState() => _CommentActionRowState();
}

class _CommentActionRowState extends State<_CommentActionRow> {
  @override
  void initState() {
    super.initState();
    widget.onMounted?.call(widget.close);
  }

  @override
  void dispose() {
    widget.onUnmounted?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = switch (widget.action) {
      _CommentAction.edit => PrismListRow(
        leading: Icon(AppIcons.editOutlined),
        title: Text(context.l10n.edit),
        onTap: () {
          widget.close();
          widget.onActivate();
        },
      ),
      _CommentAction.delete => PrismListRow(
        leading: Icon(AppIcons.deleteOutline, color: theme.colorScheme.error),
        title: Text(
          context.l10n.delete,
          style: TextStyle(color: theme.colorScheme.error),
        ),
        onTap: () {
          widget.close();
          widget.onActivate();
        },
      ),
    };

    if (!widget.highlighted) return row;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(PrismTokens.radiusSmall),
        ),
      ),
      child: row,
    );
  }
}

void _runCommentAction({
  required BuildContext context,
  required WidgetRef ref,
  required _CommentAction action,
  required FrontSessionComment comment,
}) {
  switch (action) {
    case _CommentAction.edit:
      _openEditSheet(context, comment);
    case _CommentAction.delete:
      unawaited(_confirmDelete(context, ref, comment));
  }
}

void _openEditSheet(BuildContext context, FrontSessionComment comment) {
  final sessionId = comment.sessionId;
  if (sessionId.trim().isEmpty) return;
  PrismSheet.showFullScreen(
    context: context,
    builder: (context, scrollController) => AddCommentSheet(
      sessionId: sessionId,
      timestamp: comment.timestamp,
      comment: comment,
      scrollController: scrollController,
    ),
  );
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  FrontSessionComment comment,
) async {
  final confirmed = await PrismDialog.confirm(
    context: context,
    title: context.l10n.frontingDeleteCommentTitle,
    message: context.l10n.frontingDeleteCommentMessage,
    confirmLabel: context.l10n.delete,
    destructive: true,
  );
  if (confirmed) {
    unawaited(
      ref.read(commentNotifierProvider.notifier).deleteComment(comment.id),
    );
  }
}
