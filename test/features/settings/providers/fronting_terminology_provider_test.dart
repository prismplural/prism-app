import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';

void main() {
  test('resolveFrontingTerms defaults to current fronting language', () {
    final terms = resolveFrontingTerms(null);

    expect(terms.featureLabel, 'Fronting');
    expect(terms.currentQuestion, "Who's fronting?");
    expect(terms.activePluralLabel, 'Fronters');
    expect(terms.logAction, 'Log Front');
    expect(terms.quickCorrectionLabel, 'Quick Switch');
  });

  test('resolveFrontingTerms resolves preset phrase bundles', () {
    final out = resolveFrontingTerms(
      const FrontingTerms.preset(FrontingTermPreset.out),
    );
    final online = resolveFrontingTerms(
      const FrontingTerms.preset(FrontingTermPreset.online),
    );

    expect(out.currentQuestion, "Who's out?");
    expect(out.activePluralLabel, 'Out Members');
    expect(out.logAction, 'Mark Out');
    expect(out.historyLabel, 'Out history');
    expect(online.activePluralLabel, 'Online Members');
  });

  test('resolveFrontingTerms uses complete custom bundles', () {
    final custom = FrontingTermBundle.fromFields(
      featureLabel: 'In Orbit',
      featureLower: 'in orbit',
      currentQuestion: "Who's in orbit?",
      currentQuestionNow: "Who's in orbit now?",
      emptyCurrentState: "No one's in orbit",
      activeSingularLabel: 'Orbiter',
      activePluralLabel: 'Orbiters',
      activeSectionLabel: 'In Orbit',
      currentActiveLabel: 'Current orbiter',
      latestActiveLabel: 'Latest orbiter',
      unknownActiveLabel: 'Unknown orbiter',
      currentlyActivePhrase: 'currently in orbit',
      logAction: 'Mark In Orbit',
      logPastAction: 'Log Past Orbit',
      quickAction: 'Quick Orbit',
      holdToStartHint: 'Hold to mark in orbit',
      addAction: 'Add as orbiter',
      setAsAction: 'Set as orbiter',
      replaceCurrentAction: 'Replace current orbiters',
      endWithoutAction: 'End without orbiting',
      endCurrentAction: 'End orbit',
      keepCurrentAction: 'Keep orbiting',
      directButtonLabel: 'Orbit buttons',
      historyLabel: 'Orbit history',
      dataLabel: 'Orbit data',
      entryLabel: 'Orbit entry',
      sessionSingular: 'Orbit session',
      sessionPlural: 'Orbit sessions',
      sessionCommentSingular: 'Orbit session comment',
      sessionCommentPlural: 'Orbit session comments',
      statsLabel: 'Orbit Stats',
      timeLabel: 'Orbit time',
      lastActiveLabel: 'Last in orbit',
      mostActiveSortLabel: 'Most in orbit',
      leastActiveSortLabel: 'Least in orbit',
      statusLabel: 'Orbit status',
      togetherStateLabel: 'Orbiting together',
      togetherActiveSingularLabel: 'Co-orbiter',
      togetherActivePluralLabel: 'Co-orbiters',
      togetherPastLabel: 'Co-orbited',
      addTogetherAction: 'Add co-orbiter',
      overlapOptionLabel: 'Create overlapping orbits',
      overlapSubtitle: 'Split overlap into shared orbit segments.',
      changeSingular: 'Orbit change',
      changePlural: 'Orbit changes',
      anyChangeLabel: 'Any orbit change',
      onChangeLabel: 'On orbit change',
      delayAfterChangeLabel: 'Delay after orbit change',
      reminderLabel: 'Orbit reminder',
      logChangeReminderAction: 'Log orbit change',
      alwaysActiveLabel: 'Always orbiting',
      alwaysPresentHeaderLabel: 'Always in orbit',
      longRunningLabel: 'Long-running',
      longRunningHeaderLabel: 'Long-running orbits',
      quickCorrectionLabel: 'Quick Correction',
      quickCorrectionWindowTitle: 'Quick Correction Window',
      switchEventLabel: 'Orbit switch',
    );

    final resolved = resolveFrontingTerms(FrontingTerms.custom(custom));

    expect(resolved, custom);
    expect(resolved.activePluralLabel, 'Orbiters');
    expect(resolved.quickCorrectionLabel, 'Quick Correction');
  });
}
