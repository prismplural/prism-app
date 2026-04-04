import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

/// Bottom sheet to start a new sleep session.
class StartSleepSheet extends ConsumerStatefulWidget {
  const StartSleepSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<StartSleepSheet> createState() => _StartSleepSheetState();
}

class _StartSleepSheetState extends ConsumerState<StartSleepSheet> {
  final _notesController = TextEditingController();
  late DateTime _startTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final date = await showPrismDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showPrismTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _startTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _startSleep() async {
    setState(() => _saving = true);

    try {
      final notifier = ref.read(sleepNotifierProvider.notifier);
      await notifier.startSleep(
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        startTime: _startTime,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error starting sleep: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PrismButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
                enabled: !_saving,
                tone: PrismButtonTone.subtle,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.bedtimeRounded,
                    color: theme.colorScheme.tertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Start Sleep',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              PrismButton(
                label: 'Start',
                onPressed: _startSleep,
                isLoading: _saving,
                tone: PrismButtonTone.filled,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PrismListRow(
                  leading: Icon(AppIcons.schedule),
                  title: const Text('Start Time'),
                  subtitle: Text(_formatDateTime(_startTime)),
                  trailing: Icon(AppIcons.edit),
                  onTap: _pickStartTime,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                PrismTextField(
                  controller: _notesController,
                  labelText: 'Notes',
                  hintText: 'Optional notes about this sleep...',
                  alignLabelWithHint: true,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[dt.month - 1];
    return '$month ${dt.day}, $hour:$minute $period';
  }
}
