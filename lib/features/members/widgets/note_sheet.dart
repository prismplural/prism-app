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
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Create or edit a note. Shown as a full-screen PrismSheet.
class NoteSheet extends ConsumerStatefulWidget {
  const NoteSheet({super.key, this.note, this.memberId, this.scrollController});

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

  Future<void> _pickDate(BuildContext anchorContext) async {
    final picked = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
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
    if (result == null) return;
    setState(() {
      _selectedMemberId = result.isEmpty ? null : result;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return await PrismDialog.confirm(
      context: context,
      title: context.l10n.memberNoteDiscardTitle,
      message: context.l10n.memberNoteDiscardMessage,
      confirmLabel: context.l10n.memberNoteDiscardConfirm,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    _bodyController.updateTheme(context);

    return ListenableBuilder(
      listenable: Listenable.merge([_titleController, _bodyController]),
      builder: (context, _) => PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldDiscard = await _confirmDiscard();
          if (shouldDiscard && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Column(
          children: [
            PrismSheetTopBar(
              title: l10n.memberNoteTitle,
              trailing: PrismGlassIconButton(
                icon: AppIcons.check,
                onPressed: _isValid ? _save : null,
                enabled: _isValid,
                tooltip: l10n.memberSaveNoteTooltip,
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
                      hintText: l10n.memberNoteTitleHint,
                      fieldStyle: PrismTextFieldStyle.borderless,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      hintStyle: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
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
                      hintText: l10n.memberNoteBodyHint,
                      fieldStyle: PrismTextFieldStyle.borderless,
                      style: theme.textTheme.bodyLarge,
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
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
  final void Function(BuildContext anchorContext) onPickDate;
  final VoidCallback onPickMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final dateFormat = DateFormat.MMMd(context.dateLocale);
    final terminology = watchTerminology(context, ref);
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
          Builder(
            builder: (anchorContext) => _ToolbarChip(
              icon: AppIcons.calendarTodayOutlined,
              label: dateFormat.format(date),
              color: mutedColor,
              onTap: () => onPickDate(anchorContext),
              semanticLabel: l10n.memberNoteDateSemantics(
                DateFormat.yMMMd(context.dateLocale).format(date),
              ),
            ),
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
                memberName: member.name,
                emoji: member.emoji,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 20,
              ),
              semanticLabel: l10n.memberNoteMemberSemantics(member.name),
            )
          else
            _ToolbarChip(
              icon: AppIcons.personOutline,
              label: l10n.memberNoteAddHeadmate(terminology.singularLower),
              color: mutedColor.withValues(alpha: 0.6),
              onTap: onPickMember,
              semanticLabel: l10n.memberNoteNoHeadmateSemantics(
                terminology.singularLower,
              ),
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
