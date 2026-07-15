import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/normalized_avatar_batch_writer.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/widgets/sp_avatar_zip_import_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  testWidgets('shows commit-aware progress and a retryable partial outcome', (
    tester,
  ) async {
    final importer = _ProgressImporter(
      progress: const SpAvatarZipProgress(
        phase: SpAvatarZipProgressPhase.normalizingAndSaving,
        processedCandidates: 3,
        totalCandidates: 5,
        committedMemberUpdates: 0,
        skippedImages: 1,
        warningCount: 0,
      ),
      result: const SpAvatarZipImportResult(
        entriesScanned: 5,
        imagesFound: 5,
        memberAvatarsUpdated: 0,
        memberIdsUpdated: {},
        memberAvatarsUnchanged: 0,
        memberIdsUnchanged: {},
        memberIdsMissingOrDeleted: {},
        systemAvatarUpdated: false,
        unmatchedImages: 0,
        warnings: ['Import stopped before every batch was saved.'],
        duration: Duration(milliseconds: 1),
        completion: SpAvatarZipImportCompletion.partial,
      ),
    );
    await _pumpSheet(tester, importer);

    await tester.tap(find.text('Select Avatar ZIP'));
    await tester.pump();

    expect(find.text('Processed 3 of 5 matching photos'), findsOneWidget);

    importer.finish();
    await tester.pumpAndSettle();

    expect(find.text('Some photos need attention'), findsOneWidget);
    expect(find.text('No matching photos found'), findsNothing);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('unchanged member candidate still reaches terminal progress', (
    tester,
  ) async {
    final importer = _ProgressImporter(
      progress: const SpAvatarZipProgress(
        phase: SpAvatarZipProgressPhase.complete,
        processedCandidates: 1,
        totalCandidates: 1,
        committedMemberUpdates: 0,
        skippedImages: 0,
        warningCount: 0,
      ),
      result: const SpAvatarZipImportResult(
        entriesScanned: 1,
        imagesFound: 1,
        memberAvatarsUpdated: 0,
        memberIdsUpdated: {},
        memberAvatarsUnchanged: 1,
        memberIdsUnchanged: {'member-a'},
        memberIdsMissingOrDeleted: {},
        systemAvatarUpdated: false,
        unmatchedImages: 0,
        warnings: [],
        duration: Duration(milliseconds: 1),
        completion: SpAvatarZipImportCompletion.complete,
      ),
    );
    await _pumpSheet(tester, importer);

    await tester.tap(find.text('Select Avatar ZIP'));
    await tester.pump();

    expect(find.text('Processed 1 of 1 matching photos'), findsOneWidget);

    importer.finish();
    await tester.pumpAndSettle();
  });

  testWidgets('system-only candidate reaches terminal progress', (
    tester,
  ) async {
    final importer = _ProgressImporter(
      progress: const SpAvatarZipProgress(
        phase: SpAvatarZipProgressPhase.complete,
        processedCandidates: 1,
        totalCandidates: 1,
        committedMemberUpdates: 0,
        skippedImages: 0,
        warningCount: 0,
      ),
      result: const SpAvatarZipImportResult(
        entriesScanned: 1,
        imagesFound: 1,
        memberAvatarsUpdated: 0,
        memberIdsUpdated: {},
        memberAvatarsUnchanged: 0,
        memberIdsUnchanged: {},
        memberIdsMissingOrDeleted: {},
        systemAvatarUpdated: true,
        unmatchedImages: 0,
        warnings: [],
        duration: Duration(milliseconds: 1),
        completion: SpAvatarZipImportCompletion.complete,
      ),
    );
    await _pumpSheet(tester, importer);

    await tester.tap(find.text('Select Avatar ZIP'));
    await tester.pump();

    expect(find.text('Processed 1 of 1 matching photos'), findsOneWidget);

    importer.finish();
    await tester.pumpAndSettle();
    expect(find.text('System photo updated'), findsOneWidget);
  });
}

class _ProgressImporter extends SpAvatarZipImporter {
  _ProgressImporter({required this.progress, required this.result});

  final SpAvatarZipProgress progress;
  final SpAvatarZipImportResult result;
  final _done = Completer<SpAvatarZipImportResult>();

  void finish() {
    _done.complete(result);
  }

  @override
  Future<SpAvatarZipImportResult> importZipFile({
    required String filePath,
    required MemberRepository memberRepo,
    required NormalizedAvatarBatchWriter avatarBatchWriter,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    SpExportData? exportData,
    Set<String> skipMemberIds = const {},
    void Function(SpAvatarZipProgress progress)? onProgress,
  }) {
    onProgress?.call(progress);
    return _done.future;
  }
}

Future<void> _pumpSheet(
  WidgetTester tester,
  SpAvatarZipImporter importer,
) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(_BatchMemberRepository()),
      systemSettingsRepositoryProvider.overrideWithValue(
        FakeSystemSettingsRepository(),
      ),
      prismFileDialogServiceProvider.overrideWithValue(
        const _ZipFileDialogService(),
      ),
      spAvatarZipImporterProvider.overrideWithValue(importer),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: SpAvatarZipImportSheet()),
      ),
    ),
  );
}

class _BatchMemberRepository extends FakeMemberRepository
    implements NormalizedAvatarBatchWriter {
  @override
  Future<NormalizedAvatarBatchResult> applyNormalizedAvatarBatch(
    Map<String, Uint8List> bytesByMemberId,
  ) async => NormalizedAvatarBatchResult(
    requested: bytesByMemberId.length,
    updatedMemberIds: bytesByMemberId.keys,
    unchangedMemberIds: const {},
    missingOrDeletedMemberIds: const {},
  );
}

class _ZipFileDialogService implements PrismFileDialogService {
  const _ZipFileDialogService();

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async => PickedFileHandle(
    name: 'avatars.zip',
    path: '/tmp/avatars.zip',
    readAsBytes: () async => Uint8List(0),
    openRead: null,
  );

  @override
  Future<PickedFileHandle?> pickImageFile({String? dialogTitle}) async => null;

  @override
  Future<SaveFileOutcome> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    required List<String> allowedExtensions,
    String? dialogTitle,
    String? mimeType,
  }) async => const SaveFileOutcome(status: SaveFileStatus.unsupported);

  @override
  Future<SaveFileOutcome> saveExistingFile(
    ExistingFileSaveRequest request,
  ) async => const SaveFileOutcome(status: SaveFileStatus.unsupported);
}
