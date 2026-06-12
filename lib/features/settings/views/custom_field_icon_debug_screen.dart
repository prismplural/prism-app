import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/custom_field_header_icon.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

class CustomFieldIconDebugScreen extends StatelessWidget {
  const CustomFieldIconDebugScreen({super.key});

  static final _samples = <_IconSample>[
    const _IconSample('Fallback', null, detail: 'No headerIcon'),
    const _IconSample(
      'Phosphor',
      CustomFieldHeaderIcon.phosphor('sparkle'),
      detail: 'sparkle',
    ),
    const _IconSample(
      'Simple emoji',
      CustomFieldHeaderIcon.emoji('⚡'),
      emoji: '⚡',
    ),
    const _IconSample(
      'Emoji VS16',
      CustomFieldHeaderIcon.emoji('☕️'),
      emoji: '☕️',
    ),
    const _IconSample(
      'Text VS15',
      CustomFieldHeaderIcon.emoji('☕︎'),
      emoji: '☕︎',
    ),
    const _IconSample(
      'ZWJ sequence',
      CustomFieldHeaderIcon.emoji('🧑‍🚀'),
      emoji: '🧑‍🚀',
    ),
    const _IconSample(
      'Skin tone',
      CustomFieldHeaderIcon.emoji('👍🏽'),
      emoji: '👍🏽',
    ),
    const _IconSample(
      'Regional flag',
      CustomFieldHeaderIcon.emoji('🇨🇷'),
      emoji: '🇨🇷',
    ),
    const _IconSample(
      'ZWJ flag',
      CustomFieldHeaderIcon.emoji('🏳️‍⚧️'),
      emoji: '🏳️‍⚧️',
    ),
    const _IconSample(
      'Keycap',
      CustomFieldHeaderIcon.emoji('1️⃣'),
      emoji: '1️⃣',
    ),
  ];

  static final _variants = <_FieldVariant>[
    _FieldVariant('Null config', 'text', CustomFieldType.text, (_) => null),
    _FieldVariant(
      'TextConfig',
      'text',
      CustomFieldType.text,
      (icon) => TextConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'ColorConfig',
      'color',
      CustomFieldType.color,
      (icon) => ColorConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'DateConfig',
      'date',
      CustomFieldType.date,
      (icon) => DateConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'LongTextConfig',
      'long_text',
      CustomFieldType.longText,
      (icon) => LongTextConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'ChoiceConfig',
      'choice',
      CustomFieldType.choice,
      (icon) => ChoiceConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'GroupConfig',
      'group',
      CustomFieldType.text,
      (icon) => GroupConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'ScaleConfig',
      'scale',
      CustomFieldType.text,
      (icon) => ScaleConfig(headerIcon: icon),
    ),
    _FieldVariant(
      'SliderConfig',
      'slider',
      CustomFieldType.text,
      (icon) => SliderConfig(mode: SliderMode.labeled, headerIcon: icon),
    ),
    _FieldVariant(
      'MemberConfig',
      'member',
      CustomFieldType.text,
      (icon) => MemberConfig(headerIcon: icon),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Custom Field Icon Debug',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: PrismTokens.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SummaryCard(),
                  const SizedBox(height: 16),
                  for (final sample in _samples) ...[
                    _SampleMatrix(sample: sample, variants: _variants),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rendering paths',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Each section crosses one icon sample with every type_config '
            'variant that can store headerIcon.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendChip('Raw title'),
              _LegendChip('MemberAvatar.centeredEmoji'),
              _LegendChip('CustomFieldHeaderIconView'),
              _LegendChip('PrismListRow title'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SampleMatrix extends StatelessWidget {
  const _SampleMatrix({required this.sample, required this.variants});

  final _IconSample sample;
  final List<_FieldVariant> variants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SampleBadge(sample: sample),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sample.detailText != null)
                      Text(
                        sample.detailText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MatrixHeader(),
                const SizedBox(height: 6),
                for (final variant in variants)
                  _MatrixRow(sample: sample, variant: variant),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixHeader extends StatelessWidget {
  const _MatrixHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _HeaderCell(width: 132, label: 'Config'),
        _HeaderCell(width: 116, label: 'Raw title'),
        _HeaderCell(width: 72, label: '16'),
        _HeaderCell(width: 72, label: '20'),
        _HeaderCell(width: 72, label: '28'),
        _HeaderCell(width: 184, label: 'Title row'),
        _HeaderCell(width: 228, label: 'List row'),
      ],
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({required this.sample, required this.variant});

  final _IconSample sample;
  final _FieldVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = variant.fieldFor(sample.icon);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _BodyCell(
            width: 132,
            child: Text(
              variant.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          _BodyCell(width: 116, child: _RawTitle(sample: sample)),
          _BodyCell(
            width: 72,
            child: CustomFieldHeaderIconView(field: field, size: 16),
          ),
          _BodyCell(
            width: 72,
            child: CustomFieldHeaderIconView(field: field, size: 20),
          ),
          _BodyCell(
            width: 72,
            child: CustomFieldHeaderIconView(field: field, size: 28),
          ),
          _BodyCell(width: 184, child: _InlineTitle(field: field)),
          _BodyCell(width: 228, child: _ListRowTitle(field: field)),
        ],
      ),
    );
  }
}

class _RawTitle extends StatelessWidget {
  const _RawTitle({required this.sample});

  final _IconSample sample;

  @override
  Widget build(BuildContext context) {
    final emoji = sample.emoji;
    if (emoji == null) {
      return Text(
        'Title',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      );
    }
    return Text(
      '$emoji Title',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

class _InlineTitle extends StatelessWidget {
  const _InlineTitle({required this.field});

  final CustomField field;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomFieldHeaderIconView(field: field, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            field.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

class _ListRowTitle extends StatelessWidget {
  const _ListRowTitle({required this.field});

  final CustomField field;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: PrismListRow(
        dense: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        leading: CustomFieldHeaderIconView(field: field, size: 18),
        title: Text(field.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('subtitle', maxLines: 1),
      ),
    );
  }
}

class _SampleBadge extends StatelessWidget {
  const _SampleBadge({required this.sample});

  final _IconSample sample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = sample.emoji;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: emoji != null
          ? MemberAvatar.centeredEmoji(emoji, fontSize: 28)
          : Icon(
              sample.icon == null ? AppIcons.textFields : AppIcons.autoAwesome,
              size: 24,
              color: theme.colorScheme.primary,
            ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.width, required this.label});

  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: theme.textTheme.labelMedium),
      ),
    );
  }
}

class _IconSample {
  const _IconSample(this.label, this.icon, {this.emoji, this.detail});

  final String label;
  final CustomFieldHeaderIcon? icon;
  final String? emoji;
  final String? detail;

  String? get detailText {
    final emojiValue = emoji;
    if (emojiValue == null) return detail;
    final codepoints = emojiValue.runes
        .map(
          (rune) => 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        )
        .join(' ');
    return detail == null ? codepoints : '$detail • $codepoints';
  }
}

class _FieldVariant {
  const _FieldVariant(
    this.label,
    this.fieldTypeId,
    this.fieldType,
    this.configBuilder,
  );

  final String label;
  final String fieldTypeId;
  final CustomFieldType fieldType;
  final CustomFieldTypeConfig? Function(CustomFieldHeaderIcon? icon)
  configBuilder;

  CustomField fieldFor(CustomFieldHeaderIcon? icon) {
    return CustomField(
      id: 'debug-$fieldTypeId-${icon?.kind.name ?? 'fallback'}',
      name: label,
      fieldType: fieldType,
      fieldTypeId: fieldTypeId,
      createdAt: DateTime(2026, 6, 12),
      typeConfig: configBuilder(icon),
    );
  }
}
