import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';

enum PkFileImportStep {
  idle,
  parsing,
  previewing,
  importing,
  complete,
  error,
}

class PkFileImportState {
  final PkFileImportStep step;
  final PkFileExport? export;
  final PkFileImportResult? result;
  final String? error;
  final double progress;
  final String progressLabel;

  const PkFileImportState({
    this.step = PkFileImportStep.idle,
    this.export,
    this.result,
    this.error,
    this.progress = 0,
    this.progressLabel = '',
  });

  PkFileImportState copyWith({
    PkFileImportStep? step,
    PkFileExport? export,
    PkFileImportResult? result,
    String? error,
    double? progress,
    String? progressLabel,
  }) {
    return PkFileImportState(
      step: step ?? this.step,
      export: export ?? this.export,
      result: result ?? this.result,
      error: error ?? this.error,
      progress: progress ?? this.progress,
      progressLabel: progressLabel ?? this.progressLabel,
    );
  }
}

class PkFileImportNotifier extends Notifier<PkFileImportState> {
  @override
  PkFileImportState build() => const PkFileImportState();

  Future<void> selectAndParseFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      state = state.copyWith(step: PkFileImportStep.parsing);

      final raw = await File(path).readAsString();
      final export = await parsePkExportFile(raw);

      state = state.copyWith(
        step: PkFileImportStep.previewing,
        export: export,
      );
    } on PkFileParseException catch (e) {
      state = state.copyWith(
        step: PkFileImportStep.error,
        error: e.message,
      );
    } catch (e, st) {
      debugPrint('[PK_FILE_IMPORT] selectAndParseFile failed: $e\n$st');
      state = state.copyWith(
        step: PkFileImportStep.error,
        error: 'Could not read the file. $e',
      );
    }
  }

  Future<void> runImport() async {
    final export = state.export;
    if (export == null) return;

    state = state.copyWith(
      step: PkFileImportStep.importing,
      progress: 0,
      progressLabel: 'Importing…',
    );

    try {
      final result = await ref
          .read(pluralKitSyncProvider.notifier)
          .importFromFile(
            export,
            onProgress: (p, s) {
              state = state.copyWith(progress: p, progressLabel: s);
            },
          );
      state = state.copyWith(
        step: PkFileImportStep.complete,
        result: result,
        progress: 1,
        progressLabel: 'Done',
      );
    } catch (e, st) {
      debugPrint('[PK_FILE_IMPORT] runImport failed: $e\n$st');
      state = state.copyWith(
        step: PkFileImportStep.error,
        error: 'Import failed: $e',
      );
    }
  }

  void reset() {
    state = const PkFileImportState();
  }
}

final pkFileImportProvider =
    NotifierProvider<PkFileImportNotifier, PkFileImportState>(
  PkFileImportNotifier.new,
);
