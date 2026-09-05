import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/terminology_picker.dart';
import 'package:prism_plurality/features/settings/views/terminology_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

import '../../../helpers/fake_repositories.dart';
import '../../../helpers/fronting_term_fixtures.dart';

void main() {
  Future<void> pumpTerminologyAutosave(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Widget buildSubject(
    FakeAppPreferenceRepository appPrefs, {
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: SystemTerminologyPicker()),
        ),
      ),
    );
  }

  Widget buildFrontingSubject(
    FakeAppPreferenceRepository appPrefs, {
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: FrontingTerminologyPicker()),
        ),
      ),
    );
  }

  Widget buildMemberTerminologySubject(
    SystemSettingsRepository settingsRepository,
  ) {
    return ProviderScope(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            final settings =
                ref.watch(systemSettingsProvider).value ??
                const SystemSettings();
            return Scaffold(
              body: TerminologyPicker(
                current: settings.terminology,
                currentUseEnglish: settings.terminologyUseEnglish,
                customTerminology: settings.customTerminology,
                customPluralTerminology: settings.customPluralTerminology,
              ),
            );
          },
        ),
      ),
    );
  }

  group('SystemTerminologyPicker', () {
    testWidgets(
      'keeps custom mode when a default reset completes after re-toggle',
      (tester) async {
        final appPrefs = _DelayedResetAppPreferenceRepository();
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildSubject(appPrefs));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          ' collective ',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          ' collectives ',
        );
        expect(find.text('Save'), findsNothing);
        await pumpTerminologyAutosave(tester);

        expect(
          await appPrefs.getStored(systemTermsPreference),
          const SystemTerms.custom(
            singular: 'collective',
            plural: 'collectives',
          ),
        );

        await tester.tap(find.text('System'));
        await tester.pump();
        await appPrefs.waitForResetStart();

        await tester.tap(find.text('Custom'));
        await tester.pump();
        appPrefs.completeReset();
        await tester.pumpAndSettle();

        expect(find.text('Singular'), findsOneWidget);
        expect(find.text('Plural'), findsOneWidget);
        expect(await appPrefs.getStored(systemTermsPreference), isNull);

        await tester.enterText(find.byType(TextFormField).at(0), 'team');
        await tester.enterText(find.byType(TextFormField).at(1), 'teams');
        await pumpTerminologyAutosave(tester);

        expect(
          await appPrefs.getStored(systemTermsPreference),
          const SystemTerms.custom(singular: 'team', plural: 'teams'),
        );
      },
    );

    testWidgets('saves a system terminology preset', (tester) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs));
      await tester.pumpAndSettle();

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Collective'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Constellation'), findsOneWidget);
      expect(find.text('Collectives'), findsNothing);

      await tester.tap(find.text('Collective'));
      await tester.pumpAndSettle();

      expect(
        await appPrefs.getStored(systemTermsPreference),
        const SystemTerms.preset(SystemTermPreset.collective),
      );
    });

    testWidgets('hydrates a stored preset without entering custom mode', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          systemTermsPreference,
          const SystemTerms.preset(SystemTermPreset.network),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs));
      await tester.pumpAndSettle();

      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Singular'), findsNothing);
      expect(find.text('Plural'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('"Network Info"'), findsOneWidget);
    });

    testWidgets('requires a complete custom term pair', (tester) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Collective');
      expect(find.text('Save'), findsNothing);
      await pumpTerminologyAutosave(tester);

      expect(
        find.text('Enter both singular and plural terms.'),
        findsOneWidget,
      );
      expect(await appPrefs.getStored(systemTermsPreference), isNull);
    });

    testWidgets('retapping Custom preserves pending system-term autosave', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Team');
      await tester.enterText(find.byType(TextFormField).at(1), 'Teams');
      await tester.tap(find.text('Custom'));
      await pumpTerminologyAutosave(tester);

      expect(
        await appPrefs.getStored(systemTermsPreference),
        const SystemTerms.custom(singular: 'Team', plural: 'Teams'),
      );
    });

    testWidgets('autosave preserves trailing text and caret state', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Collective ');
      await tester.enterText(find.byType(TextFormField).at(1), 'Collectives');
      final singularField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(0),
      );
      final selectionBefore = singularField.controller!.selection;

      await pumpTerminologyAutosave(tester);

      expect(singularField.controller!.text, 'Collective ');
      expect(singularField.controller!.selection, selectionBefore);
      expect(
        await appPrefs.getStored(systemTermsPreference),
        const SystemTerms.custom(singular: 'Collective', plural: 'Collectives'),
      );
    });
  });

  group('TerminologyPicker', () {
    testWidgets('ignores an older custom terminology save while typing', (
      tester,
    ) async {
      final settingsRepository =
          _DelayedCustomTerminologySystemSettingsRepository();
      addTearDown(settingsRepository.close);

      await tester.pumpWidget(
        buildMemberTerminologySubject(settingsRepository),
      );
      await tester.pumpAndSettle();

      final singularField = find.byType(TextFormField).first;
      await tester.enterText(singularField, 'a');
      await tester.pump(const Duration(milliseconds: 300));
      await settingsRepository.waitForFirstCustomSave();

      await tester.enterText(singularField, 'ab');
      await tester.pumpAndSettle();
      settingsRepository.completeFirstCustomSave();
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextFormField>(singularField).controller!.text,
        'ab',
      );
      expect(
        tester
            .widget<TextFormField>(singularField)
            .controller!
            .selection
            .baseOffset,
        2,
      );
      expect(settingsRepository.settings.customTerminology, 'ab');
    });

    testWidgets('a preset selection supersedes a pending custom-term save', (
      tester,
    ) async {
      final settingsRepository =
          _DelayedCustomTerminologySystemSettingsRepository();
      addTearDown(settingsRepository.close);

      await tester.pumpWidget(
        buildMemberTerminologySubject(settingsRepository),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'crew');
      await tester.pump(const Duration(milliseconds: 300));
      await settingsRepository.waitForFirstCustomSave();
      await tester.tap(find.text('Members'));
      settingsRepository.completeFirstCustomSave();
      await tester.pumpAndSettle();

      expect(
        settingsRepository.settings.terminology,
        SystemTerminology.members,
      );
      expect(settingsRepository.settings.customTerminology, 'crew');
    });

    testWidgets('leaving with a pending custom draft does not throw', (
      tester,
    ) async {
      final settingsRepository = FakeSystemSettingsRepository()
        ..settings = const SystemSettings(
          terminology: SystemTerminology.custom,
          customTerminology: '',
          customPluralTerminology: '',
        );

      await tester.pumpWidget(
        buildMemberTerminologySubject(settingsRepository),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'crew');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(settingsRepository.settings.terminology, SystemTerminology.custom);
      expect(settingsRepository.settings.customTerminology, 'crew');
    });
  });

  group('FrontingTerminologyPicker', () {
    for (final hasAuthoring in [false, true]) {
      for (final retainedDraft in [false, true]) {
        testWidgets('opens a legacy bundle without singular header '
            '(Simple inputs: $hasAuthoring, retained draft: $retainedDraft)', (
          tester,
        ) async {
          final en = appLocalizationsForLocale(const Locale('en'));
          final authoring = simpleFrontingAuthoringForPreset(
            en,
            FrontingTermPreset.fronting,
          );
          final generated = generateSimpleFrontingBundle(authoring);
          final legacy = generated.toJson()
            ..remove('longRunningHeaderSingularLabel')
            ..['longRunningHeaderLabel'] = 'Our lasting presence';
          const codec = FrontingTermsPreferenceCodec();
          final payload = {
            if (retainedDraft) 'preset': 'out',
            'custom': legacy,
            if (hasAuthoring) 'authoring': authoring.toJson(),
          };
          final appPrefs = FakeAppPreferenceRepository()
            ..seed(frontingTermsPreference, codec.decode(payload));
          addTearDown(appPrefs.close);

          await tester.pumpWidget(buildFrontingSubject(appPrefs));
          await pumpTerminologyAutosave(tester);
          expect(tester.takeException(), isNull);
          expect(
            codec.encode((await appPrefs.getStored(frontingTermsPreference))!),
            payload,
          );

          if (retainedDraft) {
            await tester.tap(find.text('Custom'));
            await pumpTerminologyAutosave(tester);
          }
          if (hasAuthoring) {
            expect(find.text('Activity name'), findsOneWidget);
            await tester.tap(find.text('Advanced'));
            await tester.pumpAndSettle();
          }
          final group = find.text(en.terminologyFrontingGroupPinned);
          await tester.ensureVisible(group);
          await tester.tap(group);
          await tester.pumpAndSettle();
          final label = en.terminologyFrontingFieldLabel(
            'longRunningHeaderSingularLabel',
          );
          final field = tester.widget<PrismTextField>(
            find.byWidgetPredicate(
              (widget) => widget is PrismTextField && widget.labelText == label,
            ),
          );
          expect(
            field.controller!.text,
            hasAuthoring
                ? generated.longRunningHeaderSingularLabel
                : 'Our lasting presence',
          );
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await pumpTerminologyAutosave(tester);
          final saved = await appPrefs.getStored(frontingTermsPreference);
          expect(codec.encode(saved!), {
            'custom': legacy,
            if (hasAuthoring) 'authoring': authoring.toJson(),
          });
        });
      }
    }

    testWidgets('uses compact three-column desktop tiles', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      Rect tileRect(String label) {
        return tester.getRect(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
      }

      final fronting = tileRect('Fronting');
      final present = tileRect('Present');
      final out = tileRect('Out');
      final online = tileRect('Online');

      expect(fronting.height, closeTo(52, 0.1));
      expect(fronting.width, lessThan(360));
      expect(present.top, fronting.top);
      expect(out.top, fronting.top);
      expect(online.top, greaterThan(fronting.top));
      expect(tester.takeException(), isNull);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
        'renders localized fronting terminology strings for ${locale.languageCode}',
        (tester) async {
          final appPrefs = FakeAppPreferenceRepository();
          addTearDown(appPrefs.close);
          final l10n = await AppLocalizations.delegate.load(locale);

          await tester.pumpWidget(
            buildFrontingSubject(appPrefs, locale: locale),
          );
          await tester.pumpAndSettle();

          expect(
            find.text(l10n.settingsTerminologyPreviewLabel),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingCustomSubtitle),
            findsOneWidget,
          );

          for (final preset in frontingTermPresetChoices) {
            await tester.tap(
              find.text(frontingTermPresetChoiceLabel(l10n, preset)),
            );
            await tester.pumpAndSettle();

            final terms = frontingTermBundleForPreset(l10n, preset);
            expect(
              find.text(
                l10n.terminologyFrontingPreview(
                  terms.currentQuestionNow,
                  terms.activePluralLabel,
                  terms.logAction,
                  terms.historyLabel,
                ),
              ),
              findsOneWidget,
            );
          }

          await tester.tap(find.text(l10n.terminologySystemModeCustom));
          await tester.pumpAndSettle();

          expect(
            find.text(l10n.terminologyFrontingSimpleIntro),
            findsOneWidget,
          );
          expect(find.text(l10n.terminologyFrontingModeSimple), findsOneWidget);
          expect(
            find.text(l10n.terminologyFrontingModeAdvanced),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingSimpleFieldLabel('featureLabel')),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingSimpleRegenerationNote),
            findsOneWidget,
          );
          expect(find.textContaining('{question}'), findsNothing);
          expect(find.textContaining('{activePlural}'), findsNothing);
          expect(find.textContaining('{logAction}'), findsNothing);
          expect(find.textContaining('{historyLabel}'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('saves a fronting terminology preset', (tester) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();

      expect(find.text('Fronting'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Out'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Out Members'), findsOneWidget);
      expect(find.text('Simple or advanced'), findsOneWidget);

      await tester.tap(find.text('Out'));
      await tester.pumpAndSettle();

      expect(
        await appPrefs.getStored(frontingTermsPreference),
        const FrontingTerms.preset(FrontingTermPreset.out),
      );
    });

    testWidgets('uses the Fronting choice as the reset/default state', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          frontingTermsPreference,
          const FrontingTerms.preset(FrontingTermPreset.online),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fronting'));
      await tester.pumpAndSettle();

      expect(await appPrefs.getStored(frontingTermsPreference), isNull);
    });

    testWidgets('uses Fronting to discard a retained custom draft', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          frontingTermsPreference,
          FrontingTerms.preset(
            FrontingTermPreset.online,
            custom: testFrontingTermBundle,
          ),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fronting'));
      await tester.pumpAndSettle();

      expect(await appPrefs.getStored(frontingTermsPreference), isNull);
    });

    testWidgets('saves a generated simple custom fronting phrase bundle', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(find.text('Simple'), findsOneWidget);
      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('Activity name'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('simple-fronting-featureLabel')),
        'Orbit',
      );
      expect(find.text('Save'), findsNothing);
      await pumpTerminologyAutosave(tester);

      final stored = await appPrefs.getStored(frontingTermsPreference);
      expect(stored?.custom?.featureLabel, 'Orbit');
      expect(stored?.custom?.activePluralLabel, 'Fronters');
      expect(stored?.custom?.historyLabel, 'Orbit History');
      expect(stored?.authoring?.featureLabel, 'Orbit');
      expect(stored?.preset, isNull);
    });

    testWidgets('preserves a custom draft when selecting a preset', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      final featureField = find.descendant(
        of: find.byKey(const ValueKey('simple-fronting-featureLabel')),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(featureField, 'Orbit');
      await pumpTerminologyAutosave(tester);

      await tester.tap(find.text('Out'));
      await tester.pumpAndSettle();

      final storedPreset = await appPrefs.getStored(frontingTermsPreference);
      expect(storedPreset?.preset, FrontingTermPreset.out);
      expect(storedPreset?.custom?.featureLabel, 'Orbit');
      expect(storedPreset?.authoring?.featureLabel, 'Orbit');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextFormField>(featureField).controller!.text,
        'Orbit',
      );
      final restored = await appPrefs.getStored(frontingTermsPreference);
      expect(restored?.preset, isNull);
      expect(restored?.custom?.featureLabel, 'Orbit');
    });

    testWidgets('exploring Custom does not replace the selected preset', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          frontingTermsPreference,
          const FrontingTerms.preset(FrontingTermPreset.online),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      final featureField = find.descendant(
        of: find.byKey(const ValueKey('simple-fronting-featureLabel')),
        matching: find.byType(TextFormField),
      );
      expect(
        tester.widget<TextFormField>(featureField).controller!.text,
        'Online',
      );

      expect(
        await appPrefs.getStored(frontingTermsPreference),
        const FrontingTerms.preset(FrontingTermPreset.online),
      );
    });

    testWidgets('retapping Custom preserves the draft and pending autosave', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      final featureField = find.descendant(
        of: find.byKey(const ValueKey('simple-fronting-featureLabel')),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(featureField, 'Orbit');
      await tester.tap(find.text('Custom'));
      await pumpTerminologyAutosave(tester);

      expect(
        tester.widget<TextFormField>(featureField).controller!.text,
        'Orbit',
      );
      expect(
        (await appPrefs.getStored(
          frontingTermsPreference,
        ))?.custom?.featureLabel,
        'Orbit',
      );
    });

    testWidgets('autosave preserves trailing text and caret state', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      final wrapperFinder = find.byKey(
        const ValueKey('simple-fronting-featureLabel'),
      );
      final fieldFinder = find.descendant(
        of: wrapperFinder,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fieldFinder, 'Orbit ');
      final field = tester.widget<TextFormField>(fieldFinder);
      final selectionBefore = field.controller!.selection;

      await pumpTerminologyAutosave(tester);

      expect(field.controller!.text, 'Orbit ');
      expect(field.controller!.selection, selectionBefore);
      expect(
        (await appPrefs.getStored(
          frontingTermsPreference,
        ))?.custom?.featureLabel,
        'Orbit',
      );
    });

    testWidgets('loads a legacy custom bundle in Advanced unchanged', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          frontingTermsPreference,
          FrontingTerms.custom(testFrontingTermBundle),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();

      expect(
        find.text('Edit every phrase Prism uses for this activity.'),
        findsOneWidget,
      );
      expect(find.text('Start Simple Setup'), findsOneWidget);
      expect(find.text('Primary labels'), findsOneWidget);
      expect(find.text('Activity name'), findsNothing);
      expect(
        await appPrefs.getStored(frontingTermsPreference),
        FrontingTerms.custom(testFrontingTermBundle),
      );
    });

    testWidgets(
      'starting Simple does not overwrite legacy terms until edited',
      (tester) async {
        final appPrefs = FakeAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(testFrontingTermBundle),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Simple Setup'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(
          await appPrefs.getStored(frontingTermsPreference),
          FrontingTerms.custom(testFrontingTermBundle),
        );
      },
    );

    testWidgets(
      'selecting a preset after pristine Simple retains legacy terms',
      (tester) async {
        final appPrefs = FakeAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(testFrontingTermBundle),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Simple Setup'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Out'));
        await tester.pumpAndSettle();

        final storedPreset = await appPrefs.getStored(frontingTermsPreference);
        expect(storedPreset?.preset, FrontingTermPreset.out);
        expect(storedPreset?.custom, testFrontingTermBundle);

        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        expect(
          find.text('Edit every phrase Prism uses for this activity.'),
          findsOneWidget,
        );
        final restored = await appPrefs.getStored(frontingTermsPreference);
        expect(restored?.preset, isNull);
        expect(restored?.custom, testFrontingTermBundle);
      },
    );

    testWidgets(
      'starting Simple flushes a pending Advanced edit without saving defaults',
      (tester) async {
        final appPrefs = FakeAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(testFrontingTermBundle),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Primary labels'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'Orbiting');
        await tester.ensureVisible(find.text('Start Simple Setup'));
        await tester.tap(find.text('Start Simple Setup'));
        await pumpTerminologyAutosave(tester);

        final stored = await appPrefs.getStored(frontingTermsPreference);
        expect(stored?.custom?.featureLabel, 'Orbiting');
        expect(stored?.authoring, isNull);
        expect(find.text('Activity name'), findsOneWidget);
      },
    );

    testWidgets(
      'starting Simple ignores stale Advanced saves while its flush is queued',
      (tester) async {
        final appPrefs = _DelayedFrontingSetAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(testFrontingTermBundle),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Primary labels'));
        await tester.pumpAndSettle();

        final featureField = find.byType(TextFormField).first;
        await tester.enterText(featureField, 'First draft');
        await tester.pump(const Duration(milliseconds: 350));
        await appPrefs.waitForFirstFrontingSet();

        await tester.enterText(featureField, 'Latest draft');
        await tester.ensureVisible(find.text('Start Simple Setup'));
        await tester.tap(find.text('Start Simple Setup'));
        await tester.pump();

        appPrefs.completeFirstFrontingSet();
        await appPrefs.waitForSecondFrontingSet();
        await tester.pump();

        expect(find.text('Activity name'), findsOneWidget);
        expect(
          find.text('Edit every phrase Prism uses for this activity.'),
          findsNothing,
        );

        appPrefs.completeSecondFrontingSet();
        await tester.pumpAndSettle();

        final stored = await appPrefs.getStored(frontingTermsPreference);
        expect(stored?.custom?.featureLabel, 'Latest draft');
        expect(stored?.authoring, isNull);
        expect(find.text('Activity name'), findsOneWidget);
      },
    );

    testWidgets(
      'an older preset write cannot restore a discarded custom draft',
      (tester) async {
        final appPrefs = _DelayedFirstFrontingSetAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(testFrontingTermBundle),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Out'));
        await tester.pump();
        await appPrefs.waitForFirstFrontingSet();

        await tester.tap(find.text('Fronting'));
        await tester.pump();
        appPrefs.completeFirstFrontingSet();
        await tester.pumpAndSettle();

        expect(await appPrefs.getStored(frontingTermsPreference), isNull);
      },
    );

    testWidgets(
      'reconciles an external update after a missing stored echo times out',
      (tester) async {
        final appPrefs = _DelayedFirstFrontingSetAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(testFrontingTermBundle),
          );
        addTearDown(appPrefs.completeFirstFrontingSet);
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Primary labels'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'Orbiting');
        await tester.pump(const Duration(milliseconds: 350));
        await appPrefs.waitForFirstFrontingSet();

        await tester.ensureVisible(find.text('Start Simple Setup'));
        await tester.tap(find.text('Start Simple Setup'));
        await tester.pump();
        await appPrefs.setExternalFrontingTerms(
          const FrontingTerms.preset(FrontingTermPreset.out),
        );
        await tester.pump();

        expect(find.text('Activity name'), findsOneWidget);
        await tester.pump(const Duration(seconds: 16));

        expect(find.text('Activity name'), findsNothing);
        expect(
          find.text('Edit every phrase Prism uses for this activity.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'switching Simple to Advanced and back preserves Simple authoring',
      (tester) async {
        const authoring = SimpleFrontingTermAuthoring(
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
        final appPrefs = FakeAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(
              generateSimpleFrontingBundle(authoring),
              authoring: authoring,
            ),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        final featureField = find.descendant(
          of: find.byKey(const ValueKey('simple-fronting-featureLabel')),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(featureField, 'Orbit Activity');
        await tester.tap(find.text('Advanced'));
        await tester.pump();
        expect(
          find.text('Edit every phrase Prism uses for this activity.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Simple'));
        await tester.pump();
        expect(
          tester.widget<TextFormField>(featureField).controller!.text,
          'Orbit Activity',
        );
        await pumpTerminologyAutosave(tester);

        final stored = await appPrefs.getStored(frontingTermsPreference);
        expect(stored?.custom?.featureLabel, 'Orbit Activity');
        expect(stored?.authoring?.featureLabel, 'Orbit Activity');
      },
    );

    testWidgets(
      'disposing after switching to Advanced flushes Simple authoring',
      (tester) async {
        const authoring = SimpleFrontingTermAuthoring(
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
        final appPrefs = FakeAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(
              generateSimpleFrontingBundle(authoring),
              authoring: authoring,
            ),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        final featureField = find.descendant(
          of: find.byKey(const ValueKey('simple-fronting-featureLabel')),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(featureField, 'Orbit Activity');
        await tester.tap(find.text('Advanced'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        final stored = await appPrefs.getStored(frontingTermsPreference);
        expect(stored?.custom?.featureLabel, 'Orbit Activity');
        expect(stored?.authoring?.featureLabel, 'Orbit Activity');
      },
    );

    testWidgets(
      'pending Simple autosave does not bounce Advanced back to Simple',
      (tester) async {
        const authoring = SimpleFrontingTermAuthoring(
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
        final appPrefs = FakeAppPreferenceRepository()
          ..seed(
            frontingTermsPreference,
            FrontingTerms.custom(
              generateSimpleFrontingBundle(authoring),
              authoring: authoring,
            ),
          );
        addTearDown(appPrefs.close);

        await tester.pumpWidget(buildFrontingSubject(appPrefs));
        await tester.pumpAndSettle();
        final featureField = find.descendant(
          of: find.byKey(const ValueKey('simple-fronting-featureLabel')),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(featureField, 'Orbit Activity');
        await tester.tap(find.text('Advanced'));
        await pumpTerminologyAutosave(tester);

        expect(
          find.text('Edit every phrase Prism uses for this activity.'),
          findsOneWidget,
        );
        expect(find.text('Activity name'), findsNothing);
        final stored = await appPrefs.getStored(frontingTermsPreference);
        expect(stored?.custom?.featureLabel, 'Orbit Activity');
        expect(stored?.authoring?.featureLabel, 'Orbit Activity');
      },
    );

    testWidgets('an Advanced override drops stale Simple metadata', (
      tester,
    ) async {
      const authoring = SimpleFrontingTermAuthoring(
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
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          frontingTermsPreference,
          FrontingTerms.custom(
            generateSimpleFrontingBundle(authoring),
            authoring: authoring,
          ),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Primary labels'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Orbiting');
      expect(find.text('Save'), findsNothing);
      await pumpTerminologyAutosave(tester);

      final stored = await appPrefs.getStored(frontingTermsPreference);
      expect(stored?.custom?.featureLabel, 'Orbiting');
      expect(stored?.authoring, isNull);
    });
  });
}

class _DelayedResetAppPreferenceRepository extends FakeAppPreferenceRepository {
  final _resetStarted = Completer<void>();
  final _completeReset = Completer<void>();

  Future<void> waitForResetStart() => _resetStarted.future;

  void completeReset() {
    if (!_completeReset.isCompleted) {
      _completeReset.complete();
    }
  }

  @override
  Future<void> reset<T>(PreferenceDefinition<T> definition) async {
    if (!_resetStarted.isCompleted) {
      _resetStarted.complete();
    }
    await _completeReset.future;
    await super.reset(definition);
  }
}

class _DelayedFrontingSetAppPreferenceRepository
    extends FakeAppPreferenceRepository {
  final _firstFrontingSetStarted = Completer<void>();
  final _secondFrontingSetStarted = Completer<void>();
  final _completeFirstFrontingSet = Completer<void>();
  final _completeSecondFrontingSet = Completer<void>();
  var _frontingSetCount = 0;

  Future<void> waitForFirstFrontingSet() => _firstFrontingSetStarted.future;

  Future<void> waitForSecondFrontingSet() => _secondFrontingSetStarted.future;

  void completeFirstFrontingSet() {
    if (!_completeFirstFrontingSet.isCompleted) {
      _completeFirstFrontingSet.complete();
    }
  }

  void completeSecondFrontingSet() {
    if (!_completeSecondFrontingSet.isCompleted) {
      _completeSecondFrontingSet.complete();
    }
  }

  @override
  Future<void> set<T>(PreferenceDefinition<T> definition, T value) async {
    if (definition.key == frontingTermsPreference.key) {
      switch (_frontingSetCount++) {
        case 0:
          _firstFrontingSetStarted.complete();
          await _completeFirstFrontingSet.future;
        case 1:
          _secondFrontingSetStarted.complete();
          await _completeSecondFrontingSet.future;
      }
    }
    await super.set(definition, value);
  }
}

class _DelayedFirstFrontingSetAppPreferenceRepository
    extends FakeAppPreferenceRepository {
  final _firstFrontingSetStarted = Completer<void>();
  final _completeFirstFrontingSet = Completer<void>();
  var _hasDelayedFrontingSet = false;

  Future<void> waitForFirstFrontingSet() => _firstFrontingSetStarted.future;

  void completeFirstFrontingSet() {
    if (!_completeFirstFrontingSet.isCompleted) {
      _completeFirstFrontingSet.complete();
    }
  }

  Future<void> setExternalFrontingTerms(FrontingTerms terms) {
    return super.set(frontingTermsPreference, terms);
  }

  @override
  Future<void> set<T>(PreferenceDefinition<T> definition, T value) async {
    if (definition.key == frontingTermsPreference.key &&
        !_hasDelayedFrontingSet) {
      _hasDelayedFrontingSet = true;
      _firstFrontingSetStarted.complete();
      await _completeFirstFrontingSet.future;
    }
    await super.set(definition, value);
  }
}

class _DelayedCustomTerminologySystemSettingsRepository
    extends FakeSystemSettingsRepository {
  _DelayedCustomTerminologySystemSettingsRepository() {
    settings = const SystemSettings(
      terminology: SystemTerminology.custom,
      customTerminology: '',
      customPluralTerminology: '',
    );
  }

  final _changes = StreamController<SystemSettings>.broadcast();
  final _firstCustomSaveStarted = Completer<void>();
  final _completeFirstCustomSave = Completer<void>();
  var _hasDelayedCustomSave = false;

  Future<void> waitForFirstCustomSave() => _firstCustomSaveStarted.future;

  void completeFirstCustomSave() {
    if (!_completeFirstCustomSave.isCompleted) {
      _completeFirstCustomSave.complete();
    }
  }

  void close() => _changes.close();

  @override
  Stream<SystemSettings> watchSettings() async* {
    yield settings;
    yield* _changes.stream;
  }

  @override
  Future<void> updateTerminologyFields({
    required SystemTerminology terminology,
    String? customTerminology,
    String? customPluralTerminology,
    bool useEnglish = false,
  }) async {
    final next = settings.copyWith(
      terminology: terminology,
      customTerminology: customTerminology,
      customPluralTerminology: customPluralTerminology,
      terminologyUseEnglish: useEnglish,
    );
    if (!_hasDelayedCustomSave) {
      _hasDelayedCustomSave = true;
      _firstCustomSaveStarted.complete();
      await _completeFirstCustomSave.future;
    }
    settings = next;
    _changes.add(settings);
  }
}
