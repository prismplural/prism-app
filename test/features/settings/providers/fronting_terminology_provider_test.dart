import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  group('legacy custom singular headers', () {
    const codec = FrontingTermsPreferenceCodec();

    for (final locale in ['en', 'es']) {
      test(
        'fills only the missing display phrase using saved $locale inputs',
        () {
          final savedLocale = appLocalizationsForLocale(Locale(locale));
          final authoring = simpleFrontingAuthoringForPreset(
            savedLocale,
            FrontingTermPreset.fronting,
          );
          final generated = generateSimpleFrontingBundle(authoring);
          final legacy = generated.toJson()
            ..remove('longRunningHeaderSingularLabel')
            ..['longRunningHeaderLabel'] = 'Saved plural phrase'
            ..['historyLabel'] = 'My saved history wording';
          final payload = {'custom': legacy, 'authoring': authoring.toJson()};
          final stored = codec.decode(payload);
          final otherLocale = appLocalizationsForLocale(
            Locale(locale == 'en' ? 'es' : 'en'),
          );

          for (var pass = 0; pass < 2; pass++) {
            final reloaded = codec.decode(codec.encode(stored));
            final resolved = resolveFrontingTerms(otherLocale, reloaded);
            expect(
              resolved.longRunningHeaderSingularLabel,
              generated.longRunningHeaderSingularLabel,
            );
            expect(resolved.toJson(), {
              ...legacy,
              'longRunningHeaderSingularLabel':
                  generated.longRunningHeaderSingularLabel,
            });
            expect(codec.encode(reloaded), payload);
            expect(codec.encode(stored), payload);
          }
        },
      );
    }

    test(
      'preserves an explicitly saved singular even when it equals plural',
      () {
        final en = appLocalizationsForLocale(const Locale('en'));
        final authoring = simpleFrontingAuthoringForPreset(
          en,
          FrontingTermPreset.fronting,
        );
        final bundle = generateSimpleFrontingBundle(authoring).toJson()
          ..['longRunningHeaderSingularLabel'] = 'Our lasting presence'
          ..['longRunningHeaderLabel'] = 'Our lasting presence';
        final payload = {'custom': bundle, 'authoring': authoring.toJson()};
        final stored = codec.decode(payload);

        expect(resolveFrontingTerms(en, stored).toJson(), bundle);
        expect(codec.encode(stored), payload);
      },
    );

    test(
      'keeps advanced wording when Simple inputs are missing or invalid',
      () {
        final en = appLocalizationsForLocale(const Locale('en'));
        final legacy =
            frontingTermBundleForPreset(
                en,
                FrontingTermPreset.fronting,
              ).toJson()
              ..remove('longRunningHeaderSingularLabel')
              ..['longRunningHeaderLabel'] = 'Our lasting presence';
        for (final metadata in [
          null,
          {'kind': 'simple', 'version': 999},
        ]) {
          final stored = codec.decode({
            'custom': legacy,
            'authoring': metadata,
          });
          final resolved = resolveFrontingTerms(en, stored);

          expect(
            resolved.longRunningHeaderSingularLabel,
            'Our lasting presence',
          );
          expect(resolved.toJson(), legacy);
          expect((codec.encode(stored)! as Map)['custom'], legacy);
        }
      },
    );

    test('retains a legacy draft while its preset is active', () {
      final en = appLocalizationsForLocale(const Locale('en'));
      final authoring = simpleFrontingAuthoringForPreset(
        en,
        FrontingTermPreset.fronting,
      );
      final generated = generateSimpleFrontingBundle(authoring);
      final legacy = generated.toJson()
        ..remove('longRunningHeaderSingularLabel');
      final payload = {
        'preset': 'out',
        'custom': legacy,
        'authoring': authoring.toJson(),
      };
      final stored = codec.decode(payload);

      expect(
        resolveFrontingTerms(en, stored),
        frontingTermBundleForPreset(en, FrontingTermPreset.out),
      );
      expect(codec.encode(stored), payload);
      final activated = FrontingTerms.custom(
        stored.custom!,
        authoring: stored.authoring,
      );
      expect(
        resolveFrontingTerms(en, activated).longRunningHeaderSingularLabel,
        generated.longRunningHeaderSingularLabel,
      );
    });
  });

  test('unsupported device locales fall back to English safely', () {
    final l10n = appLocalizationsForLocale(const Locale('fr', 'FR'));

    expect(l10n.localeName, 'en');
    expect(
      resolveFrontingTerms(
        l10n,
        const FrontingTerms.preset(FrontingTermPreset.present),
      ).currentQuestion,
      "Who's present?",
    );
  });

  test(
    'resolveFrontingTerms defaults to localized fronting language',
    () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final terms = resolveFrontingTerms(en, null);

      expect(terms.featureLabel, 'Fronting');
      expect(terms.currentQuestion, "Who's fronting?");
      expect(terms.activePluralLabel, 'Fronters');
      expect(terms.logAction, 'Log Front');
      expect(terms.quickCorrectionLabel, 'Quick Switch');
    },
  );

  test('resolveFrontingTerms resolves English preset phrase bundles', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final fronting = resolveFrontingTerms(
      en,
      const FrontingTerms.preset(FrontingTermPreset.fronting),
    );
    final present = resolveFrontingTerms(
      en,
      const FrontingTerms.preset(FrontingTermPreset.present),
    );
    final out = resolveFrontingTerms(
      en,
      const FrontingTerms.preset(FrontingTermPreset.out),
    );
    final online = resolveFrontingTerms(
      en,
      const FrontingTerms.preset(FrontingTermPreset.online),
    );

    expect(fronting.activePluralLabel, 'Fronters');
    expect(present.activePluralLabel, 'Present Members');
    expect(out.currentQuestion, "Who's out?");
    expect(out.activePluralLabel, 'Out Members');
    expect(out.logAction, 'Mark Out');
    expect(out.historyLabel, 'Out history');
    expect(online.activePluralLabel, 'Online Members');
  });

  test(
    'resolveFrontingTerms keeps an active preset over a retained draft',
    () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final retainedDraft = frontingTermBundleForPreset(
        en,
        FrontingTermPreset.present,
      );

      expect(
        resolveFrontingTerms(
          en,
          FrontingTerms.preset(FrontingTermPreset.out, custom: retainedDraft),
        ),
        frontingTermBundleForPreset(en, FrontingTermPreset.out),
      );
    },
  );

  test('every preset resolves as Spanish without English leakage', () async {
    final es = await AppLocalizations.delegate.load(const Locale('es'));
    const expectedActiveLabels = {
      FrontingTermPreset.fronting: 'Personas al frente',
      FrontingTermPreset.present: 'Personas presentes',
      FrontingTermPreset.out: 'Personas fuera',
      FrontingTermPreset.online: 'Personas en línea',
    };

    for (final preset in FrontingTermPreset.values) {
      final terms = resolveFrontingTerms(es, FrontingTerms.preset(preset));
      expect(terms.currentQuestion, startsWith('¿'));
      expect(terms.sessionSingular, startsWith('Sesión'));
      expect(terms.activePluralLabel, isNot(contains('Members')));
      expect(terms.activePluralLabel, expectedActiveLabels[preset]);
      expect(terms.historyLabel, isNot(contains('history')));
    }

    expect(
      resolveFrontingTerms(
        es,
        const FrontingTerms.preset(FrontingTermPreset.present),
      ).currentQuestion,
      '¿Quién está presente?',
    );
  });

  test('simple authoring generates complete English and Spanish bundles', () {
    const english = SimpleFrontingTermAuthoring(
      locale: 'en',
      seedPreset: FrontingTermPreset.fronting,
      featureLabel: 'Orbit',
      activeSectionLabel: 'In Orbit',
      statePhrase: 'in orbit',
      activeSingularLabel: 'Orbiter',
      activePluralLabel: 'Orbiters',
      sessionSingular: 'Orbit session',
      sessionPlural: 'Orbit sessions',
    );
    const spanish = SimpleFrontingTermAuthoring(
      locale: 'es',
      seedPreset: FrontingTermPreset.fronting,
      featureLabel: 'Órbita',
      activeSectionLabel: 'En órbita',
      statePhrase: 'en órbita',
      activeSingularLabel: 'Persona en órbita',
      activePluralLabel: 'Personas en órbita',
      sessionSingular: 'Sesión en órbita',
      sessionPlural: 'Sesiones en órbita',
    );

    final enBundle = generateSimpleFrontingBundle(english);
    final esBundle = generateSimpleFrontingBundle(spanish);

    expect(enBundle.isValid, isTrue);
    expect(enBundle.currentQuestionNow, "Who's in orbit now?");
    expect(enBundle.historyLabel, 'Orbit History');
    expect(enBundle.activePluralLabel, 'Orbiters');
    expect(enBundle.longRunningHeaderSingularLabel, 'Long-running Orbiter');
    expect(enBundle.longRunningHeaderLabel, 'Long-running Orbiters');
    expect(esBundle.isValid, isTrue);
    expect(esBundle.currentQuestionNow, '¿Quién está en órbita ahora?');
    expect(esBundle.historyLabel, 'Historial: Órbita');
    expect(esBundle.activePluralLabel, 'Personas en órbita');
    expect(
      esBundle.longRunningHeaderSingularLabel,
      'Actividad prolongada: Persona en órbita',
    );
    expect(
      esBundle.longRunningHeaderLabel,
      'Actividad prolongada: Personas en órbita',
    );
    expect(esBundle.toJson().values, everyElement(isNotEmpty));
    final spanishText = esBundle.toJson().values.join('\n');
    expect(spanishText, isNot(contains('del comunidad')));
    expect(spanishText, isNot(contains('como al frente')));
  });

  test('system info labels use exact Spanish preset grammar', () async {
    final es = await AppLocalizations.delegate.load(const Locale('es'));
    const expected = {
      null: 'Información del sistema',
      SystemTermPreset.collective: 'Información del colectivo',
      SystemTermPreset.community: 'Información de la comunidad',
      SystemTermPreset.network: 'Información de la red',
      SystemTermPreset.constellation: 'Información de la constelación',
    };

    for (final entry in expected.entries) {
      final raw = entry.key == null
          ? SystemTerms.unset
          : SystemTerms.preset(entry.key!);
      final resolved = resolveSystemTerms(es, raw);
      expect(systemInfoLabel(es, raw, resolved.singular), entry.value);
    }
    expect(
      systemInfoLabel(
        es,
        const SystemTerms.custom(singular: 'familia', plural: 'familias'),
        'Familia',
      ),
      'Información: Familia',
    );
  });

  test('Spanish system presets fit agreement-neutral sentences', () async {
    final es = await AppLocalizations.delegate.load(const Locale('es'));

    for (final preset in SystemTermPreset.values) {
      final system = resolveSystemTerms(es, SystemTerms.preset(preset));
      final lower = system.singular.toLowerCase();
      final infoLabel = systemInfoLabel(
        es,
        SystemTerms.preset(preset),
        system.singular,
      );
      final preview = es.terminologySystemPreview(
        infoLabel,
        lower,
        'integrante',
      );

      expect(preview, contains('"$infoLabel"'));
      expect(preview, contains('Agrega integrante a tu $lower'));
      expect(preview, isNot(contains('Agrega integrante del $lower')));
      expect(preview, isNot(contains('este $lower')));
    }
  });

  test('custom bundles stay stable across locale changes', () async {
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
      longRunningHeaderSingularLabel: 'Long-running orbit',
      longRunningHeaderLabel: 'Long-running orbits',
      quickCorrectionLabel: 'Quick Correction',
      quickCorrectionWindowTitle: 'Quick Correction Window',
      switchEventLabel: 'Orbit switch',
    );

    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final es = await AppLocalizations.delegate.load(const Locale('es'));
    final stored = FrontingTerms.custom(
      custom,
      authoring: const SimpleFrontingTermAuthoring(
        locale: 'en',
        seedPreset: FrontingTermPreset.fronting,
        featureLabel: 'In Orbit',
        activeSectionLabel: 'In Orbit',
        statePhrase: 'in orbit',
        activeSingularLabel: 'Orbiter',
        activePluralLabel: 'Orbiters',
        sessionSingular: 'Orbit session',
        sessionPlural: 'Orbit sessions',
      ),
    );
    final resolved = resolveFrontingTerms(en, stored);
    final resolvedInSpanish = resolveFrontingTerms(es, stored);

    expect(resolved, custom);
    expect(resolvedInSpanish, custom);
    expect(resolved.activePluralLabel, 'Orbiters');
    expect(resolved.longRunningHeaderSingularLabel, 'Long-running orbit');
    expect(resolved.longRunningHeaderLabel, 'Long-running orbits');
    expect(resolved.quickCorrectionLabel, 'Quick Correction');
  });
}
