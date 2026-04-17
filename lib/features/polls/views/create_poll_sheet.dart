import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Full-screen sheet for creating a new poll.
///
/// Use via [PrismSheet.showFullScreen] — pass the [scrollController] from the
/// builder callback.
class CreatePollSheet extends ConsumerStatefulWidget {
  const CreatePollSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends ConsumerState<CreatePollSheet> {
  final _questionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<String?> _optionColors = [null, null];

  bool _isAnonymous = false;
  bool _allowsMultipleVotes = false;
  bool _addOtherOption = false;
  bool _hasExpiration = false;
  DateTime? _expiresAt;
  bool _isCreating = false;

  @override
  void dispose() {
    _questionController.dispose();
    _descriptionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canCreate {
    if (_questionController.text.trim().isEmpty) return false;
    final filledOptions = _optionControllers
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    return filledOptions >= 2;
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
      _optionColors.add(null);
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
      _optionColors.removeAt(index);
    });
  }

  Future<void> _pickExpiration(BuildContext anchorContext) async {
    final now = DateTime.now();
    final date = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
      initialDate: _expiresAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted || !anchorContext.mounted) return;

    final time = await showPrismTimePicker(
      context: context,
      anchorContext: anchorContext,
      initialTime: TimeOfDay.fromDateTime(
        _expiresAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _expiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _createPoll() async {
    if (!_canCreate || _isCreating) return;
    setState(() => _isCreating = true);

    final optionTexts = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Collect colors for non-empty options, preserving order.
    final optionColorHexes = <String?>[];
    for (var i = 0; i < _optionControllers.length; i++) {
      if (_optionControllers[i].text.trim().isNotEmpty) {
        optionColorHexes.add(_optionColors[i]);
      }
    }

    final description = _descriptionController.text.trim();

    try {
      await ref
          .read(pollNotifierProvider.notifier)
          .createPoll(
            question: _questionController.text.trim(),
            description: description.isNotEmpty ? description : null,
            optionTexts: optionTexts,
            optionColorHexes: optionColorHexes,
            isAnonymous: _isAnonymous,
            allowsMultipleVotes: _allowsMultipleVotes,
            expiresAt: _hasExpiration ? _expiresAt : null,
            addOtherOption: _addOtherOption,
          );

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.pollsCreateError(e));
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: context.l10n.pollsNewPoll,
            trailing: PrismGlassIconButton(
                    icon: AppIcons.check,
                    size: PrismTokens.topBarActionSize,
                    isLoading: _isCreating,
                    tint: _canCreate ? theme.colorScheme.primary : null,
                    accentIcon: _canCreate,
                    onPressed: _canCreate ? _createPoll : null,
                  ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              children: [
                // Question
                PrismTextField(
                  controller: _questionController,
                  labelText: context.l10n.pollsQuestionLabel,
                  hintText: context.l10n.pollsQuestionHint,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // Description (optional)
                PrismTextField(
                  controller: _descriptionController,
                  labelText: context.l10n.pollsDescriptionLabel,
                  hintText: context.l10n.pollsDescriptionHint,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),

                // Options header
                Text(context.l10n.pollsOptionsHeader, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),

                // Option fields
                for (var i = 0; i < _optionControllers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        // Color dot
                        _OptionColorDot(
                          colorHex: _optionColors[i],
                          onColorSelected: (hex) {
                            setState(() => _optionColors[i] = hex);
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrismTextField(
                            controller: _optionControllers[i],
                            labelText: context.l10n.pollsOptionLabel(i + 1),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (_optionControllers.length > 2)
                          PrismIconButton(
                            icon: AppIcons.removeCircleOutline,
                            color: theme.colorScheme.error,
                            size: 36,
                            iconSize: 18,
                            onPressed: () => _removeOption(i),
                            tooltip: context.l10n.pollsRemoveOptionTooltip,
                          ),
                      ],
                    ),
                  ),

                // Add option button
                Align(
                  alignment: Alignment.centerLeft,
                  child: PrismButton(
                    label: context.l10n.pollsAddOption,
                    onPressed: _addOption,
                    icon: AppIcons.add,
                    tone: PrismButtonTone.subtle,
                  ),
                ),
                const SizedBox(height: 8),

                // Toggles
                PrismSwitchRow(
                  title: context.l10n.pollsAddOtherOption,
                  subtitle: context.l10n.pollsAddOtherOptionSubtitle,
                  value: _addOtherOption,
                  onChanged: (v) => setState(() => _addOtherOption = v),
                ),
                PrismSwitchRow(
                  title: context.l10n.pollsAnonymousVoting,
                  subtitle: context.l10n.pollsAnonymousVotingSubtitle,
                  value: _isAnonymous,
                  onChanged: (v) => setState(() => _isAnonymous = v),
                ),
                PrismSwitchRow(
                  title: context.l10n.pollsAllowMultipleVotes,
                  subtitle: context.l10n.pollsAllowMultipleVotesSubtitle(watchTerminology(context, ref).plural),
                  value: _allowsMultipleVotes,
                  onChanged: (v) => setState(() => _allowsMultipleVotes = v),
                ),

                // Expiration
                Builder(
                  builder: (anchorContext) => PrismSwitchRow(
                    title: context.l10n.pollsSetExpiration,
                    subtitle: _hasExpiration && _expiresAt != null
                        ? _formatDateTime(_expiresAt!)
                        : context.l10n.pollsNoExpiration,
                    value: _hasExpiration,
                    onChanged: (v) {
                      setState(() => _hasExpiration = v);
                      if (v) _pickExpiration(anchorContext);
                    },
                  ),
                ),
                if (_hasExpiration)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(
                      builder: (anchorContext) => PrismButton(
                        label: _expiresAt != null
                            ? context.l10n
                                .pollsChangeDateTime(_formatDateTime(_expiresAt!))
                            : context.l10n.pollsPickDateTime,
                        onPressed: () => _pickExpiration(anchorContext),
                        icon: AppIcons.schedule,
                        tone: PrismButtonTone.subtle,
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $amPm';
  }
}

/// A small color dot that opens a palette popover for choosing option colors.
class _OptionColorDot extends StatelessWidget {
  const _OptionColorDot({
    required this.colorHex,
    required this.onColorSelected,
  });

  final String? colorHex;
  final ValueChanged<String?> onColorSelected;

  static const _palette = [
    null, // no color
    'EF4444', // red
    'F97316', // orange
    'EAB308', // yellow
    '22C55E', // green
    '06B6D4', // cyan
    '3B82F6', // blue
    '8B5CF6', // violet
    'EC4899', // pink
    '6B7280', // gray
  ];

  Color _parseColor(String hex) {
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = colorHex != null
        ? _parseColor(colorHex!)
        : theme.colorScheme.outlineVariant;

    return BlurPopupAnchor(
      itemCount: 1,
      width: 200,
      maxHeight: 120,
      itemBuilder: (context, index, close) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in _palette)
              GestureDetector(
                onTap: () {
                  onColorSelected(hex);
                  close();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hex != null
                        ? _parseColor(hex)
                        : theme.colorScheme.surfaceContainerHighest,
                    border: hex == colorHex
                        ? Border.all(
                            color: theme.colorScheme.primary,
                            width: 2.5,
                          )
                        : null,
                  ),
                  child: hex == null
                      ? Icon(
                          AppIcons.block,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorHex != null ? _parseColor(colorHex!) : null,
          border: Border.all(color: dotColor, width: 2),
        ),
        child: colorHex == null
            ? Icon(
                AppIcons.paletteOutlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }
}
