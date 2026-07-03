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
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/terminology_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
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
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

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
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

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
      expect(find.textContaining('Network Information'), findsOneWidget);
    });

    testWidgets('requires a complete custom term pair', (tester) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Collective');
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter both singular and plural terms.'),
        findsOneWidget,
      );
      expect(await appPrefs.getStored(systemTermsPreference), isNull);
    });
  });

  group('FrontingTerminologyPicker', () {
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
            await tester.tap(find.text(frontingTermPresetChoiceLabel(preset)));
            await tester.pumpAndSettle();

            final terms = frontingTermBundleForPreset(preset);
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
            find.text(l10n.terminologyFrontingCustomIntro),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupPrimary),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupPrimarySubtitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupActions),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupActionsSubtitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupHistory),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupHistorySubtitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupTogether),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupTogetherSubtitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupChanges),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupChangesSubtitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupPinned),
            findsOneWidget,
          );
          expect(
            find.text(l10n.terminologyFrontingGroupPinnedSubtitle),
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

    testWidgets('saves an advanced custom fronting phrase bundle', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildFrontingSubject(appPrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(find.text('Primary labels'), findsOneWidget);
      expect(find.text('Actions'), findsOneWidget);
      expect(find.text('Feature label'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'At Front');
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await appPrefs.getStored(frontingTermsPreference);
      expect(stored?.custom?.featureLabel, 'At Front');
      expect(stored?.custom?.activePluralLabel, 'Fronters');
      expect(stored?.preset, isNull);
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
