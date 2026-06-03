import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_color_picker_dialog.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';
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
  final _descriptionController = MarkdownEditingController();
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

  bool get _isDirty =>
      _questionController.text.isNotEmpty ||
      _descriptionController.text.isNotEmpty ||
      _optionControllers.any((controller) => controller.text.isNotEmpty) ||
      _optionControllers.length != 2 ||
      _optionColors.any((color) => color != null) ||
      _isAnonymous ||
      _allowsMultipleVotes ||
      _addOtherOption ||
      _hasExpiration ||
      _expiresAt != null;

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

  /// Opens the full color picker for option [index]. Runs from the state so the
  /// async dialog is `mounted`-guarded; option colors are bare hex, so the
  /// picker's `#RRGGBB` result has its `#` stripped.
  Future<void> _pickCustomColor(int index) async {
    final current = _optionColors[index];
    Color initialColor;
    try {
      initialColor = current != null
          ? Color(int.parse('FF$current', radix: 16))
          : Theme.of(context).colorScheme.primary;
    } catch (_) {
      initialColor = Theme.of(context).colorScheme.primary;
    }

    final picked = await showPrismColorPickerDialog(
      context: context,
      initialColor: initialColor,
      title: context.l10n.pollsOptionColorTitle,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _optionColors[index] = picked.replaceFirst('#', '').toUpperCase();
    });
    Haptics.selection();
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
    _descriptionController.updateTheme(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        _questionController,
        _descriptionController,
        ..._optionControllers,
      ]),
      builder: (context, _) => UnsavedChangesGuard<void>(
        hasUnsavedChanges: _isDirty,
        child: SafeArea(
          child: Column(
            children: [
              PrismSheetTopBar(
                title: context.l10n.pollsNewPoll,
                trailing: PrismGlassIconButton(
                  icon: AppIcons.check,
                  tooltip: context.l10n.pollsCreateTooltip,
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
                    Text(
                      context.l10n.pollsOptionsHeader,
                      style: theme.textTheme.titleSmall,
                    ),
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
                                Haptics.selection();
                                setState(() => _optionColors[i] = hex);
                              },
                              onCustomRequested: () => _pickCustomColor(i),
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
                                textCapitalization:
                                    TextCapitalization.sentences,
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
                      subtitle: context.l10n.pollsAllowMultipleVotesSubtitle(
                        watchTerminology(context, ref).plural,
                      ),
                      value: _allowsMultipleVotes,
                      onChanged: (v) =>
                          setState(() => _allowsMultipleVotes = v),
                    ),

                    // Expiration
                    Builder(
                      builder: (anchorContext) => PrismSwitchRow(
                        title: context.l10n.pollsSetExpiration,
                        subtitle: _hasExpiration && _expiresAt != null
                            ? _formatDateTime(context, _expiresAt!)
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
                                ? context.l10n.pollsChangeDateTime(
                                    _formatDateTime(context, _expiresAt!),
                                  )
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
        ),
      ),
    );
  }

  String _formatDateTime(BuildContext context, DateTime dt) {
    return '${DateFormat.yMMMd(context.dateLocale).format(dt)} '
        '${context.formatTime(dt)}';
  }
}

/// A color dot that opens a popover of quick [_palette] swatches plus a custom
/// tile. Swatches report a bare-hex value (or null) via [onColorSelected]; the
/// custom flow is delegated to [onCustomRequested] so its dialog runs in the
/// `mounted` parent state.
class _OptionColorDot extends StatelessWidget {
  const _OptionColorDot({
    required this.colorHex,
    required this.onColorSelected,
    required this.onCustomRequested,
  });

  final String? colorHex;
  final ValueChanged<String?> onColorSelected;
  final VoidCallback onCustomRequested;

  /// Quick-pick swatches as bare uppercase `RRGGBB` hex. `null` is "no color".
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

  Color _parseColor(String hex) => Color(int.parse('FF$hex', radix: 16));

  /// Uppercased so swatch matching is case-insensitive.
  String? get _selectedHex => colorHex?.toUpperCase();

  /// True when the color isn't a quick swatch, so the custom tile shows selected.
  bool get _isCustom =>
      _selectedHex != null && !_palette.contains(_selectedHex);

  String _swatchLabel(BuildContext context, String? hex) {
    final l10n = context.l10n;
    return switch (hex) {
      null => l10n.pollsOptionColorNone,
      'EF4444' => l10n.pollsOptionColorRed,
      'F97316' => l10n.pollsOptionColorOrange,
      'EAB308' => l10n.pollsOptionColorYellow,
      '22C55E' => l10n.pollsOptionColorGreen,
      '06B6D4' => l10n.pollsOptionColorCyan,
      '3B82F6' => l10n.pollsOptionColorBlue,
      '8B5CF6' => l10n.pollsOptionColorViolet,
      'EC4899' => l10n.pollsOptionColorPink,
      '6B7280' => l10n.pollsOptionColorGray,
      _ => '#$hex',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    final dotColor = colorHex != null
        ? _parseColor(colorHex!)
        : theme.colorScheme.outlineVariant;

    return BlurPopupAnchor(
      itemCount: 1,
      width: 248,
      maxHeight: 260,
      semanticLabel: context.l10n.pollsOptionColorTitle,
      itemBuilder: (context, index, close) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in _palette)
              _PollColorSwatch(
                label: _swatchLabel(context, hex),
                color: hex != null ? _parseColor(hex) : null,
                isSelected: hex == _selectedHex,
                onTap: () {
                  onColorSelected(hex);
                  close();
                },
              ),
            _PollColorSwatch(
              label: context.l10n.pollsOptionColorCustom,
              color: _isCustom ? _parseColor(colorHex!) : null,
              isSelected: _isCustom,
              isCustom: true,
              onTap: () {
                // Close before the dialog so the two overlays don't stack.
                close();
                onCustomRequested();
              },
            ),
          ],
        ),
      ),
      child: Tooltip(
        message: context.l10n.pollsOptionColorTitle,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: shapes.avatarShape(),
            borderRadius: shapes.avatarBorderRadius(),
            color: colorHex != null ? _parseColor(colorHex!) : null,
            border: Border.all(color: dotColor, width: 2),
          ),
          child: colorHex == null
              ? Icon(
                  AppIcons.paletteOutlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
      ),
    );
  }
}

/// A 44×44 swatch in the option color popover: a quick color, the "no color"
/// slash, or the custom-picker tile. Selection adds a ring + check so it isn't
/// signalled by color alone.
class _PollColorSwatch extends StatelessWidget {
  const _PollColorSwatch({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
    this.isCustom = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;
  final bool isCustom;

  /// An icon color that stays legible on top of [fill].
  Color _onColor(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.light
      ? const Color(0xFF1A1A1A)
      : Colors.white;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    final hasColor = color != null;
    final fill = color ?? theme.colorScheme.surfaceContainerHighest;

    Widget? child;
    if (isSelected && hasColor) {
      child = Icon(AppIcons.check, size: 20, color: _onColor(fill));
    } else if (isCustom) {
      child = Icon(
        AppIcons.colorize,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      );
    } else if (color == null) {
      // "No color": a diagonal slash.
      child = Transform.rotate(
        angle: -math.pi / 4,
        child: Container(
          width: 30,
          height: 2.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: shapes.avatarShape(),
                  borderRadius: shapes.avatarBorderRadius(),
                  color: fill,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isSelected ? 3 : 1.5,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
