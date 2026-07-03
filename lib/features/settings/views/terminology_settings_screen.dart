import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/terminology_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_term_choice_grid.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

typedef _SystemTermOption = ({SystemTermPreset? preset, bool custom});

class TerminologySettingsScreen extends ConsumerWidget {
  const TerminologySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsTerminology,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (error, _) =>
            Center(child: Text(context.l10n.errorWithDetail(error))),
        data: (settings) => ListView(
          padding: EdgeInsets.only(top: 16, bottom: NavBarInset.of(context)),
          children: [
            PrismSection(
              title: context.l10n.terminologyMemberSectionTitle,
              description: context.l10n.terminologyMemberSectionDescription,
              child: PrismSectionCard(
                child: TerminologyPicker(
                  current: settings.terminology,
                  currentUseEnglish: settings.terminologyUseEnglish,
                  customTerminology: settings.customTerminology,
                  customPluralTerminology: settings.customPluralTerminology,
                ),
              ),
            ),
            PrismSection(
              title: context.l10n.terminologySystemSectionTitle,
              description: context.l10n.terminologySystemSectionDescription,
              child: const PrismSectionCard(child: SystemTerminologyPicker()),
            ),
          ],
        ),
      ),
    );
  }
}

class SystemTerminologyPicker extends ConsumerStatefulWidget {
  const SystemTerminologyPicker({super.key});

  @override
  ConsumerState<SystemTerminologyPicker> createState() =>
      _SystemTerminologyPickerState();
}

class _SystemTerminologyPickerState
    extends ConsumerState<SystemTerminologyPicker> {
  final _singularController = TextEditingController();
  final _pluralController = TextEditingController();

  bool _initialized = false;
  bool _useCustom = false;
  SystemTermPreset? _selectedPreset;
  SystemTermPreset? _desiredPreset;
  bool _desiredUseCustom = false;
  bool _dirty = false;
  bool _suppressNextResetReload = false;
  int _selectionGeneration = 0;
  String? _errorText;

  @override
  void dispose() {
    _singularController.dispose();
    _pluralController.dispose();
    super.dispose();
  }

  void _loadStored(SystemTerms? terms, {required bool notify}) {
    void update() {
      final normalized = terms?.normalized() ?? SystemTerms.unset;
      final hasCustom =
          normalized.preset == null &&
          const SystemTermsPreferenceCodec().isValid(normalized);
      _useCustom = hasCustom;
      _selectedPreset = normalized.preset;
      if (_selectionGeneration == 0) {
        _desiredUseCustom = hasCustom;
        _desiredPreset = normalized.preset;
      }
      _singularController.text = hasCustom ? normalized.singular! : '';
      _pluralController.text = hasCustom ? normalized.plural! : '';
      _dirty = false;
      _suppressNextResetReload = false;
      _errorText = null;
      _initialized = true;
    }

    if (notify && mounted) {
      setState(update);
    } else {
      update();
    }
  }

  void _markDirty() {
    setState(() {
      _dirty = true;
      _errorText = null;
    });
  }

  void _selectSystemChoice(_SystemTermOption option) {
    final generation = ++_selectionGeneration;
    _desiredUseCustom = option.custom;
    _desiredPreset = option.preset;
    setState(() {
      _useCustom = option.custom;
      _selectedPreset = option.preset;
      _errorText = null;
      if (!option.custom) {
        _singularController.clear();
        _pluralController.clear();
        _dirty = false;
      }
    });

    if (option.custom) return;

    _suppressNextResetReload = true;
    unawaited(_persistSystemChoice(option, generation));
  }

  Future<void> _persistSystemChoice(
    _SystemTermOption option,
    int generation,
  ) async {
    if (option.preset == null) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .resetSystemTerminology();
    } else {
      await ref
          .read(settingsNotifierProvider.notifier)
          .updateSystemTerminologyPreset(option.preset!);
    }

    if (!mounted || generation == _selectionGeneration || _desiredUseCustom) {
      return;
    }

    final currentPreset = _desiredPreset;
    if (currentPreset != null) {
      setState(() {
        _useCustom = false;
        _selectedPreset = currentPreset;
      });
      await ref
          .read(settingsNotifierProvider.notifier)
          .updateSystemTerminologyPreset(currentPreset);
    }
  }

  Future<void> _saveCustom() async {
    final l10n = context.l10n;
    final singular = _singularController.text.trim();
    final plural = _pluralController.text.trim();
    if (singular.isEmpty || plural.isEmpty) {
      setState(() {
        _errorText = l10n.terminologySystemCustomRequired;
      });
      return;
    }
    if (singular.length > systemTermMaxLength ||
        plural.length > systemTermMaxLength) {
      setState(() {
        _errorText = l10n.terminologySystemCustomTooLong(systemTermMaxLength);
      });
      return;
    }

    await ref
        .read(settingsNotifierProvider.notifier)
        .updateSystemTerminology(singular: singular, plural: plural);
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(systemTermsSettingProvider);
    final notifierState = ref.watch(settingsNotifierProvider);
    final terms = watchFullTerminology(context, ref);
    if (!_initialized && !_dirty) {
      _loadStored(stored, notify: false);
    }
    ref.listen<SystemTerms?>(systemTermsSettingProvider, (previous, next) {
      if (_suppressNextResetReload && next == null) {
        _suppressNextResetReload = false;
        return;
      }
      _suppressNextResetReload = false;
      if (!_dirty) _loadStored(next, notify: true);
    });

    final theme = Theme.of(context);
    final selectedPresetTerms = _selectedPreset == null
        ? null
        : resolveSystemTermPreset(context.l10n, _selectedPreset!);
    final previewSystemSingular = _useCustom
        ? _capFirst(
            _singularController.text.trim().isEmpty
                ? terms.systemSingular
                : _singularController.text.trim(),
          )
        : selectedPresetTerms?.singular ?? terms.systemSingular;
    final previewSystemLower = previewSystemSingular.toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrismTermChoiceGrid<_SystemTermOption>(
          selected: _useCustom
              ? (preset: null, custom: true)
              : (preset: _selectedPreset, custom: false),
          choices: [
            PrismTermChoice<_SystemTermOption>(
              value: (preset: null, custom: false),
              label: context.l10n.terminologySystemDefaultSingular,
            ),
            for (final preset in systemTermPresetChoices)
              PrismTermChoice<_SystemTermOption>(
                value: (preset: preset, custom: false),
                label: resolveSystemTermPreset(context.l10n, preset).singular,
              ),
            PrismTermChoice<_SystemTermOption>(
              value: (preset: null, custom: true),
              label: context.l10n.terminologySystemModeCustom,
            ),
          ],
          onSelected: _selectSystemChoice,
        ),
        if (_useCustom) ...[
          const SizedBox(height: 12),
          PrismTextField(
            controller: _singularController,
            labelText: context.l10n.terminologySystemCustomSingularLabel,
            hintText: context.l10n.terminologySystemCustomSingularHint,
            errorText: _errorText,
            maxLength: systemTermMaxLength,
            isDense: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _markDirty(),
            onSubmitted: (_) => unawaited(_saveCustom()),
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: _pluralController,
            labelText: context.l10n.terminologySystemCustomPluralLabel,
            hintText: context.l10n.terminologySystemCustomPluralHint,
            maxLength: systemTermMaxLength,
            isDense: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => _markDirty(),
            onSubmitted: (_) => unawaited(_saveCustom()),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PrismButton(
              label: context.l10n.save,
              icon: AppIcons.check,
              density: PrismControlDensity.compact,
              tone: PrismButtonTone.filled,
              enabled: _dirty,
              isLoading: notifierState.isLoading,
              onPressed: () => unawaited(_saveCustom()),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.settingsTerminologyPreviewLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.terminologySystemPreview(
                  previewSystemSingular,
                  previewSystemLower,
                  terms.singularLower,
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _capFirst(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
