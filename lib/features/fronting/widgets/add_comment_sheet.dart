import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

/// Create or edit a front session comment.
class AddCommentSheet extends ConsumerStatefulWidget {
  const AddCommentSheet({
    super.key,
    required this.sessionId,
    this.comment,
    this.scrollController,
  });

  final String sessionId;
  final FrontSessionComment? comment;
  final ScrollController? scrollController;

  @override
  ConsumerState<AddCommentSheet> createState() => _AddCommentSheetState();
}

class _AddCommentSheetState extends ConsumerState<AddCommentSheet> {
  late final TextEditingController _bodyController;
  late DateTime _timestamp;

  bool get _isEditing => widget.comment != null;

  @override
  void initState() {
    super.initState();
    _bodyController =
        TextEditingController(text: widget.comment?.body ?? '');
    _timestamp = widget.comment?.timestamp ?? DateTime.now();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isValid => _bodyController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_isValid) return;
    final notifier = ref.read(commentNotifierProvider.notifier);
    if (_isEditing) {
      await notifier.updateComment(
        widget.comment!.copyWith(
          body: _bodyController.text.trim(),
          timestamp: _timestamp,
        ),
      );
    } else {
      await notifier.createComment(
        sessionId: widget.sessionId,
        body: _bodyController.text.trim(),
        timestamp: _timestamp,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDateTime(BuildContext anchorContext) async {
    final date = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
      initialDate: _timestamp,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted || !anchorContext.mounted) return;
    final time = await showPrismTimePicker(
      context: context,
      anchorContext: anchorContext,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (time != null) {
      setState(() {
        _timestamp = DateTime(
            date.year, date.month, date.day, time.hour, time.minute);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PrismSheetTopBar(
          title: _isEditing ? context.l10n.frontingEditCommentTitle : context.l10n.frontingAddCommentTitle,
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              PrismTextField(
                controller: _bodyController,
                hintText: context.l10n.frontingCommentHint,
                maxLines: 5,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (anchorContext) => PrismListRow(
                  padding: EdgeInsets.zero,
                  leading: Icon(AppIcons.accessTime),
                  title: Text(DateFormat.yMMMd(context.dateLocale)
                      .add_jm()
                      .format(_timestamp)),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () => _pickDateTime(anchorContext),
                ),
              ),
              const SizedBox(height: 24),
              PrismButton(
                onPressed: _save,
                enabled: _isValid,
                label: _isEditing ? context.l10n.save : context.l10n.add,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
