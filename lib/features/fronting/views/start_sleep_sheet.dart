import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

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

  // Date/time editing is handled inline by PrismDateTimePills.

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
        PrismToast.error(context, message: context.l10n.frontingErrorStartingSleep(e));
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
                label: context.l10n.cancel,
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
                    context.l10n.frontingStartSleepTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              PrismButton(
                label: context.l10n.frontingStartButton,
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
                PrismDateTimePills(
                  label: context.l10n.frontingStart,
                  dateTime: _startTime,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  onChanged: (dt) => setState(() => _startTime = dt),
                ),
                const SizedBox(height: 16),
                PrismTextField(
                  controller: _notesController,
                  labelText: context.l10n.frontingNotes,
                  hintText: context.l10n.frontingStartSleepNotesHint,
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

}
