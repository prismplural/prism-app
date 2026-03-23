import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

/// Current import state exposed to the UI.
class MigrationState {
  final ImportState step;
  final SpExportData? exportData;
  final ImportResult? result;
  final String? error;
  final int current;
  final int total;
  final String progressLabel;

  const MigrationState({
    this.step = ImportState.idle,
    this.exportData,
    this.result,
    this.error,
    this.current = 0,
    this.total = 0,
    this.progressLabel = '',
  });

  double get progress => total > 0 ? current / total : 0;

  MigrationState copyWith({
    ImportState? step,
    SpExportData? exportData,
    ImportResult? result,
    String? error,
    int? current,
    int? total,
    String? progressLabel,
  }) {
    return MigrationState(
      step: step ?? this.step,
      exportData: exportData ?? this.exportData,
      result: result ?? this.result,
      error: error ?? this.error,
      current: current ?? this.current,
      total: total ?? this.total,
      progressLabel: progressLabel ?? this.progressLabel,
    );
  }
}

/// Notifier managing the SP import workflow.
class ImporterNotifier extends Notifier<MigrationState> {
  final _importer = SpImporter();

  @override
  MigrationState build() => const MigrationState();

  /// Let the user pick a file, then parse it.
  Future<void> selectAndParseFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      state = state.copyWith(step: ImportState.parsing);

      final exportData = _importer.parseFile(filePath);

      if (exportData.isEmpty) {
        state = state.copyWith(
          step: ImportState.error,
          error: 'The selected file does not contain any recognized '
              'Simply Plural data. Please check that you exported '
              'from Simply Plural correctly.',
        );
        return;
      }

      state = state.copyWith(
        step: ImportState.previewing,
        exportData: exportData,
      );
    } on FormatException catch (e) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Could not parse the file: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'An error occurred: $e',
      );
    }
  }

  /// Execute the import using the previously parsed data.
  Future<void> executeImport({bool downloadAvatars = true}) async {
    final data = state.exportData;
    if (data == null) return;

    state = state.copyWith(
      step: ImportState.importing,
      current: 0,
      total: data.totalEntities,
      progressLabel: 'Starting import...',
    );

    try {
      final result = await _importer.executeImport(
        db: ref.read(databaseProvider),
        data: data,
        memberRepo: ref.read(memberRepositoryProvider),
        sessionRepo: ref.read(frontingSessionRepositoryProvider),
        conversationRepo: ref.read(conversationRepositoryProvider),
        messageRepo: ref.read(chatMessageRepositoryProvider),
        pollRepo: ref.read(pollRepositoryProvider),
        notesRepo: ref.read(notesRepositoryProvider),
        commentsRepo: ref.read(frontSessionCommentsRepositoryProvider),
        customFieldsRepo: ref.read(customFieldsRepositoryProvider),
        groupsRepo: ref.read(memberGroupsRepositoryProvider),
        remindersRepo: ref.read(remindersRepositoryProvider),
        downloadAvatars: downloadAvatars,
        onProgress: (current, total, label) {
          state = state.copyWith(
            current: current,
            total: total,
            progressLabel: label,
          );
        },
      );

      state = state.copyWith(
        step: ImportState.complete,
        result: result,
        current: state.total,
      );
    } catch (e) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Import failed: $e',
      );
    }
  }

  /// Reset to initial state.
  void reset() {
    state = const MigrationState();
  }
}

final importerProvider =
    NotifierProvider<ImporterNotifier, MigrationState>(ImporterNotifier.new);
