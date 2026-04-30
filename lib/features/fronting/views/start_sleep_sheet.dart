import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Bottom sheet to start a new sleep session, with an optional
/// "Log past sleep" disclosure that flips the form into a historical
/// entry mode (start in past + end-time field, no overlap blocking).
class StartSleepSheet extends ConsumerStatefulWidget {
  const StartSleepSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<StartSleepSheet> createState() => _StartSleepSheetState();
}

class _StartSleepSheetState extends ConsumerState<StartSleepSheet> {
  final _notesController = TextEditingController();
  late DateTime _startTime;
  DateTime? _endTime;
  bool _isHistorical = false;
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

  void _enterHistorical() {
    setState(() {
      _isHistorical = true;
      // Default historical entry: start 8h ago, end now
      _startTime = DateTime.now().subtract(const Duration(hours: 8));
      _endTime = DateTime.now();
    });
  }

  void _exitHistorical() {
    setState(() {
      _isHistorical = false;
      _startTime = DateTime.now();
      _endTime = null;
    });
  }

  Future<void> _submit() async {
    final notes = _notesController.text.trim().isNotEmpty
        ? _notesController.text.trim()
        : null;

    setState(() => _saving = true);
    try {
      final notifier = ref.read(sleepNotifierProvider.notifier);
      if (_isHistorical) {
        final endTime = _endTime ?? DateTime.now();
        if (!endTime.isAfter(_startTime)) {
          PrismToast.error(
            context,
            message: context.l10n.frontingEndTimeMustBeAfterStart,
          );
          return;
        }
        await notifier.logHistoricalSleep(
          startTime: _startTime,
          endTime: endTime,
          notes: notes,
        );
      } else {
        await notifier.startSleep(notes: notes, startTime: _startTime);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorStartingSleep(e),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _overlapsExisting(List<FrontingSession> existing) {
    if (!_isHistorical) return false;
    final end = _endTime ?? DateTime.now();
    for (final s in existing) {
      if (!s.isSleep) continue;
      final sEnd = s.endTime ?? DateTime.now();
      // [_startTime, end) overlaps [s.startTime, sEnd) iff
      // _startTime < sEnd && s.startTime < end
      if (_startTime.isBefore(sEnd) && s.startTime.isBefore(end)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Pull a window of recent sleep sessions for overlap detection.
    // When not in historical mode, we don't actually use this list,
    // but watching once keeps the cache warm if the user toggles in.
    final recentAsync = ref.watch(
      recentSleepSessionsPaginatedProvider(50),
    );
    final overlap = _isHistorical &&
        _overlapsExisting(recentAsync.value ?? const []);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PrismButton(
                label: l10n.cancel,
                onPressed: () => Navigator.of(context).pop(),
                enabled: !_saving,
                tone: PrismButtonTone.subtle,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.bedtimeRounded,
                    color: AppColors.sleep(theme.brightness),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.frontingStartSleepTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              PrismButton(
                label: l10n.frontingStartButton,
                onPressed: _submit,
                isLoading: _saving,
                tone: PrismButtonTone.filled,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PrismDateTimePills(
                  label: l10n.frontingStart,
                  dateTime: _startTime,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  onChanged: (dt) => setState(() => _startTime = dt),
                ),
                if (_isHistorical) ...[
                  const SizedBox(height: 16),
                  PrismDateTimePills(
                    label: l10n.frontingEnd,
                    dateTime: _endTime ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    onChanged: (dt) => setState(() => _endTime = dt),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : (_isHistorical
                            ? _exitHistorical
                            : _enterHistorical),
                    child: Text(
                      _isHistorical
                          ? l10n.cancelHistoricalSleep
                          : l10n.logPastSleep,
                    ),
                  ),
                ),
                if (overlap) ...[
                  const SizedBox(height: 8),
                  InfoBanner(
                    icon: AppIcons.infoOutline,
                    iconColor: theme.colorScheme.tertiary,
                    title: l10n.sleepOverlapsExistingWarning,
                    message: '',
                  ),
                ],
                const SizedBox(height: 16),
                PrismTextField(
                  controller: _notesController,
                  labelText: l10n.frontingNotes,
                  hintText: l10n.frontingStartSleepNotesHint,
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
