import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

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

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
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
          title: _isEditing ? 'Edit Comment' : 'Add Comment',
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              PrismTextField(
                controller: _bodyController,
                hintText: 'Write your comment...',
                maxLines: 5,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: Text(
                    DateFormat.yMMMd().add_jm().format(_timestamp)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 24),
              PrismButton(
                onPressed: _save,
                enabled: _isValid,
                label: _isEditing ? 'Save' : 'Add',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
