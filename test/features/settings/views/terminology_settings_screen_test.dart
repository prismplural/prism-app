import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/terminology_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  Widget buildSubject(FakeAppPreferenceRepository appPrefs) {
    return ProviderScope(
      overrides: [
        appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(
          body: SingleChildScrollView(child: SystemTerminologyPicker()),
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
