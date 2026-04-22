import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_picker_text_field_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';

/// Developer-only component gallery for rapid design iteration.
class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({super.key});

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  // ── Form state ──────────────────────────────────────────────────────
  // ignore: unused_field
  String _textFieldValue = '';
  String? _selectValue;
  bool _switchValue = false;
  bool _checkboxValue = false;
  bool _checkbox2Value = true;
  String _segmentValue = 'a';
  bool _chip1Selected = true;
  bool _chip2Selected = false;
  bool _chip3Selected = false;
  String _emoji = '';
  DateTime _dateTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Component Gallery',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ═══════════════════════════════════════════════════════════════
          // TEXT FIELDS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Text Fields'),
          const SizedBox(height: 8),

          PrismTextField(
            labelText: 'Standard field',
            hintText: 'Type something...',
            onChanged: (v) => setState(() => _textFieldValue = v),
          ),
          const SizedBox(height: 12),

          PrismTextField(
            labelText: 'With prefix icon',
            hintText: 'Search...',
            prefixIcon: Icon(AppIcons.search),
          ),
          const SizedBox(height: 12),

          const PrismTextField(
            labelText: 'With helper text',
            helperText: 'This is helper text below the field',
            hintText: 'Enter value',
          ),
          const SizedBox(height: 12),

          const PrismTextField(
            labelText: 'Error state',
            errorText: 'Required',
            hintText: 'Enter a value',
          ),
          const SizedBox(height: 12),

          const PrismTextField(
            labelText: 'Disabled',
            initialValue: 'Cannot edit this',
            enabled: false,
          ),
          const SizedBox(height: 12),

          PrismTextField(
            labelText: 'Password',
            hintText: 'Enter password',
            obscureText: true,
            prefixIcon: Icon(AppIcons.lock),
          ),
          const SizedBox(height: 12),

          const PrismTextField(
            labelText: 'Multi-line',
            hintText: 'Notes, descriptions...',
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),

          const PrismTextField(
            labelText: 'Borderless style',
            hintText: 'No outline',
            fieldStyle: PrismTextFieldStyle.borderless,
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // SELECTS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Selects'),
          const SizedBox(height: 8),

          PrismSelect<String>(
            labelText: 'Field style',
            hintText: 'Choose one...',
            value: _selectValue,
            items: const [
              PrismSelectItem(value: 'apple', label: 'Apple'),
              PrismSelectItem(value: 'banana', label: 'Banana'),
              PrismSelectItem(
                value: 'cherry',
                label: 'Cherry',
                subtitle: 'With subtitle',
              ),
              PrismSelectItem(
                value: 'disabled',
                label: 'Disabled option',
                enabled: false,
              ),
            ],
            onChanged: (v) => setState(() => _selectValue = v),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Text('Compact:', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 12),
              PrismSelect<String>.compact(
                hintText: 'Pick',
                value: _selectValue,
                items: const [
                  PrismSelectItem(value: 'apple', label: 'Apple'),
                  PrismSelectItem(value: 'banana', label: 'Banana'),
                  PrismSelectItem(value: 'cherry', label: 'Cherry'),
                ],
                onChanged: (v) => setState(() => _selectValue = v),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // SEGMENTED CONTROL
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Segmented Control'),
          const SizedBox(height: 8),

          PrismSegmentedControl<String>(
            segments: const [
              PrismSegment(value: 'a', label: 'First'),
              PrismSegment(value: 'b', label: 'Second'),
              PrismSegment(value: 'c', label: 'Third'),
            ],
            selected: _segmentValue,
            onChanged: (v) => setState(() => _segmentValue = v),
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // SWITCHES & CHECKBOXES
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Switches & Checkboxes'),
          const SizedBox(height: 8),

          PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                PrismSwitchRow(
                  title: 'Toggle option',
                  subtitle: 'With subtitle text',
                  icon: AppIcons.navSettings,
                  value: _switchValue,
                  onChanged: (v) => setState(() => _switchValue = v),
                ),
                PrismSwitchRow(
                  title: 'Disabled toggle',
                  value: true,
                  enabled: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                PrismCheckboxRow(
                  title: const Text('Checkbox option'),
                  value: _checkboxValue,
                  onChanged: (v) => setState(() => _checkboxValue = v),
                ),
                PrismCheckboxRow(
                  title: const Text('Leading checkbox'),
                  subtitle: const Text('Affinity: leading'),
                  value: _checkbox2Value,
                  checkboxAffinity: PrismCheckboxAffinity.leading,
                  onChanged: (v) => setState(() => _checkbox2Value = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // BUTTONS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Buttons'),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: 'Subtle',
                tone: PrismButtonTone.subtle,
                onPressed: () {},
              ),
              PrismButton(
                label: 'Filled',
                tone: PrismButtonTone.filled,
                onPressed: () {},
              ),
              PrismButton(
                label: 'Outlined',
                tone: PrismButtonTone.outlined,
                onPressed: () {},
              ),
              PrismButton(
                label: 'Destructive',
                tone: PrismButtonTone.destructive,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: 'With icon',
                icon: AppIcons.add,
                tone: PrismButtonTone.filled,
                onPressed: () {},
              ),
              PrismButton(
                label: 'Loading',
                tone: PrismButtonTone.filled,
                isLoading: true,
                onPressed: () {},
              ),
              PrismButton(
                label: 'Disabled',
                tone: PrismButtonTone.filled,
                enabled: false,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: 'Compact',
                tone: PrismButtonTone.filled,
                density: PrismControlDensity.compact,
                onPressed: () {},
              ),
              PrismButton(
                label: 'Compact outlined',
                tone: PrismButtonTone.outlined,
                density: PrismControlDensity.compact,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: PrismButton(
              label: 'Expanded button',
              icon: AppIcons.check,
              tone: PrismButtonTone.filled,
              expanded: true,
              onPressed: () {},
            ),
          ),
          const SizedBox(height: 16),

          // Icon buttons
          Text('Icon Buttons', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            spacing: 12,
            children: [
              PrismGlassIconButton(
                icon: AppIcons.add,
                onPressed: () {},
                tooltip: 'Glass icon button',
              ),
              PrismGlassIconButton(
                icon: AppIcons.edit,
                onPressed: () {},
                accentIcon: true,
                tooltip: 'Accent glass',
              ),
              PrismGlassIconButton(
                icon: AppIcons.refresh,
                onPressed: () {},
                isLoading: true,
                tooltip: 'Loading glass',
              ),
              PrismInlineIconButton(
                icon: AppIcons.copy,
                onPressed: () {},
                tooltip: 'Inline icon',
              ),
              PrismInlineIconButton(
                icon: AppIcons.delete,
                onPressed: () {},
                color: theme.colorScheme.error,
                tooltip: 'Destructive inline',
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // CHIPS & PILLS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Chips & Pills'),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismChip(
                label: 'Selected',
                selected: _chip1Selected,
                onTap: () => setState(() => _chip1Selected = !_chip1Selected),
              ),
              PrismChip(
                label: 'Unselected',
                selected: _chip2Selected,
                onTap: () => setState(() => _chip2Selected = !_chip2Selected),
              ),
              PrismChip(
                label: 'With avatar',
                selected: _chip3Selected,
                avatar: const Text('🌸'),
                onTap: () => setState(() => _chip3Selected = !_chip3Selected),
              ),
              PrismChip(
                label: 'Custom color',
                selected: true,
                selectedColor: Colors.teal,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const PrismPill(label: 'Neutral', tone: PrismPillTone.neutral),
              PrismPill(
                label: 'Accent',
                tone: PrismPillTone.accent,
                icon: AppIcons.checkCircle,
              ),
              PrismPill(
                label: 'Destructive',
                tone: PrismPillTone.destructive,
                icon: AppIcons.warningAmber,
              ),
              const PrismPill(label: 'Custom', color: Colors.teal),
            ],
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // SURFACES & LAYOUT
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Surfaces'),
          const SizedBox(height: 8),

          const PrismSurface(
            tone: PrismSurfaceTone.subtle,
            child: Text('PrismSurface — subtle'),
          ),
          const SizedBox(height: 8),
          const PrismSurface(
            tone: PrismSurfaceTone.strong,
            child: Text('PrismSurface — strong'),
          ),
          const SizedBox(height: 8),
          const PrismSurface(
            tone: PrismSurfaceTone.accent,
            child: Text('PrismSurface — accent'),
          ),
          const SizedBox(height: 8),
          PrismSurface(
            onTap: () => PrismToast.show(context, message: 'Tapped!'),
            child: const Text('PrismSurface — tappable'),
          ),

          const SizedBox(height: 16),

          const PrismSectionCard(
            padding: EdgeInsets.all(16),
            child: Text('PrismSectionCard — default'),
          ),
          const SizedBox(height: 8),
          const PrismSectionCard(
            tone: PrismSurfaceTone.accent,
            padding: EdgeInsets.all(16),
            child: Text('PrismSectionCard — accent'),
          ),

          const SizedBox(height: 16),

          const PrismSection(
            title: 'PrismSection',
            description: 'With a description underneath the title',
            child: PrismSurface(child: Text('Section content goes here')),
          ),

          const SizedBox(height: 16),

          PrismExpandableSection(
            title: const Text('Expandable Section'),
            subtitle: const Text('Tap to expand'),
            children: [
              PrismListRow(
                title: const Text('Item inside expandable'),
                leading: Icon(AppIcons.check),
              ),
              PrismListRow(
                title: const Text('Another item'),
                leading: Icon(AppIcons.check),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // LIST ROWS & SETTINGS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('List Rows'),
          const SizedBox(height: 8),

          PrismGroupedSectionCard(
            child: Column(
              children: [
                PrismListRow(
                  leading: Icon(AppIcons.navMembers),
                  title: const Text('Standard row'),
                  subtitle: const Text('With subtitle'),
                  showChevron: true,
                  onTap: () {},
                ),
                PrismListRow(
                  leading: Icon(AppIcons.edit),
                  title: const Text('Dense row'),
                  dense: true,
                  onTap: () {},
                ),
                PrismListRow(
                  leading: Icon(AppIcons.delete),
                  title: const Text('Destructive row'),
                  destructive: true,
                  onTap: () {},
                ),
                PrismListRow(
                  leading: Icon(AppIcons.lock),
                  title: const Text('Disabled row'),
                  enabled: false,
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          const _SectionHeader('Settings Rows'),
          const SizedBox(height: 8),

          PrismGroupedSectionCard(
            child: Column(
              children: [
                PrismSettingsRow(
                  icon: AppIcons.navSettings,
                  title: 'Settings row',
                  subtitle: 'With subtitle',
                  onTap: () {},
                ),
                PrismSettingsRow(
                  icon: AppIcons.delete,
                  title: 'Destructive settings',
                  destructive: true,
                  onTap: () {},
                ),
                PrismSettingsRow(
                  icon: AppIcons.lock,
                  title: 'With trailing',
                  trailing: const PrismPill(
                    label: 'Pro',
                    tone: PrismPillTone.accent,
                  ),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // PICKERS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Pickers'),
          const SizedBox(height: 8),

          PrismPickerTextFieldRow(
            pickerLabel: 'Emoji',
            picker: PrismEmojiPicker(
              emoji: _emoji.isEmpty ? null : _emoji,
              onSelected: (e) => setState(() => _emoji = e),
            ),
            field: const PrismTextField(
              initialValue: 'Group chat',
              labelText: 'Name',
            ),
          ),
          const SizedBox(height: 12),

          PrismDateTimePills(
            label: 'Date & Time',
            dateTime: _dateTime,
            onChanged: (dt) => setState(() => _dateTime = dt),
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // FEEDBACK & DIALOGS
          // ═══════════════════════════════════════════════════════════════
          const _SectionHeader('Feedback'),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: 'Show Toast',
                tone: PrismButtonTone.outlined,
                icon: AppIcons.infoOutline,
                onPressed: () =>
                    PrismToast.show(context, message: 'This is a toast'),
              ),
              PrismButton(
                label: 'Success Toast',
                tone: PrismButtonTone.outlined,
                icon: AppIcons.checkCircle,
                onPressed: () =>
                    PrismToast.success(context, message: 'Success!'),
              ),
              PrismButton(
                label: 'Error Toast',
                tone: PrismButtonTone.outlined,
                icon: AppIcons.errorOutline,
                onPressed: () =>
                    PrismToast.error(context, message: 'Something went wrong'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: 'Show Dialog',
                tone: PrismButtonTone.outlined,
                onPressed: () => PrismDialog.show(
                  context: context,
                  title: 'Dialog Title',
                  message:
                      'This is the dialog message body. '
                      'It can be multiple lines.',
                  actions: [
                    Builder(
                      builder: (dialogCtx) => PrismButton(
                        label: 'Cancel',
                        tone: PrismButtonTone.subtle,
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ),
                    Builder(
                      builder: (dialogCtx) => PrismButton(
                        label: 'Confirm',
                        tone: PrismButtonTone.filled,
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ),
                  ],
                  builder: (_) => const SizedBox.shrink(),
                ),
              ),
              PrismButton(
                label: 'Confirm Dialog',
                tone: PrismButtonTone.outlined,
                onPressed: () async {
                  final result = await PrismDialog.confirm(
                    context: context,
                    title: 'Are you sure?',
                    message: 'This action cannot be undone.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (context.mounted && result) {
                    PrismToast.show(context, message: 'Confirmed!');
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Loading state
          Text('Loading State', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          const SizedBox(height: 48, child: PrismLoadingState()),

          const SizedBox(height: 16),

          // Info banner
          InfoBanner(
            icon: AppIcons.infoOutline,
            iconColor: theme.colorScheme.primary,
            title: 'Info Banner',
            message:
                'This is an informational banner with an optional '
                'action button.',
            buttonText: 'Action',
            onButtonPressed: () {},
          ),

          const SizedBox(height: 16),

          // Empty state
          EmptyState(
            icon: Icon(
              AppIcons.search,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: 'Empty State',
            subtitle: 'Nothing to show here yet. Try adding something.',
            actionLabel: 'Add Item',
            actionIcon: AppIcons.add,
            onAction: () {},
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
