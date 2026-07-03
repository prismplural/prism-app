import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/terminology_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_term_choice_grid.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

typedef _SystemTermOption = ({SystemTermPreset? preset, bool custom});
typedef _FrontingTermOption = ({FrontingTermPreset? preset, bool custom});

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
            PrismSection(
              title: context.l10n.terminologyFrontingSectionTitle,
              description: context.l10n.terminologyFrontingSectionDescription,
              child: const PrismSectionCard(child: FrontingTerminologyPicker()),
            ),
          ],
        ),
      ),
    );
  }
}

class FrontingTerminologyPicker extends ConsumerStatefulWidget {
  const FrontingTerminologyPicker({super.key});

  @override
  ConsumerState<FrontingTerminologyPicker> createState() =>
      _FrontingTerminologyPickerState();
}

class _FrontingTerminologyPickerState
    extends ConsumerState<FrontingTerminologyPicker> {
  late final Map<String, TextEditingController> _controllers = {
    for (final key in FrontingTermBundle.fieldKeys)
      key: TextEditingController(),
  };

  bool _initialized = false;
  bool _useCustom = false;
  FrontingTermPreset _selectedPreset = FrontingTermPreset.fronting;
  FrontingTermPreset _desiredPreset = FrontingTermPreset.fronting;
  bool _desiredUseCustom = false;
  bool _dirty = false;
  bool _suppressNextResetReload = false;
  int _selectionGeneration = 0;
  String? _errorText;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setControllersFromBundle(FrontingTermBundle bundle) {
    final values = bundle.toJson();
    for (final key in FrontingTermBundle.fieldKeys) {
      _controllers[key]!.text = values[key] as String;
    }
  }

  void _loadStored(FrontingTerms? terms, {required bool notify}) {
    void update() {
      final normalized = terms?.normalized() ?? FrontingTerms.unset;
      final custom = normalized.custom;
      final hasCustom = custom != null && custom.isValid;
      final preset = normalized.preset ?? FrontingTermPreset.fronting;
      _useCustom = hasCustom;
      _selectedPreset = preset;
      if (_selectionGeneration == 0) {
        _desiredUseCustom = hasCustom;
        _desiredPreset = preset;
      }
      _setControllersFromBundle(
        hasCustom ? custom : frontingTermBundleForPreset(preset),
      );
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

  FrontingTermBundle? _bundleFromControllers() {
    final values = <String, String>{
      for (final key in FrontingTermBundle.fieldKeys)
        key: _controllers[key]!.text.trim(),
    };
    return FrontingTermBundle.tryDecode(values);
  }

  FrontingTermBundle _previewBundle() {
    if (_useCustom) {
      return _bundleFromControllers() ??
          frontingTermBundleForPreset(_selectedPreset);
    }
    return frontingTermBundleForPreset(_selectedPreset);
  }

  void _selectFrontingChoice(_FrontingTermOption option) {
    final generation = ++_selectionGeneration;
    _desiredUseCustom = option.custom;
    _desiredPreset = option.preset ?? FrontingTermPreset.fronting;
    final nextBundle = _previewBundle();

    setState(() {
      _useCustom = option.custom;
      _selectedPreset = _desiredPreset;
      _errorText = null;
      if (option.custom) {
        _setControllersFromBundle(nextBundle);
        _dirty = false;
      } else {
        _setControllersFromBundle(frontingTermBundleForPreset(_selectedPreset));
        _dirty = false;
      }
    });

    if (option.custom) return;

    _suppressNextResetReload = true;
    unawaited(_persistFrontingChoice(_selectedPreset, generation));
  }

  Future<void> _persistFrontingChoice(
    FrontingTermPreset preset,
    int generation,
  ) async {
    if (preset == FrontingTermPreset.fronting) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .resetFrontingTerminology();
    } else {
      await ref
          .read(settingsNotifierProvider.notifier)
          .updateFrontingTerminologyPreset(preset);
    }

    if (!mounted || generation == _selectionGeneration || _desiredUseCustom) {
      return;
    }

    final currentPreset = _desiredPreset;
    setState(() {
      _useCustom = false;
      _selectedPreset = currentPreset;
      _setControllersFromBundle(frontingTermBundleForPreset(currentPreset));
    });
    if (currentPreset == FrontingTermPreset.fronting) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .resetFrontingTerminology();
    } else {
      await ref
          .read(settingsNotifierProvider.notifier)
          .updateFrontingTerminologyPreset(currentPreset);
    }
  }

  Future<void> _saveCustom() async {
    final values = <String, String>{
      for (final key in FrontingTermBundle.fieldKeys)
        key: _controllers[key]!.text.trim(),
    };
    if (values.values.any((value) => value.isEmpty)) {
      setState(() {
        _errorText = context.l10n.terminologyFrontingCustomRequired;
      });
      return;
    }
    if (values.values.any((value) => value.length > frontingTermMaxLength)) {
      setState(() {
        _errorText = context.l10n.terminologyFrontingCustomTooLong(
          frontingTermMaxLength,
        );
      });
      return;
    }

    final bundle = FrontingTermBundle.tryDecode(values);
    if (bundle == null) {
      setState(() {
        _errorText = context.l10n.terminologyFrontingCustomRequired;
      });
      return;
    }

    await ref
        .read(settingsNotifierProvider.notifier)
        .updateFrontingTerminologyCustom(bundle);
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(frontingTermsSettingProvider);
    final notifierState = ref.watch(settingsNotifierProvider);
    if (!_initialized && !_dirty) {
      _loadStored(stored, notify: false);
    }
    ref.listen<FrontingTerms?>(frontingTermsSettingProvider, (previous, next) {
      if (_suppressNextResetReload && next == null) {
        _suppressNextResetReload = false;
        return;
      }
      _suppressNextResetReload = false;
      if (!_dirty) _loadStored(next, notify: true);
    });

    final theme = Theme.of(context);
    final preview = _previewBundle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrismTermChoiceGrid<_FrontingTermOption>(
          density: PrismTermChoiceGridDensity.compact,
          selected: _useCustom
              ? (preset: null, custom: true)
              : (preset: _selectedPreset, custom: false),
          choices: [
            for (final preset in frontingTermPresetChoices)
              PrismTermChoice<_FrontingTermOption>(
                value: (preset: preset, custom: false),
                label: frontingTermPresetChoiceLabel(preset),
                subtitle: frontingTermBundleForPreset(preset).activePluralLabel,
              ),
            PrismTermChoice<_FrontingTermOption>(
              value: (preset: null, custom: true),
              label: context.l10n.terminologySystemModeCustom,
              subtitle: context.l10n.terminologyFrontingCustomSubtitle,
            ),
          ],
          onSelected: _selectFrontingChoice,
        ),
        if (_useCustom) ...[
          const SizedBox(height: 16),
          Text(
            context.l10n.terminologyFrontingCustomIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final (index, group) in _frontingTermGroups(
            context,
          ).indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            PrismExpandableSection(
              initiallyExpanded: index == 0,
              dense: true,
              fillColor: Colors.transparent,
              borderColor: theme.colorScheme.outlineVariant.withValues(
                alpha: 0.35,
              ),
              headerPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              contentSpacing: 10,
              title: Text(group.title),
              subtitle: Text(group.subtitle),
              children: [
                for (final field in group.fields)
                  PrismTextField(
                    controller: _controllers[field.key],
                    labelText: field.label,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(frontingTermMaxLength),
                    ],
                    isDense: true,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _markDirty(),
                    onSubmitted: (_) => unawaited(_saveCustom()),
                  ),
              ],
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
                context.l10n.terminologyFrontingPreview(
                  preview.currentQuestionNow,
                  preview.activePluralLabel,
                  preview.logAction,
                  preview.historyLabel,
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
          density: PrismTermChoiceGridDensity.compact,
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

final class _FrontingTermField {
  const _FrontingTermField(this.key, this.label);

  final String key;
  final String label;
}

final class _FrontingTermFieldGroup {
  const _FrontingTermFieldGroup({
    required this.title,
    required this.subtitle,
    required this.fields,
  });

  final String title;
  final String subtitle;
  final List<_FrontingTermField> fields;
}

List<_FrontingTermFieldGroup> _frontingTermGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupPrimary,
      subtitle: l10n.terminologyFrontingGroupPrimarySubtitle,
      fields: const [
        _FrontingTermField('featureLabel', 'Feature label'),
        _FrontingTermField('featureLower', 'Feature label, lowercase'),
        _FrontingTermField('currentQuestion', 'Current question'),
        _FrontingTermField('currentQuestionNow', 'Current question now'),
        _FrontingTermField('emptyCurrentState', 'Empty current state'),
        _FrontingTermField('activeSingularLabel', 'Active singular label'),
        _FrontingTermField('activePluralLabel', 'Active plural label'),
        _FrontingTermField('activeSectionLabel', 'Active section label'),
        _FrontingTermField('currentActiveLabel', 'Current active label'),
        _FrontingTermField('latestActiveLabel', 'Latest active label'),
        _FrontingTermField('unknownActiveLabel', 'Unknown active label'),
        _FrontingTermField('currentlyActivePhrase', 'Currently active phrase'),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupActions,
      subtitle: l10n.terminologyFrontingGroupActionsSubtitle,
      fields: const [
        _FrontingTermField('logAction', 'Log action'),
        _FrontingTermField('logPastAction', 'Log past action'),
        _FrontingTermField('quickAction', 'Quick action'),
        _FrontingTermField('holdToStartHint', 'Hold-to-start hint'),
        _FrontingTermField('addAction', 'Add action'),
        _FrontingTermField('setAsAction', 'Set-as action'),
        _FrontingTermField('replaceCurrentAction', 'Replace current action'),
        _FrontingTermField('endWithoutAction', 'End without action'),
        _FrontingTermField('endCurrentAction', 'End current action'),
        _FrontingTermField('keepCurrentAction', 'Keep current action'),
        _FrontingTermField('directButtonLabel', 'Direct button label'),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupHistory,
      subtitle: l10n.terminologyFrontingGroupHistorySubtitle,
      fields: const [
        _FrontingTermField('historyLabel', 'History label'),
        _FrontingTermField('dataLabel', 'Data label'),
        _FrontingTermField('entryLabel', 'Entry label'),
        _FrontingTermField('sessionSingular', 'Session singular'),
        _FrontingTermField('sessionPlural', 'Session plural'),
        _FrontingTermField('sessionCommentSingular', 'Session comment'),
        _FrontingTermField('sessionCommentPlural', 'Session comments'),
        _FrontingTermField('statsLabel', 'Stats label'),
        _FrontingTermField('timeLabel', 'Time label'),
        _FrontingTermField('lastActiveLabel', 'Last active label'),
        _FrontingTermField('mostActiveSortLabel', 'Most active sort label'),
        _FrontingTermField('leastActiveSortLabel', 'Least active sort label'),
        _FrontingTermField('statusLabel', 'Status label'),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupTogether,
      subtitle: l10n.terminologyFrontingGroupTogetherSubtitle,
      fields: const [
        _FrontingTermField('togetherStateLabel', 'Together state label'),
        _FrontingTermField(
          'togetherActiveSingularLabel',
          'Together active singular',
        ),
        _FrontingTermField(
          'togetherActivePluralLabel',
          'Together active plural',
        ),
        _FrontingTermField('togetherPastLabel', 'Together past label'),
        _FrontingTermField('addTogetherAction', 'Add together action'),
        _FrontingTermField('overlapOptionLabel', 'Overlap option label'),
        _FrontingTermField('overlapSubtitle', 'Overlap subtitle'),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupChanges,
      subtitle: l10n.terminologyFrontingGroupChangesSubtitle,
      fields: const [
        _FrontingTermField('changeSingular', 'Change singular'),
        _FrontingTermField('changePlural', 'Change plural'),
        _FrontingTermField('anyChangeLabel', 'Any change label'),
        _FrontingTermField('onChangeLabel', 'On-change label'),
        _FrontingTermField('delayAfterChangeLabel', 'Delay label'),
        _FrontingTermField('reminderLabel', 'Reminder label'),
        _FrontingTermField('logChangeReminderAction', 'Reminder action'),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupPinned,
      subtitle: l10n.terminologyFrontingGroupPinnedSubtitle,
      fields: const [
        _FrontingTermField('alwaysActiveLabel', 'Always active label'),
        _FrontingTermField('alwaysPresentHeaderLabel', 'Always present header'),
        _FrontingTermField('longRunningLabel', 'Long-running label'),
        _FrontingTermField('longRunningHeaderLabel', 'Long-running header'),
        _FrontingTermField('quickCorrectionLabel', 'Quick correction label'),
        _FrontingTermField(
          'quickCorrectionWindowTitle',
          'Quick correction window',
        ),
        _FrontingTermField('switchEventLabel', 'Switch event label'),
      ],
    ),
  ];
}
