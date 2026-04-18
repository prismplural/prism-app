import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// First-pull PluralKit system profile disclosure.
///
/// Shown once when a user links a PK token for the first time. Presents a
/// per-field checkbox list for the PK system profile ([PKSystem.name],
/// description, tag, avatar_url) so the user can pick which fields should
/// replace Prism's `system_settings` equivalents.
///
/// Behaviour:
/// - Rows whose PK-side value is null/empty are hidden entirely.
/// - When the Prism field is blank/default, the row is pre-checked.
/// - When the Prism field already has a non-default value, the row is
///   unchecked and shows a hint that ticking it will overwrite.
///
/// The caller is responsible for writing the accepted fields back via
/// [PluralKitSyncService.adoptSystemProfile].
class PkSystemProfileDisclosureSheet extends StatefulWidget {
  const PkSystemProfileDisclosureSheet({
    super.key,
    required this.pkSystem,
    required this.currentPrismSettings,
    required this.onConfirm,
    required this.onSkip,
  });

  final PKSystem pkSystem;
  final SystemSettings currentPrismSettings;
  final void Function(Set<PkProfileField> accepted) onConfirm;
  final VoidCallback onSkip;

  @override
  State<PkSystemProfileDisclosureSheet> createState() =>
      _PkSystemProfileDisclosureSheetState();
}

class _PkSystemProfileDisclosureSheetState
    extends State<PkSystemProfileDisclosureSheet> {
  late final Set<PkProfileField> _selected;

  bool get _hasName =>
      widget.pkSystem.name != null && widget.pkSystem.name!.isNotEmpty;
  bool get _hasDescription =>
      widget.pkSystem.description != null &&
          widget.pkSystem.description!.isNotEmpty;
  bool get _hasTag =>
      widget.pkSystem.tag != null && widget.pkSystem.tag!.isNotEmpty;
  bool get _hasAvatar =>
      widget.pkSystem.avatarUrl != null &&
          widget.pkSystem.avatarUrl!.isNotEmpty;

  bool get _prismNameBlank {
    final n = widget.currentPrismSettings.systemName;
    return n == null || n.trim().isEmpty;
  }

  bool get _prismDescriptionBlank {
    final d = widget.currentPrismSettings.systemDescription;
    return d == null || d.trim().isEmpty;
  }

  bool get _prismTagBlank {
    final t = widget.currentPrismSettings.systemTag;
    return t == null || t.trim().isEmpty;
  }

  bool get _prismAvatarBlank =>
      widget.currentPrismSettings.systemAvatarData == null ||
      widget.currentPrismSettings.systemAvatarData!.isEmpty;

  @override
  void initState() {
    super.initState();
    _selected = <PkProfileField>{};
    if (_hasName && _prismNameBlank) _selected.add(PkProfileField.name);
    if (_hasDescription && _prismDescriptionBlank) {
      _selected.add(PkProfileField.description);
    }
    if (_hasTag && _prismTagBlank) _selected.add(PkProfileField.tag);
    if (_hasAvatar && _prismAvatarBlank) _selected.add(PkProfileField.avatar);
  }

  void _toggle(PkProfileField field, bool? value) {
    setState(() {
      if (value == true) {
        _selected.add(field);
      } else {
        _selected.remove(field);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final rows = <Widget>[];
    if (_hasName) {
      rows.add(_row(
        field: PkProfileField.name,
        label: l10n.pkProfileFieldName,
        preview: widget.pkSystem.name!,
        overwrite: !_prismNameBlank,
        l10nHint: l10n.pkProfileFieldOverwriteHint,
        theme: theme,
      ));
    }
    if (_hasDescription) {
      rows.add(_row(
        field: PkProfileField.description,
        label: l10n.pkProfileFieldDescription,
        preview: widget.pkSystem.description!,
        overwrite: !_prismDescriptionBlank,
        l10nHint: l10n.pkProfileFieldOverwriteHint,
        theme: theme,
      ));
    }
    if (_hasTag) {
      rows.add(_row(
        field: PkProfileField.tag,
        label: l10n.pkProfileFieldTag,
        preview: widget.pkSystem.tag!,
        overwrite: !_prismTagBlank,
        l10nHint: l10n.pkProfileFieldOverwriteHint,
        theme: theme,
      ));
    }
    if (_hasAvatar) {
      rows.add(_row(
        field: PkProfileField.avatar,
        label: l10n.pkProfileFieldAvatar,
        preview: widget.pkSystem.avatarUrl!,
        overwrite: !_prismAvatarBlank,
        l10nHint: l10n.pkProfileFieldOverwriteHint,
        theme: theme,
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pkProfileDisclosureTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pkProfileDisclosureSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ...rows,
          const SizedBox(height: 16),
          PrismButton(
            onPressed: () => widget.onConfirm(Set<PkProfileField>.from(_selected)),
            label: l10n.pkProfileDisclosureImport,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          const SizedBox(height: 8),
          PrismButton(
            onPressed: widget.onSkip,
            label: l10n.pkProfileDisclosureSkip,
            tone: PrismButtonTone.subtle,
            expanded: true,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row({
    required PkProfileField field,
    required String label,
    required String preview,
    required bool overwrite,
    required String l10nHint,
    required ThemeData theme,
  }) {
    final subtitle = overwrite
        ? Text(
            l10nHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    return CheckboxListTile(
      key: ValueKey('pk_profile_field_${field.name}'),
      value: _selected.contains(field),
      onChanged: (v) => _toggle(field, v),
      title: Text(label),
      subtitle: subtitle,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }
}
