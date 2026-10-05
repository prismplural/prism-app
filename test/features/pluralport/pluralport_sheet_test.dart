import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/data_management/views/import_export_screen.dart';
import 'package:prism_plurality/features/pluralport/widgets/pluralport_brand.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'package:prism_plurality/features/pluralport/views/pluralport_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/features/onboarding/widgets/import_data_step.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/services/onboarding_commit_service.dart';
import '../../helpers/fake_repositories.dart';
import 'harness.dart';

class _Service extends PluralPortService {
  _Service(AppDatabase db, {this.performImport = false})
    : super(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db, supportDirectory: Directory.systemTemp),
        supportDirectory: () async => Directory.systemTemp,
      );
  final bool performImport;
  final completed = Completer<ImportResult>();
  Completer<void>? importGate;
  int importCalls = 0;
  Object? importError;
  bool? replacedProfile;
  bool? restoredPreferences;
  @override
  Future<PluralPortImportPlan> preview(Uint8List bytes) async =>
      PluralPortService.previewBytes(bytes);
  @override
  Future<ImportResult> importPlan(
    PluralPortImportPlan plan, {
    bool importSystemProfile = false,
    bool restorePrismPreferences = false,
  }) async {
    importCalls++;
    replacedProfile = importSystemProfile;
    restoredPreferences = restorePrismPreferences;
    await importGate?.future;
    if (importError case final error?) throw error;
    final result = performImport
        ? await super.importPlan(
            plan,
            importSystemProfile: importSystemProfile,
            restorePrismPreferences: restorePrismPreferences,
          )
        : ImportResult(membersCreated: 1);
    completed.complete(result);
    return result;
  }
}

class _Files implements PrismFileDialogService {
  _Files(this.bytes);
  Uint8List bytes;
  bool cancel = false;
  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async => cancel
      ? null
      : PickedFileHandle(
          name: 'openplural.json',
          size: bytes.length,
          readAsBytes: () async => bytes,
          openRead: () => Stream.value(bytes),
        );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final restore in [false, true]) {
    testWidgets(
      'onboarding import preserves preference choice $restore through completion',
      (tester) async {
        await tester.runAsync(() async {
          final db = makeDb();
          addTearDown(db.close);
          final settings = DriftSystemSettingsRepository(
            db.systemSettingsDao,
            null,
          );
          await settings.updateSettings(
            (await settings.getSettings()).copyWith(
              accentColorHex: '#112233',
              pinLockEnabled: true,
              hasCompletedOnboarding: false,
              sharingId: 'local-id',
            ),
          );
          final service = _Service(db, performImport: true)
            ..importGate = Completer<void>();
          final container = await _showOnboarding(
            tester,
            service,
            _preferenceFile(),
          );
          expect(find.byType(PluralPortLogo), findsOneWidget);
          expect(find.text('Export PluralPort'), findsNothing);
          await container.read(onboardingPendingImportActionProvider)!();
          await tester.pumpAndSettle();
          expect(_preferenceCheckbox(tester).value, isFalse);
          if (restore) {
            await tester.ensureVisible(find.text('Restore Prism preferences'));
            await tester.tap(find.text('Restore Prism preferences'));
            await tester.pumpAndSettle();
          }
          final importing = container.read(
            onboardingPendingImportActionProvider,
          )!();
          await tester.pump();
          expect(container.read(onboardingImportBusyProvider), isTrue);
          expect(find.text('Other import options'), findsNothing);
          await container.read(onboardingPendingImportActionProvider)!();
          expect(service.importCalls, 1);
          service.importGate!.complete();
          await importing.timeout(const Duration(seconds: 10));
          await tester.pumpAndSettle();
          final state = container.read(onboardingProvider);
          expect(state.currentStep, OnboardingStep.importedDataReady);
          expect(state.importedDataCounts!.members, 1);
          expect(
            (await settings.getSettings()).hasCompletedOnboarding,
            isFalse,
          );
          await OnboardingCommitService(
            database: db,
            settingsRepository: settings,
            appPreferenceRepository: FakeAppPreferenceRepository(),
            memberRepository: FakeMemberRepository(),
            conversationRepository: FakeConversationRepository(),
            frontingRepository: FakeFrontingSessionRepository(),
          ).completeImportedBootstrap();
          final current = await settings.getSettings();
          expect(current.hasCompletedOnboarding, isTrue);
          expect(current.accentColorHex, restore ? '#abcdef' : '#112233');
          expect(current.pinLockEnabled, isTrue);
          expect(current.sharingId, 'local-id');
          expect(container.read(onboardingImportBusyProvider), isFalse);
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'onboarding cancelled and invalid files remain retryable; back clears Continue',
    (tester) async {
      final db = makeDb();
      addTearDown(db.close);
      final service = _Service(db);
      final files = _preferenceFile()..cancel = true;
      final container = await _showOnboarding(tester, service, files);
      await container.read(onboardingPendingImportActionProvider)!();
      await tester.pumpAndSettle();
      expect(service.importCalls, 0);
      expect(find.text('Choose import file'), findsOneWidget);
      files.cancel = false;
      files.bytes = Uint8List.fromList(utf8.encode('invalid'));
      await container.read(onboardingPendingImportActionProvider)!();
      await tester.pumpAndSettle();
      expect(service.importCalls, 0);
      expect(container.read(onboardingProvider).importedDataCounts, isNull);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(container.read(onboardingImportBusyProvider), isFalse);
      await tester.tap(find.text('Other import options'));
      await tester.pumpAndSettle();
      expect(container.read(onboardingPendingImportActionProvider), isNull);
      expect(find.byType(PluralPortIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('onboarding import failure keeps preview and allows retry', (
    tester,
  ) async {
    final db = makeDb();
    addTearDown(db.close);
    final service = _Service(db)..importError = StateError('Import failed');
    final container = await _showOnboarding(tester, service, _preferenceFile());
    await container.read(onboardingPendingImportActionProvider)!();
    await tester.pumpAndSettle();
    await container.read(onboardingPendingImportActionProvider)!();
    await tester.pumpAndSettle();
    expect(service.importCalls, 1);
    expect(container.read(onboardingProvider).importedDataCounts, isNull);
    expect(container.read(onboardingImportBusyProvider), isFalse);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    service.importError = null;
    await container.read(onboardingPendingImportActionProvider)!();
    await tester.pumpAndSettle();
    expect(service.importCalls, 2);
    expect(
      container.read(onboardingProvider).currentStep,
      OnboardingStep.importedDataReady,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('PluralPort entry opens the file chooser in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ImportExportScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PluralPortIcon), findsOneWidget);
      await tester.ensureVisible(find.text('PluralPort'));
      await tester.tap(find.text('PluralPort'));
      await tester.pumpAndSettle();
      expect(find.byType(PluralPortLogo), findsOneWidget);
      expect(find.text('Choose import file'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'preview is separate from import; profile replacement is opt-in',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = makeDb();
      addTearDown(db.close);
      final service = _Service(db);
      final files = _Files(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'openplural_version': '0.1',
              'producer': {'app': 'Test'},
              'members': [
                {'id': 'm', 'name': 'Example'},
              ],
            }),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluralPortServiceProvider.overrideWithValue(service),
            prismFileDialogServiceProvider.overrideWithValue(files),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: PluralPortSheet()),
          ),
        ),
      );
      await tester.tap(find.text('Choose import file'));
      await tester.pumpAndSettle();
      expect(find.text('1 record available to import.'), findsOneWidget);
      expect(service.replacedProfile, isNull);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        false,
      );
      await tester.scrollUntilVisible(find.text('Import'), 200);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(service.replacedProfile, false);
      expect(service.restoredPreferences, false);
      expect(
        find.text(
          'Imported 1 record. Unsupported data was retained for re-export.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final restore in [false, true]) {
    testWidgets('preview preference opt-in $restore reaches the database', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final db = makeDb();
        addTearDown(db.close);
        final settings = DriftSystemSettingsRepository(
          db.systemSettingsDao,
          null,
        );
        await settings.updateSettings(
          (await settings.getSettings()).copyWith(
            accentColorHex: '#112233',
            pinLockEnabled: true,
            hasCompletedOnboarding: true,
            sharingId: 'current-sharing-id',
          ),
        );
        final service = _Service(db, performImport: true);
        await _showSheet(tester, service, _preferenceFile());
        await tester.tap(find.text('Choose import file'));
        await tester.pumpAndSettle();
        expect(_preferenceCheckbox(tester).value, isFalse);
        if (restore) {
          await tester.ensureVisible(find.text('Restore Prism preferences'));
          await tester.tap(find.text('Restore Prism preferences'));
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(find.text('Import'), 200);
        await tester.tap(find.text('Import'));
        await service.completed.future.timeout(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        final current = await settings.getSettings();
        expect(current.accentColorHex, restore ? '#abcdef' : '#112233');
        expect(current.pinLockEnabled, isTrue);
        expect(current.hasCompletedOnboarding, isTrue);
        expect(current.sharingId, 'current-sharing-id');
        expect(service.replacedProfile, isFalse);
        expect(find.text('Restore Prism preferences'), findsNothing);
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('new preview resets opt-ins and importing disables them', (
    tester,
  ) async {
    final db = makeDb();
    addTearDown(db.close);
    final service = _Service(db)..importGate = Completer<void>();
    await _showSheet(tester, service, _preferenceFile());
    await tester.tap(find.text('Choose import file'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 2; index++) {
      final finder = find.byType(CheckboxListTile).at(index);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    expect(_preferenceCheckbox(tester).value, isTrue);
    await tester.ensureVisible(find.text('Choose import file'));
    await tester.tap(find.text('Choose import file'));
    await tester.pumpAndSettle();
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    )) {
      expect(tile.value, isFalse);
    }
    await tester.scrollUntilVisible(find.text('Import'), 200);
    await tester.tap(find.text('Import'));
    await tester.pump();
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    )) {
      expect(tile.onChanged, isNull);
    }
    service.importGate!.complete();
    await tester.pumpAndSettle();
    expect(service.restoredPreferences, isFalse);
    expect(tester.takeException(), isNull);
  });
}

CheckboxListTile _preferenceCheckbox(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Restore Prism preferences'),
    );

_Files _preferenceFile() => _Files(
  Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'pluralport_version': '0.1',
        'producer': {'app': 'Prism', 'app_id': 'prism'},
        'members': [
          {'id': 'm', 'name': 'Example'},
        ],
        'extensions': {
          'prism': {
            'native_modules': {
              'systemSettings': [
                {
                  'accentColorHex': '#abcdef',
                  'pinLockEnabled': false,
                  'hasCompletedOnboarding': false,
                  'sharingId': 'foreign-sharing-id',
                },
              ],
            },
          },
        },
      }),
    ),
  ),
);

Future<void> _showSheet(WidgetTester tester, _Service service, _Files files) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluralPortServiceProvider.overrideWithValue(service),
          prismFileDialogServiceProvider.overrideWithValue(files),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PluralPortSheet()),
        ),
      ),
    );

Future<ProviderContainer> _showOnboarding(
  WidgetTester tester,
  _Service service,
  _Files files,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      pluralPortServiceProvider.overrideWithValue(service),
      prismFileDialogServiceProvider.overrideWithValue(files),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ImportDataStep()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('PluralPort'));
  await tester.tap(find.text('PluralPort'));
  await tester.pumpAndSettle();
  return container;
}
