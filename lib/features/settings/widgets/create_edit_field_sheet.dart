import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

/// Modal sheet for creating or editing a custom field definition.
///
/// When [field] is provided the sheet operates in edit mode. The field type
/// is immutable once created.
///
/// Use via [PrismSheet.showFullScreen].
class CreateEditFieldSheet extends ConsumerStatefulWidget {
  const CreateEditFieldSheet({
    super.key,
    this.field,
    required this.scrollController,
  });

  final CustomField? field;
  final ScrollController scrollController;

  bool get isEditing => field != null;

  @override
  ConsumerState<CreateEditFieldSheet> createState() =>
      _CreateEditFieldSheetState();
}

class _CreateEditFieldSheetState extends ConsumerState<CreateEditFieldSheet> {
  late final TextEditingController _nameController;
  CustomFieldType _selectedType = CustomFieldType.text;
  DatePrecision _selectedPrecision = DatePrecision.full;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final f = widget.field;
    _nameController = TextEditingController(text: f?.name ?? '');
    if (f != null) {
      _selectedType = f.fieldType;
      _selectedPrecision = f.datePrecision ?? DatePrecision.full;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    try {
      final notifier = ref.read(customFieldNotifierProvider.notifier);

      if (widget.isEditing) {
        final updated = widget.field!.copyWith(
          name: name,
          datePrecision: _selectedType == CustomFieldType.date
              ? _selectedPrecision
              : null,
        );
        await notifier.updateField(updated);
      } else {
        await notifier.createField(
          name: name,
          fieldType: _selectedType,
          datePrecision: _selectedType == CustomFieldType.date
              ? _selectedPrecision
              : null,
        );
      }

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error saving field: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _nameController.text.trim().isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: widget.isEditing ? 'Edit Field' : 'New Field',
            trailing: _saving
                ? SizedBox(
                    width: PrismTokens.topBarActionSize,
                    height: PrismTokens.topBarActionSize,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : PrismGlassIconButton(
                    icon: AppIcons.check,
                    size: PrismTokens.topBarActionSize,
                    onPressed: canSave ? _save : null,
                  ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: PrismTokens.pageHorizontalPadding,
              ),
              children: [
                PrismTextField(
                  controller: _nameController,
                  labelText: 'Field Name',
                  hintText: 'e.g. Birthday, Favorite Color',
                  autofocus: !widget.isEditing,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // Type picker
                Text(
                  'Type',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.isEditing) ...[
                  // Immutable when editing — show read-only chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in CustomFieldType.values)
                        PrismChip(
                          label: type.label,
                          selected: type == _selectedType,
                          onTap: null,
                          avatar: Icon(_iconForType(type), size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type cannot be changed after creation.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in CustomFieldType.values)
                        PrismChip(
                          label: type.label,
                          selected: type == _selectedType,
                          onTap: () {
                            setState(() => _selectedType = type);
                            Haptics.selection();
                          },
                          avatar: Icon(_iconForType(type), size: 16),
                        ),
                    ],
                  ),
                ],

                // Date precision picker
                if (_selectedType == CustomFieldType.date) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Date Precision',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final precision in DatePrecision.values)
                        PrismChip(
                          label: precision.label,
                          selected: precision == _selectedPrecision,
                          onTap: () {
                            setState(() => _selectedPrecision = precision);
                            Haptics.selection();
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(CustomFieldType type) => switch (type) {
        CustomFieldType.text => AppIcons.textFields,
        CustomFieldType.color => AppIcons.palette,
        CustomFieldType.date => AppIcons.calendarToday,
      };
}
