import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'package:prism_plurality/features/pluralport/views/pluralport_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'harness.dart';

class _Service extends PluralPortService {
  _Service(AppDatabase db)
    : super(db: db, exporter: makeExport(db), importer: makeImport(db));
  bool? replacedProfile;
  @override
  Future<PluralPortImportPlan> preview(Uint8List bytes) async =>
      PluralPortService.previewBytes(bytes);
  @override
  Future<ImportResult> importPlan(
    PluralPortImportPlan plan, {
    bool importSystemProfile = false,
    bool restorePrismPreferences = false,
  }) async {
    replacedProfile = importSystemProfile;
    return ImportResult(membersCreated: 1);
  }
}

class _Files implements PrismFileDialogService {
  _Files(this.bytes);
  Uint8List bytes;
  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async => PickedFileHandle(
    name: 'openplural.json',
    size: bytes.length,
    readAsBytes: () async => bytes,
    openRead: () => Stream.value(bytes),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.ensureVisible(find.text('Import'));
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(service.replacedProfile, false);
      expect(
        find.text(
          'Imported 1 record. Unsupported data was retained for re-export.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
