import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_select_sheet.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Create or edit a note. Shown as a full-screen PrismSheet.
///
/// Inline editor with borderless title/body fields, bottom toolbar for date
/// and optional headmate selection, and a save checkmark in the top bar.
class NoteSheet extends ConsumerStatefulWidget {
  const NoteSheet({
    super.key,
    this.note,
    this.memberId,
    this.scrollController,
  });

  final Note? note;
  final String? memberId;
  final ScrollController? scrollController;

  @override
  ConsumerState<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<NoteSheet> {
  late final TextEditingController _titleController;
  late final MarkdownEditingController _bodyController;
  late final FocusNode _bodyFocusNode;
  late DateTime _date;
  late String? _selectedMemberId;
  String? _colorHex;

  // Track initial values for dirty checking.
  late final String _initialTitle;
  late final String _initialBody;
  late final DateTime _initialDate;
  late final String? _initialMemberId;

  bool get _isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();
    _initialTitle = widget.note?.title ?? '';
    _initialBody = widget.note?.body ?? '';
    _initialDate = widget.note?.date ?? DateTime.now();
    _initialMemberId = widget.note?.memberId ?? widget.memberId;

    _titleController = TextEditingController(text: _initialTitle);
    _bodyController = MarkdownEditingController(text: _initialBody);
    _bodyFocusNode = FocusNode();
    _date = _initialDate;
    _selectedMemberId = _initialMemberId;
    _colorHex = widget.note?.colorHex;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  bool get _isDirty =>
      _titleController.text != _initialTitle ||
      _bodyController.text != _initialBody ||
      _date != _initialDate ||
      _selectedMemberId != _initialMemberId;

  Future<void> _save() async {
    if (!_isValid) return;
    final notifier = ref.read(noteNotifierProvider.notifier);
    if (_isEditing) {
      await notifier.updateNote(
        widget.note!.copyWith(
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          colorHex: _colorHex,
          memberId: _selectedMemberId,
          date: _date,
        ),
      );
    } else {
      await notifier.createNote(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        colorHex: _colorHex,
        memberId: _selectedMemberId,
        date: _date,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickMember() async {
    final result = await MemberSelectSheet.show(
      context,
      currentMemberId: _selectedMemberId,
    );
    if (result == null) return; // Dismissed without selection.
    setState(() {
      _selectedMemberId = result.isEmpty ? null : result;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return await PrismDialog.confirm(
      context: context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Are you sure you want to discard them?',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _bodyController.updateTheme(context);

    return ListenableBuilder(
      listenable: Listenable.merge([_titleController, _bodyController]),
      builder: (context, _) => PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldDiscard = await _confirmDiscard();
          if (shouldDiscard && mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Column(
          children: [
            PrismSheetTopBar(
              title: 'Note',
              trailing: PrismGlassIconButton(
                icon: AppIcons.check,
                onPressed: _isValid ? _save : null,
                enabled: _isValid,
                tooltip: 'Save note',
                size: PrismTokens.topBarActionSize,
                tint: theme.colorScheme.primary,
                accentIcon: true,
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _bodyFocusNode.requestFocus(),
                behavior: HitTestBehavior.translucent,
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrismTokens.pageHorizontalPadding + 8,
                    vertical: 16,
                  ),
                  children: [
                    PrismTextField(
                      controller: _titleController,
                      hintText: 'Title',
                      fieldStyle: PrismTextFieldStyle.borderless,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      hintStyle: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      autofocus: !_isEditing,
                    ),
                    const SizedBox(height: 8),
                    PrismTextField(
                      controller: _bodyController,
                      focusNode: _bodyFocusNode,
                      hintText: 'Start writing...',
                      fieldStyle: PrismTextFieldStyle.borderless,
                      style: theme.textTheme.bodyLarge,
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                      minLines: 12,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
            ),
          _BottomToolbar(
            date: _date,
            memberId: _selectedMemberId,
            onPickDate: _pickDate,
            onPickMember: _pickMember,
          ),
          ],
        ),
      ),
    );
  }
}

/// Bottom toolbar with date and member chips, pinned above keyboard.
class _BottomToolbar extends ConsumerWidget {
  const _BottomToolbar({
    required this.date,
    required this.memberId,
    required this.onPickDate,
    required this.onPickMember,
  });

  final DateTime date;
  final String? memberId;
  final VoidCallback onPickDate;
  final VoidCallback onPickMember;

  static final _dateFormat = DateFormat.MMMd();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    // Resolve member if set.
    final member = memberId != null
        ? ref.watch(memberByIdProvider(memberId!)).value
        : null;

    return Container(
      padding: EdgeInsets.only(
        left: PrismTokens.pageHorizontalPadding + 8,
        right: PrismTokens.pageHorizontalPadding + 8,
        top: 8,
        bottom: 8 + bottomInset,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Date chip.
          _ToolbarChip(
            icon: AppIcons.calendarTodayOutlined,
            label: _dateFormat.format(date),
            color: mutedColor,
            onTap: onPickDate,
            semanticLabel:
                'Note date, ${DateFormat.yMMMd().format(date)}. Tap to change',
          ),
          const SizedBox(width: 8),
          // Member chip.
          if (member != null)
            _ToolbarChip(
              icon: null,
              label: member.name,
              color: mutedColor,
              onTap: onPickMember,
              leading: MemberAvatar(
                avatarImageData: member.avatarImageData,
                emoji: member.emoji,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 20,
              ),
              semanticLabel:
                  'Headmate: ${member.name}. Tap to change',
            )
          else
            _ToolbarChip(
              icon: AppIcons.personOutline,
              label: 'Add headmate',
              color: mutedColor.withValues(alpha: 0.6),
              onTap: onPickMember,
              semanticLabel: 'No headmate selected. Tap to choose',
            ),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.leading,
    this.semanticLabel,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? leading;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
