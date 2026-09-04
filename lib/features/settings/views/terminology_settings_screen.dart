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
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_term_choice_grid.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

typedef _SystemTermOption = ({SystemTermPreset? preset, bool custom});
typedef _FrontingTermOption = ({FrontingTermPreset? preset, bool custom});

enum _FrontingEditorMode { simple, advanced }

const _simpleFrontingFieldKeys = [
  'featureLabel',
  'activeSectionLabel',
  'statePhrase',
  'activeSingularLabel',
  'activePluralLabel',
  'sessionSingular',
  'sessionPlural',
];

const _terminologyAutosaveDelay = Duration(milliseconds: 300);

final class _PersistenceQueue {
  Future<void>? _tail;

  Future<void> add(Future<void> Function() action) {
    final previous = _tail;
    late final Future<void> result;
    if (previous == null) {
      try {
        result = action();
      } catch (error, stackTrace) {
        result = Future<void>.error(error, stackTrace);
      }
    } else {
      result = previous.then((_) => action());
    }
    final settled = result.then<void>((_) {}, onError: (_, _) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return result;
  }
}

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
  late final Map<String, TextEditingController> _simpleControllers = {
    for (final key in _simpleFrontingFieldKeys) key: TextEditingController(),
  };

  bool _initialized = false;
  bool _useCustom = false;
  FrontingTermPreset _selectedPreset = FrontingTermPreset.fronting;
  FrontingTermPreset _desiredPreset = FrontingTermPreset.fronting;
  bool _desiredUseCustom = false;
  bool _dirty = false;
  bool _advancedDirty = false;
  bool _simpleAvailable = false;
  _FrontingEditorMode _editorMode = _FrontingEditorMode.simple;
  String _authoringLocale = 'en';
  FrontingTermPreset _authoringSeedPreset = FrontingTermPreset.fronting;
  bool _suppressNextResetReload = false;
  int _selectionGeneration = 0;
  int _customSaveGeneration = 0;
  FrontingTerms? _ignoredStoredEcho;
  FrontingTerms? _customDraft;
  Timer? _customSaveDebounce;
  final _persistenceQueue = _PersistenceQueue();
  late final SettingsNotifier _settingsNotifier;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _settingsNotifier = ref.read(settingsNotifierProvider.notifier);
  }

  @override
  void dispose() {
    _customSaveDebounce?.cancel();
    _persistCustomOnDispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _simpleControllers.values) {
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

  void _setSimpleControllers(SimpleFrontingTermAuthoring authoring) {
    final values = {
      'featureLabel': authoring.featureLabel,
      'activeSectionLabel': authoring.activeSectionLabel,
      'statePhrase': authoring.statePhrase,
      'activeSingularLabel': authoring.activeSingularLabel,
      'activePluralLabel': authoring.activePluralLabel,
      'sessionSingular': authoring.sessionSingular,
      'sessionPlural': authoring.sessionPlural,
    };
    for (final key in _simpleFrontingFieldKeys) {
      _simpleControllers[key]!.text = values[key]!;
    }
    _authoringLocale = authoring.locale;
    _authoringSeedPreset = authoring.seedPreset;
  }

  SimpleFrontingTermAuthoring _simpleAuthoringFromControllers() {
    return SimpleFrontingTermAuthoring(
      locale: _authoringLocale,
      seedPreset: _authoringSeedPreset,
      featureLabel: _simpleControllers['featureLabel']!.text.trim(),
      activeSectionLabel: _simpleControllers['activeSectionLabel']!.text.trim(),
      statePhrase: _simpleControllers['statePhrase']!.text.trim(),
      activeSingularLabel: _simpleControllers['activeSingularLabel']!.text
          .trim(),
      activePluralLabel: _simpleControllers['activePluralLabel']!.text.trim(),
      sessionSingular: _simpleControllers['sessionSingular']!.text.trim(),
      sessionPlural: _simpleControllers['sessionPlural']!.text.trim(),
    );
  }

  void _startSimpleSetup(FrontingTermPreset preset, {required bool dirty}) {
    final authoring = simpleFrontingAuthoringForPreset(context.l10n, preset);
    _setSimpleControllers(authoring);
    _setControllersFromBundle(generateSimpleFrontingBundle(authoring));
    _simpleAvailable = true;
    _editorMode = _FrontingEditorMode.simple;
    _advancedDirty = false;
    _dirty = dirty;
    _errorText = null;
  }

  void _restoreCustomDraft(FrontingTerms draft) {
    final normalized = draft.normalized();
    final custom = normalized.custom;
    if (custom == null) return;
    _setControllersFromBundle(custom);
    if (normalized.authoring case final authoring?) {
      _setSimpleControllers(authoring);
    }
    _customDraft = FrontingTerms.custom(
      custom,
      authoring: normalized.authoring,
    );
    _simpleAvailable = normalized.authoring != null;
    _editorMode = _simpleAvailable
        ? _FrontingEditorMode.simple
        : _FrontingEditorMode.advanced;
    _advancedDirty = false;
    _dirty = false;
    _errorText = null;
  }

  void _startSimpleSetupFromAdvanced() {
    _customSaveDebounce?.cancel();
    _customSaveDebounce = null;
    if (_dirty && _useCustom) {
      _ignoredStoredEcho = _currentCustomTerms();
      final generation = ++_customSaveGeneration;
      unawaited(_saveCustom(generation: generation));
    }
    ++_customSaveGeneration;
    setState(() {
      _startSimpleSetup(FrontingTermPreset.fronting, dirty: false);
    });
  }

  void _loadStored(FrontingTerms? terms, {required bool notify}) {
    void update() {
      final normalized = terms?.normalized() ?? FrontingTerms.unset;
      final custom = normalized.custom;
      final customDraft = custom == null
          ? null
          : FrontingTerms.custom(custom, authoring: normalized.authoring);
      final hasCustom = normalized.preset == null && customDraft != null;
      final authoring = normalized.authoring;
      final preset = normalized.preset ?? FrontingTermPreset.fronting;
      _useCustom = hasCustom;
      _selectedPreset = preset;
      if (_selectionGeneration == 0) {
        _desiredUseCustom = hasCustom;
        _desiredPreset = preset;
      }
      _setControllersFromBundle(
        customDraft?.custom ??
            frontingTermBundleForPreset(context.l10n, preset),
      );
      _customDraft = customDraft;
      _simpleAvailable = hasCustom && authoring != null;
      _editorMode = _simpleAvailable
          ? _FrontingEditorMode.simple
          : _FrontingEditorMode.advanced;
      if (authoring != null) _setSimpleControllers(authoring);
      _dirty = false;
      _advancedDirty = false;
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

  void _markAdvancedDirty() {
    setState(() {
      _dirty = true;
      _advancedDirty = true;
      _simpleAvailable = false;
      _errorText = null;
    });
    _scheduleCustomSave();
  }

  void _markSimpleDirty() {
    setState(() {
      _dirty = true;
      _advancedDirty = false;
      _errorText = null;
      final authoring = _simpleAuthoringFromControllers();
      if (authoring.isValid) {
        _setControllersFromBundle(generateSimpleFrontingBundle(authoring));
      }
    });
    _scheduleCustomSave();
  }

  void _scheduleCustomSave() {
    _customSaveDebounce?.cancel();
    final generation = ++_customSaveGeneration;
    _customSaveDebounce = Timer(_terminologyAutosaveDelay, () {
      _customSaveDebounce = null;
      unawaited(_saveCustom(generation: generation));
    });
  }

  void _submitCustomSave() {
    _customSaveDebounce?.cancel();
    _customSaveDebounce = null;
    final generation = ++_customSaveGeneration;
    unawaited(_saveCustom(generation: generation));
  }

  FrontingTermBundle? _bundleFromControllers() {
    final values = <String, String>{
      for (final key in FrontingTermBundle.fieldKeys)
        key: _controllers[key]!.text.trim(),
    };
    return FrontingTermBundle.tryDecode(values);
  }

  FrontingTerms? _currentCustomTerms() {
    if (!_useCustom) return null;
    SimpleFrontingTermAuthoring? authoring;
    FrontingTermBundle? bundle;
    if (_editorMode == _FrontingEditorMode.simple) {
      authoring = _simpleAuthoringFromControllers().normalized();
      if (!authoring.isValid) return null;
      bundle = generateSimpleFrontingBundle(authoring);
    } else {
      bundle = _bundleFromControllers();
      if (_simpleAvailable && !_advancedDirty) {
        final candidate = _simpleAuthoringFromControllers().normalized();
        if (candidate.isValid) authoring = candidate;
      }
    }
    if (bundle == null) return null;
    return FrontingTerms.custom(bundle, authoring: authoring).normalized();
  }

  FrontingTerms? _customDraftForStorage() {
    final current = _currentCustomTerms();
    if (current != null) return current;
    final stored = _customDraft?.normalized();
    final custom = stored?.custom;
    if (custom == null) return null;
    return FrontingTerms.custom(custom, authoring: stored!.authoring);
  }

  FrontingTermBundle _previewBundle() {
    if (_useCustom) {
      if (_editorMode == _FrontingEditorMode.simple) {
        final authoring = _simpleAuthoringFromControllers();
        if (authoring.isValid) return generateSimpleFrontingBundle(authoring);
      }
      return _bundleFromControllers() ??
          frontingTermBundleForPreset(context.l10n, _selectedPreset);
    }
    return frontingTermBundleForPreset(context.l10n, _selectedPreset);
  }

  void _selectFrontingChoice(_FrontingTermOption option) {
    if (option.custom && _useCustom) return;

    _customSaveDebounce?.cancel();
    _customSaveDebounce = null;
    ++_customSaveGeneration;
    final customDraft = _customDraftForStorage();
    final generation = ++_selectionGeneration;
    final customSeedPreset = _selectedPreset;
    _desiredUseCustom = option.custom;
    _desiredPreset = option.custom
        ? customSeedPreset
        : option.preset ?? FrontingTermPreset.fronting;

    setState(() {
      _useCustom = option.custom;
      _selectedPreset = _desiredPreset;
      _errorText = null;
      if (option.custom) {
        if (customDraft != null) {
          _restoreCustomDraft(customDraft);
        } else {
          _startSimpleSetup(customSeedPreset, dirty: false);
        }
      } else {
        _customDraft = customDraft;
        if (customDraft == null) {
          _setControllersFromBundle(
            frontingTermBundleForPreset(context.l10n, _selectedPreset),
          );
        }
        _dirty = false;
        _advancedDirty = false;
        _simpleAvailable = false;
      }
    });

    if (option.custom) return;

    _suppressNextResetReload = true;
    unawaited(_persistFrontingChoice(_selectedPreset, generation, customDraft));
  }

  Future<void> _persistFrontingChoice(
    FrontingTermPreset preset,
    int generation,
    FrontingTerms? customDraft,
  ) async {
    final notifier = _settingsNotifier;
    if (preset == FrontingTermPreset.fronting && customDraft == null) {
      await _persistenceQueue.add(notifier.resetFrontingTerminology);
    } else {
      await _persistenceQueue.add(
        () => notifier.updateFrontingTerminologyPreset(
          preset,
          custom: customDraft?.custom,
          authoring: customDraft?.authoring,
        ),
      );
    }

    if (!mounted || generation == _selectionGeneration || _desiredUseCustom) {
      return;
    }

    final currentPreset = _desiredPreset;
    setState(() {
      _useCustom = false;
      _selectedPreset = currentPreset;
      final currentCustomDraft = _customDraftForStorage();
      _customDraft = currentCustomDraft;
      if (currentCustomDraft == null) {
        _setControllersFromBundle(
          frontingTermBundleForPreset(context.l10n, currentPreset),
        );
      }
    });
    final currentCustomDraft = _customDraftForStorage();
    if (currentPreset == FrontingTermPreset.fronting &&
        currentCustomDraft == null) {
      await _persistenceQueue.add(notifier.resetFrontingTerminology);
    } else {
      await _persistenceQueue.add(
        () => notifier.updateFrontingTerminologyPreset(
          currentPreset,
          custom: currentCustomDraft?.custom,
          authoring: currentCustomDraft?.authoring,
        ),
      );
    }
  }

  Future<void> _saveCustom({required int generation}) async {
    SimpleFrontingTermAuthoring? authoring;
    if (_editorMode == _FrontingEditorMode.simple) {
      authoring = _simpleAuthoringFromControllers().normalized();
      if (!authoring.isValid) {
        if (mounted && generation == _customSaveGeneration) {
          setState(() {
            _errorText = context.l10n.terminologyFrontingSimpleRequired;
          });
        }
        return;
      }
      _setControllersFromBundle(generateSimpleFrontingBundle(authoring));
    } else if (_simpleAvailable && !_advancedDirty) {
      final candidate = _simpleAuthoringFromControllers().normalized();
      if (candidate.isValid) authoring = candidate;
    }
    final values = <String, String>{
      for (final key in FrontingTermBundle.fieldKeys)
        key: _controllers[key]!.text.trim(),
    };
    if (values.values.any((value) => value.isEmpty)) {
      if (mounted && generation == _customSaveGeneration) {
        setState(() {
          _errorText = context.l10n.terminologyFrontingCustomRequired;
        });
      }
      return;
    }
    if (values.values.any((value) => value.length > frontingTermMaxLength)) {
      if (mounted && generation == _customSaveGeneration) {
        setState(() {
          _errorText = context.l10n.terminologyFrontingCustomTooLong(
            frontingTermMaxLength,
          );
        });
      }
      return;
    }

    final bundle = FrontingTermBundle.tryDecode(values);
    if (bundle == null) {
      if (mounted && generation == _customSaveGeneration) {
        setState(() {
          _errorText = context.l10n.terminologyFrontingCustomRequired;
        });
      }
      return;
    }

    final notifier = _settingsNotifier;
    final customTerms = FrontingTerms.custom(
      bundle,
      authoring: authoring,
    ).normalized();
    await _persistenceQueue.add(
      () => notifier.updateFrontingTerminologyCustom(
        bundle,
        authoring: authoring,
      ),
    );
    if (!mounted || generation != _customSaveGeneration || !_desiredUseCustom) {
      return;
    }
    setState(() {
      _customDraft = customTerms;
      _dirty = false;
      _advancedDirty = false;
      _simpleAvailable = authoring != null;
      _errorText = null;
    });
  }

  void _persistCustomOnDispose() {
    if (!_dirty || !_useCustom) return;
    SimpleFrontingTermAuthoring? authoring;
    if (_editorMode == _FrontingEditorMode.simple) {
      authoring = _simpleAuthoringFromControllers().normalized();
      if (!authoring.isValid) return;
      _setControllersFromBundle(generateSimpleFrontingBundle(authoring));
    } else if (_simpleAvailable && !_advancedDirty) {
      final candidate = _simpleAuthoringFromControllers().normalized();
      if (candidate.isValid) authoring = candidate;
    }
    final bundle = _bundleFromControllers();
    if (bundle == null) return;
    final notifier = _settingsNotifier;
    unawaited(
      _persistenceQueue.add(
        () => notifier.updateFrontingTerminologyCustom(
          bundle,
          authoring: authoring,
        ),
      ),
    );
  }

  void _selectEditorMode(_FrontingEditorMode mode) {
    if (mode == _editorMode) return;
    if (mode == _FrontingEditorMode.simple && !_simpleAvailable) return;
    setState(() {
      if (mode == _FrontingEditorMode.advanced) {
        final authoring = _simpleAuthoringFromControllers();
        if (authoring.isValid) {
          _setControllersFromBundle(generateSimpleFrontingBundle(authoring));
        }
      }
      _editorMode = mode;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(frontingTermsSettingProvider);
    if (!_initialized && !_dirty) {
      _loadStored(stored, notify: false);
    }
    ref.listen<FrontingTerms?>(frontingTermsSettingProvider, (previous, next) {
      final ignoredEcho = _ignoredStoredEcho;
      if (ignoredEcho != null) {
        if (next?.normalized() != ignoredEcho) return;
        _ignoredStoredEcho = null;
        return;
      }
      final currentCustom = _currentCustomTerms();
      if (currentCustom != null && next?.normalized() == currentCustom) return;
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
                label: frontingTermPresetChoiceLabel(context.l10n, preset),
                subtitle: frontingTermBundleForPreset(
                  context.l10n,
                  preset,
                ).activePluralLabel,
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
          if (_simpleAvailable)
            PrismSegmentedControl<_FrontingEditorMode>(
              segments: [
                PrismSegment(
                  value: _FrontingEditorMode.simple,
                  label: context.l10n.terminologyFrontingModeSimple,
                ),
                PrismSegment(
                  value: _FrontingEditorMode.advanced,
                  label: context.l10n.terminologyFrontingModeAdvanced,
                ),
              ],
              selected: _editorMode,
              onChanged: _selectEditorMode,
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PrismButton(
                label: context.l10n.terminologyFrontingStartSimple,
                icon: AppIcons.tuneOutlined,
                density: PrismControlDensity.compact,
                onPressed: _startSimpleSetupFromAdvanced,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            _editorMode == _FrontingEditorMode.simple
                ? context.l10n.terminologyFrontingSimpleIntro
                : context.l10n.terminologyFrontingCustomIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_editorMode == _FrontingEditorMode.simple) ...[
            for (final key in _simpleFrontingFieldKeys) ...[
              PrismTextField(
                key: ValueKey('simple-fronting-$key'),
                controller: _simpleControllers[key],
                labelText: context.l10n.terminologyFrontingSimpleFieldLabel(
                  key,
                ),
                hintText: context.l10n.terminologyFrontingSimpleFieldHint(key),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(simpleFrontingTermMaxLength),
                ],
                isDense: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _markSimpleDirty(),
                onSubmitted: (_) => _submitCustomSave(),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              context.l10n.terminologyFrontingSimpleRegenerationNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            for (final (index, group) in _frontingTermGroups(
              context,
            ).indexed) ...[
              if (index > 0) const SizedBox(height: 8),
              PrismExpandableSection(
                initiallyExpanded: false,
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
                      onChanged: (_) => _markAdvancedDirty(),
                      onSubmitted: (_) => _submitCustomSave(),
                    ),
                ],
              ),
            ],
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
  int _customSaveGeneration = 0;
  Timer? _customSaveDebounce;
  final _persistenceQueue = _PersistenceQueue();
  late final SettingsNotifier _settingsNotifier;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _settingsNotifier = ref.read(settingsNotifierProvider.notifier);
  }

  @override
  void dispose() {
    _customSaveDebounce?.cancel();
    _persistCustomOnDispose();
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
    _scheduleCustomSave();
  }

  void _scheduleCustomSave() {
    _customSaveDebounce?.cancel();
    final generation = ++_customSaveGeneration;
    _customSaveDebounce = Timer(_terminologyAutosaveDelay, () {
      _customSaveDebounce = null;
      unawaited(_saveCustom(generation: generation));
    });
  }

  void _submitCustomSave() {
    _customSaveDebounce?.cancel();
    _customSaveDebounce = null;
    final generation = ++_customSaveGeneration;
    unawaited(_saveCustom(generation: generation));
  }

  void _selectSystemChoice(_SystemTermOption option) {
    if (option.custom && _useCustom) return;

    _customSaveDebounce?.cancel();
    _customSaveDebounce = null;
    ++_customSaveGeneration;
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
    final notifier = _settingsNotifier;
    if (option.preset == null) {
      await _persistenceQueue.add(notifier.resetSystemTerminology);
    } else {
      await _persistenceQueue.add(
        () => notifier.updateSystemTerminologyPreset(option.preset!),
      );
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
      await _persistenceQueue.add(
        () => notifier.updateSystemTerminologyPreset(currentPreset),
      );
    }
  }

  Future<void> _saveCustom({required int generation}) async {
    final l10n = context.l10n;
    final singular = _singularController.text.trim();
    final plural = _pluralController.text.trim();
    if (singular.isEmpty || plural.isEmpty) {
      if (mounted && generation == _customSaveGeneration) {
        setState(() {
          _errorText = l10n.terminologySystemCustomRequired;
        });
      }
      return;
    }
    if (singular.length > systemTermMaxLength ||
        plural.length > systemTermMaxLength) {
      if (mounted && generation == _customSaveGeneration) {
        setState(() {
          _errorText = l10n.terminologySystemCustomTooLong(systemTermMaxLength);
        });
      }
      return;
    }

    final notifier = _settingsNotifier;
    await _persistenceQueue.add(
      () =>
          notifier.updateSystemTerminology(singular: singular, plural: plural),
    );
    if (!mounted || generation != _customSaveGeneration || !_desiredUseCustom) {
      return;
    }
    setState(() {
      _dirty = false;
      _errorText = null;
    });
  }

  void _persistCustomOnDispose() {
    if (!_dirty || !_useCustom) return;
    final singular = _singularController.text.trim();
    final plural = _pluralController.text.trim();
    if (singular.isEmpty ||
        plural.isEmpty ||
        singular.length > systemTermMaxLength ||
        plural.length > systemTermMaxLength) {
      return;
    }
    final notifier = _settingsNotifier;
    unawaited(
      _persistenceQueue.add(
        () => notifier.updateSystemTerminology(
          singular: singular,
          plural: plural,
        ),
      ),
    );
  }

  bool _matchesCurrentCustomTerms(SystemTerms? terms) {
    if (!_useCustom) return false;
    final current = SystemTerms.custom(
      singular: _singularController.text,
      plural: _pluralController.text,
    ).normalized();
    if (!const SystemTermsPreferenceCodec().isValid(current)) return false;
    return terms?.normalized() == current;
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(systemTermsSettingProvider);
    final terms = watchFullTerminology(context, ref);
    if (!_initialized && !_dirty) {
      _loadStored(stored, notify: false);
    }
    ref.listen<SystemTerms?>(systemTermsSettingProvider, (previous, next) {
      if (_matchesCurrentCustomTerms(next)) return;
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
    final previewSystemTerms = _useCustom
        ? SystemTerms.custom(
            singular: _singularController.text.trim(),
            plural: _pluralController.text.trim(),
          )
        : _selectedPreset == null
        ? SystemTerms.unset
        : SystemTerms.preset(_selectedPreset!);
    final previewInfoLabel = systemInfoLabel(
      context.l10n,
      previewSystemTerms,
      previewSystemSingular,
    );

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
            onSubmitted: (_) => _submitCustomSave(),
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
            onSubmitted: (_) => _submitCustomSave(),
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
                  previewInfoLabel,
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
      fields: [
        for (final key in const [
          'featureLabel',
          'featureLower',
          'currentQuestion',
          'currentQuestionNow',
          'emptyCurrentState',
          'activeSingularLabel',
          'activePluralLabel',
          'activeSectionLabel',
          'currentActiveLabel',
          'latestActiveLabel',
          'unknownActiveLabel',
          'currentlyActivePhrase',
        ])
          _FrontingTermField(key, l10n.terminologyFrontingFieldLabel(key)),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupActions,
      subtitle: l10n.terminologyFrontingGroupActionsSubtitle,
      fields: [
        for (final key in const [
          'logAction',
          'logPastAction',
          'quickAction',
          'holdToStartHint',
          'addAction',
          'setAsAction',
          'replaceCurrentAction',
          'endWithoutAction',
          'endCurrentAction',
          'keepCurrentAction',
          'directButtonLabel',
        ])
          _FrontingTermField(key, l10n.terminologyFrontingFieldLabel(key)),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupHistory,
      subtitle: l10n.terminologyFrontingGroupHistorySubtitle,
      fields: [
        for (final key in const [
          'historyLabel',
          'dataLabel',
          'entryLabel',
          'sessionSingular',
          'sessionPlural',
          'sessionCommentSingular',
          'sessionCommentPlural',
          'statsLabel',
          'timeLabel',
          'lastActiveLabel',
          'mostActiveSortLabel',
          'leastActiveSortLabel',
          'statusLabel',
        ])
          _FrontingTermField(key, l10n.terminologyFrontingFieldLabel(key)),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupTogether,
      subtitle: l10n.terminologyFrontingGroupTogetherSubtitle,
      fields: [
        for (final key in const [
          'togetherStateLabel',
          'togetherActiveSingularLabel',
          'togetherActivePluralLabel',
          'togetherPastLabel',
          'addTogetherAction',
          'overlapOptionLabel',
          'overlapSubtitle',
        ])
          _FrontingTermField(key, l10n.terminologyFrontingFieldLabel(key)),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupChanges,
      subtitle: l10n.terminologyFrontingGroupChangesSubtitle,
      fields: [
        for (final key in const [
          'changeSingular',
          'changePlural',
          'anyChangeLabel',
          'onChangeLabel',
          'delayAfterChangeLabel',
          'reminderLabel',
          'logChangeReminderAction',
        ])
          _FrontingTermField(key, l10n.terminologyFrontingFieldLabel(key)),
      ],
    ),
    _FrontingTermFieldGroup(
      title: l10n.terminologyFrontingGroupPinned,
      subtitle: l10n.terminologyFrontingGroupPinnedSubtitle,
      fields: [
        for (final key in const [
          'alwaysActiveLabel',
          'alwaysPresentHeaderLabel',
          'longRunningLabel',
          'longRunningHeaderLabel',
          'quickCorrectionLabel',
          'quickCorrectionWindowTitle',
          'switchEventLabel',
        ])
          _FrontingTermField(key, l10n.terminologyFrontingFieldLabel(key)),
      ],
    ),
  ];
}
