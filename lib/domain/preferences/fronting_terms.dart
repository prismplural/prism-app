import 'package:prism_plurality/domain/preferences/preference_codec.dart';

const frontingTermMaxLength = 120;

enum FrontingTermPreset { fronting, present, out, online }

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
  String get longRunningHeaderLabel => _values['longRunningHeaderLabel']!;
  String get quickCorrectionLabel => _values['quickCorrectionLabel']!;
  String get quickCorrectionWindowTitle =>
      _values['quickCorrectionWindowTitle']!;
  String get switchEventLabel => _values['switchEventLabel']!;

  FrontingTermBundle normalized() {
    return FrontingTermBundle._({
      for (final key in fieldKeys) key: _values[key]!.trim(),
    });
  }

  bool get isValid {
    for (final key in fieldKeys) {
      final value = _values[key];
      if (value == null) return false;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return false;
      if (trimmed.length > frontingTermMaxLength) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    for (final key in fieldKeys) key: _values[key],
  };

  static FrontingTermBundle? tryDecode(Object? value) {
    if (value is! Map) return null;
    final fields = <String, String>{};
    for (final key in fieldKeys) {
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
  const FrontingTerms({this.preset, this.custom});

  const FrontingTerms.preset(FrontingTermPreset preset) : this(preset: preset);

  const FrontingTerms.custom(FrontingTermBundle custom) : this(custom: custom);

  static const unset = FrontingTerms();

  final FrontingTermPreset? preset;
  final FrontingTermBundle? custom;

  bool get isUnset => preset == null && custom == null;

  FrontingTerms normalized() {
    if (preset != null) return FrontingTerms.preset(preset!);
    final bundle = custom?.normalized();
    if (bundle == null || !bundle.isValid) return unset;
    return FrontingTerms.custom(bundle);
  }

  Map<String, Object?> toJson() {
    final normalized = this.normalized();
    return {
      if (normalized.preset != null) 'preset': normalized.preset!.name,
      if (normalized.custom != null) 'custom': normalized.custom!.toJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrontingTerms &&
          other.preset == preset &&
          other.custom == custom;

  @override
  int get hashCode => Object.hash(preset, custom);

  @override
  String toString() => 'FrontingTerms(preset: $preset, custom: $custom)';
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
      if (preset != null) return FrontingTerms.preset(preset);
      return FrontingTerms.unset;
    }

    final custom = FrontingTermBundle.tryDecode(value['custom']);
    if (custom == null) return FrontingTerms.unset;
    return FrontingTerms.custom(custom);
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

FrontingTermBundle frontingTermBundleForPreset(FrontingTermPreset preset) {
  return switch (preset) {
    FrontingTermPreset.fronting => _frontingBundle,
    FrontingTermPreset.present => _presentBundle,
    FrontingTermPreset.out => _outBundle,
    FrontingTermPreset.online => _onlineBundle,
  };
}

FrontingTermBundle get defaultFrontingTermBundle => _frontingBundle;

final _frontingBundle = FrontingTermBundle.fromFields(
  featureLabel: 'Fronting',
  featureLower: 'fronting',
  currentQuestion: "Who's fronting?",
  currentQuestionNow: "Who's fronting now?",
  emptyCurrentState: "No one's fronting",
  activeSingularLabel: 'Fronter',
  activePluralLabel: 'Fronters',
  activeSectionLabel: 'Fronting',
  currentActiveLabel: 'Current fronter',
  latestActiveLabel: 'Latest fronter',
  unknownActiveLabel: 'Unknown fronter',
  currentlyActivePhrase: 'currently fronting',
  logAction: 'Log Front',
  logPastAction: 'Log Past Session',
  quickAction: 'Quick Front',
  holdToStartHint: 'Hold to start fronting',
  addAction: 'Add as fronter',
  setAsAction: 'Set as fronter',
  replaceCurrentAction: 'Replace current fronters',
  endWithoutAction: 'End without fronting',
  endCurrentAction: 'End front',
  keepCurrentAction: 'Keep fronting',
  directButtonLabel: 'Front buttons',
  historyLabel: 'Fronting history',
  dataLabel: 'Fronting data',
  entryLabel: 'Fronting entry',
  sessionSingular: 'Fronting session',
  sessionPlural: 'Fronting sessions',
  sessionCommentSingular: 'Front session comment',
  sessionCommentPlural: 'Front session comments',
  statsLabel: 'Fronting Stats',
  timeLabel: 'Fronting time',
  lastActiveLabel: 'Last fronted',
  mostActiveSortLabel: 'Most fronting',
  leastActiveSortLabel: 'Least fronting',
  statusLabel: 'Front status',
  togetherStateLabel: 'Co-fronting',
  togetherActiveSingularLabel: 'Co-fronter',
  togetherActivePluralLabel: 'Co-fronters',
  togetherPastLabel: 'Co-fronted',
  addTogetherAction: 'Add Fronter',
  overlapOptionLabel: 'Create overlapping fronts',
  overlapSubtitle: 'Split the overlapping time into shared fronting segments.',
  changeSingular: 'Front change',
  changePlural: 'Front changes',
  anyChangeLabel: 'Any front change',
  onChangeLabel: 'On front change',
  delayAfterChangeLabel: 'Delay after front change',
  reminderLabel: 'Fronting reminder',
  logChangeReminderAction: 'Log fronting change',
  alwaysActiveLabel: 'Always fronting',
  alwaysPresentHeaderLabel: 'Always present',
  longRunningLabel: 'Long-running',
  longRunningHeaderLabel: 'Long-running fronts',
  quickCorrectionLabel: 'Quick Switch',
  quickCorrectionWindowTitle: 'Quick Switch Window',
  switchEventLabel: 'Switch',
);

final _presentBundle = FrontingTermBundle.fromFields(
  featureLabel: 'Presence',
  featureLower: 'presence',
  currentQuestion: "Who's present?",
  currentQuestionNow: "Who's present now?",
  emptyCurrentState: "No one's present",
  activeSingularLabel: 'Present member',
  activePluralLabel: 'Present Members',
  activeSectionLabel: 'Present',
  currentActiveLabel: 'Current present member',
  latestActiveLabel: 'Latest present member',
  unknownActiveLabel: 'Unknown present member',
  currentlyActivePhrase: 'currently present',
  logAction: 'Mark Present',
  logPastAction: 'Log Past Presence',
  quickAction: 'Quick Presence',
  holdToStartHint: 'Hold to mark present',
  addAction: 'Mark present',
  setAsAction: 'Mark present',
  replaceCurrentAction: 'Replace present members',
  endWithoutAction: 'End without marking present',
  endCurrentAction: 'End presence',
  keepCurrentAction: 'Keep present',
  directButtonLabel: 'Presence buttons',
  historyLabel: 'Presence history',
  dataLabel: 'Presence data',
  entryLabel: 'Presence entry',
  sessionSingular: 'Presence session',
  sessionPlural: 'Presence sessions',
  sessionCommentSingular: 'Presence session comment',
  sessionCommentPlural: 'Presence session comments',
  statsLabel: 'Presence Stats',
  timeLabel: 'Presence time',
  lastActiveLabel: 'Last present',
  mostActiveSortLabel: 'Most present',
  leastActiveSortLabel: 'Least present',
  statusLabel: 'Presence status',
  togetherStateLabel: 'Present together',
  togetherActiveSingularLabel: 'Present-together member',
  togetherActivePluralLabel: 'Present-together members',
  togetherPastLabel: 'Present together',
  addTogetherAction: 'Add Present Member',
  overlapOptionLabel: 'Create overlapping presence',
  overlapSubtitle: 'Split the overlapping time into shared presence segments.',
  changeSingular: 'Presence change',
  changePlural: 'Presence changes',
  anyChangeLabel: 'Any presence change',
  onChangeLabel: 'On presence change',
  delayAfterChangeLabel: 'Delay after presence change',
  reminderLabel: 'Presence reminder',
  logChangeReminderAction: 'Log presence change',
  alwaysActiveLabel: 'Always present',
  alwaysPresentHeaderLabel: 'Always present',
  longRunningLabel: 'Long-running',
  longRunningHeaderLabel: 'Long-running presence',
  quickCorrectionLabel: 'Quick Switch',
  quickCorrectionWindowTitle: 'Quick Switch Window',
  switchEventLabel: 'Switch',
);

final _outBundle = FrontingTermBundle.fromFields(
  featureLabel: 'Out',
  featureLower: 'out',
  currentQuestion: "Who's out?",
  currentQuestionNow: "Who's out now?",
  emptyCurrentState: "No one's out",
  activeSingularLabel: 'Out member',
  activePluralLabel: 'Out Members',
  activeSectionLabel: 'Out',
  currentActiveLabel: 'Current out member',
  latestActiveLabel: 'Latest out member',
  unknownActiveLabel: 'Unknown out member',
  currentlyActivePhrase: 'currently out',
  logAction: 'Mark Out',
  logPastAction: 'Log Past Out Session',
  quickAction: 'Quick Out',
  holdToStartHint: 'Hold to mark out',
  addAction: 'Mark out',
  setAsAction: 'Mark out',
  replaceCurrentAction: 'Replace current out members',
  endWithoutAction: 'End without anyone out',
  endCurrentAction: 'End out',
  keepCurrentAction: 'Keep out',
  directButtonLabel: 'Out buttons',
  historyLabel: 'Out history',
  dataLabel: 'Out data',
  entryLabel: 'Out entry',
  sessionSingular: 'Out session',
  sessionPlural: 'Out sessions',
  sessionCommentSingular: 'Out session comment',
  sessionCommentPlural: 'Out session comments',
  statsLabel: 'Out Stats',
  timeLabel: 'Out time',
  lastActiveLabel: 'Last out',
  mostActiveSortLabel: 'Most out',
  leastActiveSortLabel: 'Least out',
  statusLabel: 'Out status',
  togetherStateLabel: 'Out together',
  togetherActiveSingularLabel: 'Out-together member',
  togetherActivePluralLabel: 'Out-together members',
  togetherPastLabel: 'Out together',
  addTogetherAction: 'Add Out Member',
  overlapOptionLabel: 'Create overlapping out sessions',
  overlapSubtitle: 'Split the overlapping time into shared out segments.',
  changeSingular: 'Out change',
  changePlural: 'Out changes',
  anyChangeLabel: 'Any out change',
  onChangeLabel: 'On out change',
  delayAfterChangeLabel: 'Delay after out change',
  reminderLabel: 'Out reminder',
  logChangeReminderAction: 'Log out change',
  alwaysActiveLabel: 'Always out',
  alwaysPresentHeaderLabel: 'Always out',
  longRunningLabel: 'Long-running',
  longRunningHeaderLabel: 'Long-running out sessions',
  quickCorrectionLabel: 'Quick Switch',
  quickCorrectionWindowTitle: 'Quick Switch Window',
  switchEventLabel: 'Switch',
);

final _onlineBundle = FrontingTermBundle.fromFields(
  featureLabel: 'Online',
  featureLower: 'online',
  currentQuestion: "Who's online?",
  currentQuestionNow: "Who's online now?",
  emptyCurrentState: "No one's online",
  activeSingularLabel: 'Online member',
  activePluralLabel: 'Online Members',
  activeSectionLabel: 'Online',
  currentActiveLabel: 'Current online member',
  latestActiveLabel: 'Latest online member',
  unknownActiveLabel: 'Unknown online member',
  currentlyActivePhrase: 'currently online',
  logAction: 'Mark Online',
  logPastAction: 'Log Past Online Session',
  quickAction: 'Quick Online',
  holdToStartHint: 'Hold to mark online',
  addAction: 'Mark online',
  setAsAction: 'Mark online',
  replaceCurrentAction: 'Replace online members',
  endWithoutAction: 'End without anyone online',
  endCurrentAction: 'End online',
  keepCurrentAction: 'Keep online',
  directButtonLabel: 'Online buttons',
  historyLabel: 'Online history',
  dataLabel: 'Online data',
  entryLabel: 'Online entry',
  sessionSingular: 'Online session',
  sessionPlural: 'Online sessions',
  sessionCommentSingular: 'Online session comment',
  sessionCommentPlural: 'Online session comments',
  statsLabel: 'Online Stats',
  timeLabel: 'Online time',
  lastActiveLabel: 'Last online',
  mostActiveSortLabel: 'Most online',
  leastActiveSortLabel: 'Least online',
  statusLabel: 'Online status',
  togetherStateLabel: 'Online together',
  togetherActiveSingularLabel: 'Online-together member',
  togetherActivePluralLabel: 'Online-together members',
  togetherPastLabel: 'Online together',
  addTogetherAction: 'Add Online Member',
  overlapOptionLabel: 'Create overlapping online sessions',
  overlapSubtitle: 'Split the overlapping time into shared online segments.',
  changeSingular: 'Online change',
  changePlural: 'Online changes',
  anyChangeLabel: 'Any online change',
  onChangeLabel: 'On online change',
  delayAfterChangeLabel: 'Delay after online change',
  reminderLabel: 'Online reminder',
  logChangeReminderAction: 'Log online change',
  alwaysActiveLabel: 'Always online',
  alwaysPresentHeaderLabel: 'Always online',
  longRunningLabel: 'Long-running',
  longRunningHeaderLabel: 'Long-running online sessions',
  quickCorrectionLabel: 'Quick Switch',
  quickCorrectionWindowTitle: 'Quick Switch Window',
  switchEventLabel: 'Switch',
);
