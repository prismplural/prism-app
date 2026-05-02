import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/utils/member_name_style.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

class MemberNameStyleDialog extends StatefulWidget {
  const MemberNameStyleDialog({
    super.key,
    required this.member,
    required this.onSaved,
  });

  final Member member;
  final ValueChanged<Member> onSaved;

  static Future<void> show({
    required BuildContext context,
    required Member member,
    required ValueChanged<Member> onSaved,
  }) {
    return PrismDialog.show<void>(
      context: context,
      title: context.l10n.memberNameStyleDialogTitle,
      builder: (_) => MemberNameStyleDialog(member: member, onSaved: onSaved),
    );
  }

  @override
  State<MemberNameStyleDialog> createState() => _MemberNameStyleDialogState();
}

class _MemberNameStyleDialogState extends State<MemberNameStyleDialog> {
  late Member _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.member;
  }

  void _update(Member draft) {
    setState(() => _draft = draft);
  }

  void _reset() {
    _update(
      _draft.copyWith(
        nameStyleFont: MemberNameFont.standard,
        nameStyleBold: true,
        nameStyleItalic: false,
        nameStyleColorMode: MemberNameColorMode.standard,
        nameStyleColorHex: null,
      ),
    );
  }

  void _save() {
    widget.onSaved(_draft);
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final maxScrollableHeight = MediaQuery.sizeOf(context).height * 0.54;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxScrollableHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NamePreview(member: _draft),
                const SizedBox(height: 16),
                _ControlLabel(context.l10n.memberNameStyleFontLabel),
                const SizedBox(height: 8),
                PrismSegmentedControl<MemberNameFont>(
                  selected: _draft.nameStyleFont,
                  onChanged: (font) =>
                      _update(_draft.copyWith(nameStyleFont: font)),
                  segments: [
                    PrismSegment(
                      value: MemberNameFont.standard,
                      label: context.l10n.memberNameStyleFontDefault,
                    ),
                    PrismSegment(
                      value: MemberNameFont.display,
                      label: context.l10n.memberNameStyleFontDisplay,
                    ),
                    PrismSegment(
                      value: MemberNameFont.serif,
                      label: context.l10n.memberNameStyleFontSerif,
                    ),
                    PrismSegment(
                      value: MemberNameFont.mono,
                      label: context.l10n.memberNameStyleFontMono,
                    ),
                    PrismSegment(
                      value: MemberNameFont.rounded,
                      label: context.l10n.memberNameStyleFontRounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ControlLabel(context.l10n.memberNameStyleStyleLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PrismButton(
                      label: context.l10n.memberNameStyleBold,
                      icon: AppIcons.textBold,
                      tone: _draft.nameStyleBold
                          ? PrismButtonTone.filled
                          : PrismButtonTone.subtle,
                      density: PrismControlDensity.compact,
                      onPressed: () => _update(
                        _draft.copyWith(nameStyleBold: !_draft.nameStyleBold),
                      ),
                    ),
                    PrismButton(
                      label: context.l10n.memberNameStyleItalic,
                      icon: AppIcons.textItalic,
                      tone: _draft.nameStyleItalic
                          ? PrismButtonTone.filled
                          : PrismButtonTone.subtle,
                      density: PrismControlDensity.compact,
                      onPressed: () => _update(
                        _draft.copyWith(
                          nameStyleItalic: !_draft.nameStyleItalic,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ControlLabel(context.l10n.memberNameStyleColorLabel),
                const SizedBox(height: 8),
                PrismSegmentedControl<MemberNameColorMode>(
                  selected: _draft.nameStyleColorMode,
                  onChanged: (mode) => _update(
                    _draft.copyWith(
                      nameStyleColorMode: mode,
                      nameStyleColorHex: mode == MemberNameColorMode.custom
                          ? _draft.nameStyleColorHex ??
                                memberNameColorHex(
                                  resolveMemberNameColor(
                                    context,
                                    _draft.copyWith(
                                      nameStyleColorMode:
                                          MemberNameColorMode.accent,
                                    ),
                                  )!,
                                )
                          : null,
                    ),
                  ),
                  segments: [
                    PrismSegment(
                      value: MemberNameColorMode.standard,
                      label: context.l10n.memberNameStyleColorDefault,
                    ),
                    PrismSegment(
                      value: MemberNameColorMode.accent,
                      label: context.l10n.memberNameStyleColorAccent,
                    ),
                    PrismSegment(
                      value: MemberNameColorMode.custom,
                      label: context.l10n.memberNameStyleColorCustom,
                    ),
                  ],
                ),
                if (_draft.nameStyleColorMode ==
                    MemberNameColorMode.custom) ...[
                  const SizedBox(height: 12),
                  _CustomColorPicker(
                    color: resolveMemberNameColor(context, _draft)!,
                    onChanged: (color) => _update(
                      _draft.copyWith(
                        nameStyleColorHex: memberNameColorHex(color),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            PrismButton(
              label: context.l10n.memberNameStyleReset,
              tone: PrismButtonTone.subtle,
              onPressed: _reset,
            ),
            PrismButton(
              label: context.l10n.cancel,
              tone: PrismButtonTone.outlined,
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
            PrismButton(
              label: context.l10n.save,
              tone: PrismButtonTone.filled,
              onPressed: _save,
            ),
          ],
        ),
      ],
    );
  }
}

class _NamePreview extends StatelessWidget {
  const _NamePreview({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = member.displayName?.trim();
    final name = displayName != null && displayName.isNotEmpty
        ? displayName
        : member.name;
    final style = resolveMemberNameTextStyle(
      context,
      member,
      theme.textTheme.headlineSmall ??
          const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      defaultColor: theme.colorScheme.onSurface,
    );

    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Text(
        name.isEmpty ? context.l10n.memberNameHint : name,
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CustomColorPicker extends StatelessWidget {
  const _CustomColorPicker({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ColorPicker(
          pickerColor: color,
          onColorChanged: onChanged,
          enableAlpha: false,
          hexInputBar: true,
          labelTypes: const [],
          pickerAreaHeightPercent: 0.65,
        ),
      ),
    );
  }
}

class _ControlLabel extends StatelessWidget {
  const _ControlLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
