import 'package:prism_plurality/domain/preferences/preference_codec.dart';

const frontingTermMaxLength = 120;
const simpleFrontingTermMaxLength = 80;

enum FrontingTermPreset { fronting, present, out, online }

final class SimpleFrontingTermAuthoring {
  const SimpleFrontingTermAuthoring({
    required this.locale,
    required this.seedPreset,
    required this.featureLabel,
    required this.activeSectionLabel,
    required this.statePhrase,
    required this.activeSingularLabel,
    required this.activePluralLabel,
    required this.sessionSingular,
    required this.sessionPlural,
  });

  static const version = 1;

  final String locale;
  final FrontingTermPreset seedPreset;
  final String featureLabel;
  final String activeSectionLabel;
  final String statePhrase;
  final String activeSingularLabel;
  final String activePluralLabel;
  final String sessionSingular;
  final String sessionPlural;

  List<String> get _inputValues => [
    featureLabel,
    activeSectionLabel,
    statePhrase,
    activeSingularLabel,
    activePluralLabel,
    sessionSingular,
    sessionPlural,
  ];

  bool get isValid {
    if (locale != 'en' && locale != 'es') return false;
    return _inputValues.every((value) {
      final normalized = value.trim();
      return normalized.isNotEmpty &&
          normalized.length <= simpleFrontingTermMaxLength;
    });
  }

  SimpleFrontingTermAuthoring normalized() {
    return SimpleFrontingTermAuthoring(
      locale: locale,
      seedPreset: seedPreset,
      featureLabel: featureLabel.trim(),
      activeSectionLabel: activeSectionLabel.trim(),
      statePhrase: statePhrase.trim(),
      activeSingularLabel: activeSingularLabel.trim(),
      activePluralLabel: activePluralLabel.trim(),
      sessionSingular: sessionSingular.trim(),
      sessionPlural: sessionPlural.trim(),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': 'simple',
    'version': version,
    'locale': locale,
    'seedPreset': seedPreset.name,
    'inputs': {
      'featureLabel': featureLabel,
      'activeSectionLabel': activeSectionLabel,
      'statePhrase': statePhrase,
      'activeSingularLabel': activeSingularLabel,
      'activePluralLabel': activePluralLabel,
      'sessionSingular': sessionSingular,
      'sessionPlural': sessionPlural,
    },
  };

  static SimpleFrontingTermAuthoring? tryDecode(Object? value) {
    if (value is! Map ||
        value['kind'] != 'simple' ||
        value['version'] != version) {
      return null;
    }
    final locale = value['locale'];
    final seedPresetName = value['seedPreset'];
    final inputs = value['inputs'];
    if (locale is! String || seedPresetName is! String || inputs is! Map) {
      return null;
    }
    final seedPreset = FrontingTermsPreferenceCodec._presetByName(
      seedPresetName,
    );
    if (seedPreset == null) return null;

    String? input(String key) {
      final result = inputs[key];
      return result is String ? result : null;
    }

    final featureLabel = input('featureLabel');
    final activeSectionLabel = input('activeSectionLabel');
    final statePhrase = input('statePhrase');
    final activeSingularLabel = input('activeSingularLabel');
    final activePluralLabel = input('activePluralLabel');
    final sessionSingular = input('sessionSingular');
    final sessionPlural = input('sessionPlural');
    if (featureLabel == null ||
        activeSectionLabel == null ||
        statePhrase == null ||
        activeSingularLabel == null ||
        activePluralLabel == null ||
        sessionSingular == null ||
        sessionPlural == null) {
      return null;
    }
    final authoring = SimpleFrontingTermAuthoring(
      locale: locale,
      seedPreset: seedPreset,
      featureLabel: featureLabel,
      activeSectionLabel: activeSectionLabel,
      statePhrase: statePhrase,
      activeSingularLabel: activeSingularLabel,
      activePluralLabel: activePluralLabel,
      sessionSingular: sessionSingular,
      sessionPlural: sessionPlural,
    ).normalized();
    return authoring.isValid ? authoring : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimpleFrontingTermAuthoring &&
          other.locale == locale &&
          other.seedPreset == seedPreset &&
          other.featureLabel == featureLabel &&
          other.activeSectionLabel == activeSectionLabel &&
          other.statePhrase == statePhrase &&
          other.activeSingularLabel == activeSingularLabel &&
          other.activePluralLabel == activePluralLabel &&
          other.sessionSingular == sessionSingular &&
          other.sessionPlural == sessionPlural;

  @override
  int get hashCode => Object.hash(
    locale,
    seedPreset,
    featureLabel,
    activeSectionLabel,
    statePhrase,
    activeSingularLabel,
    activePluralLabel,
    sessionSingular,
    sessionPlural,
  );
}

final class FrontingTermBundle {
  FrontingTermBundle._(Map<String, String> values)
    : _values = Map.unmodifiable(values);

  factory FrontingTermBundle.fromFields({
    required String featureLabel,
    required String featureLower,
    required String currentQuestion,
    required String currentQuestionNow,
    required String emptyCurrentState,
    required String activeSingularLabel,
    required String activePluralLabel,
    required String activeSectionLabel,
    required String currentActiveLabel,
    required String latestActiveLabel,
    required String unknownActiveLabel,
    required String currentlyActivePhrase,
    required String logAction,
    required String logPastAction,
    required String quickAction,
    required String holdToStartHint,
    required String addAction,
    required String setAsAction,
    required String replaceCurrentAction,
    required String endWithoutAction,
    required String endCurrentAction,
    required String keepCurrentAction,
    required String directButtonLabel,
    required String historyLabel,
    required String dataLabel,
    required String entryLabel,
    required String sessionSingular,
    required String sessionPlural,
    required String sessionCommentSingular,
    required String sessionCommentPlural,
    required String statsLabel,
    required String timeLabel,
    required String lastActiveLabel,
    required String mostActiveSortLabel,
    required String leastActiveSortLabel,
    required String statusLabel,
    required String togetherStateLabel,
    required String togetherActiveSingularLabel,
    required String togetherActivePluralLabel,
    required String togetherPastLabel,
    required String addTogetherAction,
    required String overlapOptionLabel,
    required String overlapSubtitle,
    required String changeSingular,
    required String changePlural,
    required String anyChangeLabel,
    required String onChangeLabel,
    required String delayAfterChangeLabel,
    required String reminderLabel,
    required String logChangeReminderAction,
    required String alwaysActiveLabel,
    required String alwaysPresentHeaderLabel,
    required String longRunningLabel,
    String? longRunningHeaderSingularLabel,
    required String longRunningHeaderLabel,
    required String quickCorrectionLabel,
    required String quickCorrectionWindowTitle,
    required String switchEventLabel,
  }) {
    return FrontingTermBundle._({
      'featureLabel': featureLabel,
      'featureLower': featureLower,
      'currentQuestion': currentQuestion,
      'currentQuestionNow': currentQuestionNow,
      'emptyCurrentState': emptyCurrentState,
      'activeSingularLabel': activeSingularLabel,
      'activePluralLabel': activePluralLabel,
      'activeSectionLabel': activeSectionLabel,
      'currentActiveLabel': currentActiveLabel,
      'latestActiveLabel': latestActiveLabel,
      'unknownActiveLabel': unknownActiveLabel,
      'currentlyActivePhrase': currentlyActivePhrase,
      'logAction': logAction,
      'logPastAction': logPastAction,
      'quickAction': quickAction,
      'holdToStartHint': holdToStartHint,
      'addAction': addAction,
      'setAsAction': setAsAction,
      'replaceCurrentAction': replaceCurrentAction,
      'endWithoutAction': endWithoutAction,
      'endCurrentAction': endCurrentAction,
      'keepCurrentAction': keepCurrentAction,
      'directButtonLabel': directButtonLabel,
      'historyLabel': historyLabel,
      'dataLabel': dataLabel,
      'entryLabel': entryLabel,
      'sessionSingular': sessionSingular,
      'sessionPlural': sessionPlural,
      'sessionCommentSingular': sessionCommentSingular,
      'sessionCommentPlural': sessionCommentPlural,
      'statsLabel': statsLabel,
      'timeLabel': timeLabel,
      'lastActiveLabel': lastActiveLabel,
      'mostActiveSortLabel': mostActiveSortLabel,
      'leastActiveSortLabel': leastActiveSortLabel,
      'statusLabel': statusLabel,
      'togetherStateLabel': togetherStateLabel,
      'togetherActiveSingularLabel': togetherActiveSingularLabel,
      'togetherActivePluralLabel': togetherActivePluralLabel,
      'togetherPastLabel': togetherPastLabel,
      'addTogetherAction': addTogetherAction,
      'overlapOptionLabel': overlapOptionLabel,
      'overlapSubtitle': overlapSubtitle,
      'changeSingular': changeSingular,
      'changePlural': changePlural,
      'anyChangeLabel': anyChangeLabel,
      'onChangeLabel': onChangeLabel,
      'delayAfterChangeLabel': delayAfterChangeLabel,
      'reminderLabel': reminderLabel,
      'logChangeReminderAction': logChangeReminderAction,
      'alwaysActiveLabel': alwaysActiveLabel,
      'alwaysPresentHeaderLabel': alwaysPresentHeaderLabel,
      'longRunningLabel': longRunningLabel,
      'longRunningHeaderSingularLabel':
          longRunningHeaderSingularLabel ?? longRunningHeaderLabel,
      'longRunningHeaderLabel': longRunningHeaderLabel,
      'quickCorrectionLabel': quickCorrectionLabel,
      'quickCorrectionWindowTitle': quickCorrectionWindowTitle,
      'switchEventLabel': switchEventLabel,
    }).normalized();
  }

  static const fieldKeys = [
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
    'togetherStateLabel',
    'togetherActiveSingularLabel',
    'togetherActivePluralLabel',
    'togetherPastLabel',
    'addTogetherAction',
    'overlapOptionLabel',
    'overlapSubtitle',
    'changeSingular',
    'changePlural',
    'anyChangeLabel',
    'onChangeLabel',
    'delayAfterChangeLabel',
    'reminderLabel',
    'logChangeReminderAction',
    'alwaysActiveLabel',
    'alwaysPresentHeaderLabel',
    'longRunningLabel',
    'longRunningHeaderSingularLabel',
    'longRunningHeaderLabel',
    'quickCorrectionLabel',
    'quickCorrectionWindowTitle',
    'switchEventLabel',
  ];

  final Map<String, String> _values;

  String get featureLabel => _values['featureLabel']!;
  String get featureLower => _values['featureLower']!;
  String get currentQuestion => _values['currentQuestion']!;
  String get currentQuestionNow => _values['currentQuestionNow']!;
  String get emptyCurrentState => _values['emptyCurrentState']!;
  String get activeSingularLabel => _values['activeSingularLabel']!;
  String get activePluralLabel => _values['activePluralLabel']!;
  String get activeSectionLabel => _values['activeSectionLabel']!;
  String get currentActiveLabel => _values['currentActiveLabel']!;
  String get latestActiveLabel => _values['latestActiveLabel']!;
  String get unknownActiveLabel => _values['unknownActiveLabel']!;
  String get currentlyActivePhrase => _values['currentlyActivePhrase']!;
  String get logAction => _values['logAction']!;
  String get logPastAction => _values['logPastAction']!;
  String get quickAction => _values['quickAction']!;
  String get holdToStartHint => _values['holdToStartHint']!;
  String get addAction => _values['addAction']!;
  String get setAsAction => _values['setAsAction']!;
  String get replaceCurrentAction => _values['replaceCurrentAction']!;
  String get endWithoutAction => _values['endWithoutAction']!;
  String get endCurrentAction => _values['endCurrentAction']!;
  String get keepCurrentAction => _values['keepCurrentAction']!;
  String get directButtonLabel => _values['directButtonLabel']!;
  String get historyLabel => _values['historyLabel']!;
  String get dataLabel => _values['dataLabel']!;
  String get entryLabel => _values['entryLabel']!;
  String get sessionSingular => _values['sessionSingular']!;
  String get sessionPlural => _values['sessionPlural']!;
  String get sessionSingularLower => sessionSingular.toLowerCase();
  String get sessionPluralLower => sessionPlural.toLowerCase();
  String get sessionCommentSingular => _values['sessionCommentSingular']!;
  String get sessionCommentPlural => _values['sessionCommentPlural']!;
  String get statsLabel => _values['statsLabel']!;
  String get timeLabel => _values['timeLabel']!;
  String get lastActiveLabel => _values['lastActiveLabel']!;
  String get mostActiveSortLabel => _values['mostActiveSortLabel']!;
  String get leastActiveSortLabel => _values['leastActiveSortLabel']!;
  String get statusLabel => _values['statusLabel']!;
  String get togetherStateLabel => _values['togetherStateLabel']!;
  String get togetherActiveSingularLabel =>
      _values['togetherActiveSingularLabel']!;
  String get togetherActivePluralLabel => _values['togetherActivePluralLabel']!;
  String get togetherPastLabel => _values['togetherPastLabel']!;
  String get addTogetherAction => _values['addTogetherAction']!;
  String get overlapOptionLabel => _values['overlapOptionLabel']!;
  String get overlapSubtitle => _values['overlapSubtitle']!;
  String get changeSingular => _values['changeSingular']!;
  String get changePlural => _values['changePlural']!;
  String get anyChangeLabel => _values['anyChangeLabel']!;
  String get onChangeLabel => _values['onChangeLabel']!;
  String get delayAfterChangeLabel => _values['delayAfterChangeLabel']!;
  String get reminderLabel => _values['reminderLabel']!;
  String get logChangeReminderAction => _values['logChangeReminderAction']!;
  String get alwaysActiveLabel => _values['alwaysActiveLabel']!;
  String get alwaysPresentHeaderLabel => _values['alwaysPresentHeaderLabel']!;
  String get longRunningLabel => _values['longRunningLabel']!;
  String get longRunningHeaderSingularLabel =>
      _values['longRunningHeaderSingularLabel'] ?? longRunningHeaderLabel;
  bool get hasLongRunningHeaderSingularLabel =>
      _values.containsKey('longRunningHeaderSingularLabel');
  String get longRunningHeaderLabel => _values['longRunningHeaderLabel']!;
  String get quickCorrectionLabel => _values['quickCorrectionLabel']!;
  String get quickCorrectionWindowTitle =>
      _values['quickCorrectionWindowTitle']!;
  String get switchEventLabel => _values['switchEventLabel']!;

  FrontingTermBundle normalized() {
    return FrontingTermBundle._({
      for (final key in fieldKeys)
        if (_values.containsKey(key)) key: _values[key]!.trim(),
    });
  }

  bool get isValid {
    for (final key in fieldKeys) {
      final value = _values[key];
      if (key == 'longRunningHeaderSingularLabel' && value == null) continue;
      if (value == null) return false;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return false;
      if (trimmed.length > frontingTermMaxLength) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    for (final key in fieldKeys)
      if (_values.containsKey(key)) key: _values[key],
  };

  static FrontingTermBundle? tryDecode(Object? value) {
    if (value is! Map) return null;
    final fields = <String, String>{};
    for (final key in fieldKeys) {
      // Preserve absence to distinguish legacy bundles from user-authored text.
      if (key == 'longRunningHeaderSingularLabel' && value[key] == null) {
        continue;
      }
      final field = value[key];
      if (field is! String) return null;
      fields[key] = field;
    }
    final bundle = FrontingTermBundle._(fields).normalized();
    return bundle.isValid ? bundle : null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FrontingTermBundle) return false;
    for (final key in fieldKeys) {
      if (other._values[key] != _values[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(fieldKeys.map((key) => _values[key]));

  @override
  String toString() => 'FrontingTermBundle(${toJson()})';
}

final class FrontingTerms {
  const FrontingTerms({this.preset, this.custom, this.authoring});

  const FrontingTerms.preset(
    FrontingTermPreset preset, {
    FrontingTermBundle? custom,
    SimpleFrontingTermAuthoring? authoring,
  }) : this(preset: preset, custom: custom, authoring: authoring);

  const FrontingTerms.custom(
    FrontingTermBundle custom, {
    SimpleFrontingTermAuthoring? authoring,
  }) : this(custom: custom, authoring: authoring);

  static const unset = FrontingTerms();

  final FrontingTermPreset? preset;
  final FrontingTermBundle? custom;
  final SimpleFrontingTermAuthoring? authoring;

  bool get isUnset => preset == null && custom == null;

  FrontingTerms normalized() {
    final bundle = custom?.normalized();
    final normalizedAuthoring = authoring?.normalized();
    final validBundle = bundle != null && bundle.isValid ? bundle : null;
    final validAuthoring = normalizedAuthoring?.isValid == true
        ? normalizedAuthoring
        : null;
    if (preset != null) {
      return FrontingTerms.preset(
        preset!,
        custom: validBundle,
        authoring: validBundle == null ? null : validAuthoring,
      );
    }
    if (validBundle == null) return unset;
    return FrontingTerms.custom(validBundle, authoring: validAuthoring);
  }

  Map<String, Object?> toJson() {
    final normalized = this.normalized();
    return {
      if (normalized.preset != null) 'preset': normalized.preset!.name,
      if (normalized.custom != null) 'custom': normalized.custom!.toJson(),
      if (normalized.authoring != null)
        'authoring': normalized.authoring!.toJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrontingTerms &&
          other.preset == preset &&
          other.custom == custom &&
          other.authoring == authoring;

  @override
  int get hashCode => Object.hash(preset, custom, authoring);

  @override
  String toString() =>
      'FrontingTerms(preset: $preset, custom: $custom, authoring: $authoring)';
}

final class FrontingTermsPreferenceCodec
    extends PreferenceCodec<FrontingTerms> {
  const FrontingTermsPreferenceCodec();

  @override
  String get valueType => 'json';

  @override
  Object? encode(FrontingTerms value) => value.normalized().toJson();

  @override
  FrontingTerms decode(Object? value) {
    if (value is! Map) return FrontingTerms.unset;
    final presetName = value['preset'];
    if (presetName is String) {
      final preset = _presetByName(presetName);
      if (preset == null) return FrontingTerms.unset;
      final custom = FrontingTermBundle.tryDecode(value['custom']);
      return FrontingTerms.preset(
        preset,
        custom: custom,
        authoring: SimpleFrontingTermAuthoring.tryDecode(value['authoring']),
      );
    }

    final custom = FrontingTermBundle.tryDecode(value['custom']);
    if (custom == null) return FrontingTerms.unset;
    return FrontingTerms.custom(
      custom,
      authoring: SimpleFrontingTermAuthoring.tryDecode(value['authoring']),
    );
  }

  @override
  bool isValid(FrontingTerms value) {
    if (value.preset != null) return true;
    final custom = value.custom;
    return custom != null && custom.normalized().isValid;
  }

  static FrontingTermPreset? _presetByName(String name) {
    for (final preset in FrontingTermPreset.values) {
      if (preset.name == name) return preset;
    }
    return null;
  }
}
