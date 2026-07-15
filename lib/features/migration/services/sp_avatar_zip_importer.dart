import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/normalized_avatar_batch_writer.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_worker.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

enum SpAvatarZipImportCompletion { complete, partial }

enum SpAvatarZipProgressPhase { scanning, normalizingAndSaving, complete }

/// Durable progress for a Simply Plural avatar ZIP import.
class SpAvatarZipProgress {
  final SpAvatarZipProgressPhase phase;
  final int processedCandidates;
  final int totalCandidates;
  final int committedMemberUpdates;
  final int skippedImages;
  final int warningCount;

  const SpAvatarZipProgress({
    required this.phase,
    required this.processedCandidates,
    required this.totalCandidates,
    required this.committedMemberUpdates,
    required this.skippedImages,
    required this.warningCount,
  });
}

/// Summary for a Simply Plural avatar ZIP import.
class SpAvatarZipImportResult {
  final int entriesScanned;
  final int imagesFound;
  final int memberAvatarsUpdated;
  final Set<String> memberIdsUpdated;
  final int memberAvatarsUnchanged;
  final Set<String> memberIdsUnchanged;
  final Set<String> memberIdsMissingOrDeleted;
  final bool systemAvatarUpdated;
  final int unmatchedImages;
  final List<String> warnings;
  final Duration duration;
  final SpAvatarZipImportCompletion completion;

  const SpAvatarZipImportResult({
    required this.entriesScanned,
    required this.imagesFound,
    required this.memberAvatarsUpdated,
    required this.memberIdsUpdated,
    required this.memberAvatarsUnchanged,
    required this.memberIdsUnchanged,
    required this.memberIdsMissingOrDeleted,
    required this.systemAvatarUpdated,
    required this.unmatchedImages,
    required this.warnings,
    required this.duration,
    required this.completion,
  });

  int get totalUpdated => memberAvatarsUpdated + (systemAvatarUpdated ? 1 : 0);
}

typedef SpAvatarZipTemporaryDirectoryProvider = Future<Directory> Function();

/// Imports Simply Plural's separate avatar ZIP export.
///
/// The worker owns file-backed archive scanning and normalization. This class
/// owns durable, bounded writes and only acknowledges a worker chunk after its
/// member transaction and system-avatar attempt have finished.
class SpAvatarZipImporter {
  final SpAvatarZipWorkerRunner _workerRunner;
  final SpAvatarZipTemporaryDirectoryProvider _temporaryDirectory;

  SpAvatarZipImporter({
    SpAvatarZipWorkerRunner workerRunner = const SpAvatarZipWorkerRunner(),
    SpAvatarZipTemporaryDirectoryProvider? temporaryDirectory,
  }) : _workerRunner = workerRunner,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  Future<SpAvatarZipImportResult> importZipFile({
    required String filePath,
    required MemberRepository memberRepo,
    required NormalizedAvatarBatchWriter avatarBatchWriter,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    SpExportData? exportData,
    Set<String> skipMemberIds = const {},
    void Function(SpAvatarZipProgress progress)? onProgress,
  }) async {
    // Production supplies one object for both repository capabilities.
    final _ = memberRepo;
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Avatar ZIP not found', filePath);
    }

    return _runFileImport(
      filePath: filePath,
      avatarBatchWriter: avatarBatchWriter,
      settingsRepo: settingsRepo,
      spImportDao: spImportDao,
      exportData: exportData,
      skipMemberIds: skipMemberIds,
      onProgress: onProgress,
    );
  }

  Future<SpAvatarZipImportResult> importZipFileBytes({
    required List<int> bytes,
    required MemberRepository memberRepo,
    required NormalizedAvatarBatchWriter avatarBatchWriter,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    SpExportData? exportData,
    Set<String> skipMemberIds = const {},
    void Function(SpAvatarZipProgress progress)? onProgress,
  }) async {
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);
    final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'sp-avatar-${DateTime.now().microsecondsSinceEpoch}-$nonce.zip',
    );

    try {
      await file.writeAsBytes(bytes, flush: true);
      // The caller may release its bytes after this flush.
      onProgress?.call(_initialScanningProgress);
      final _ = memberRepo;
      return await _runFileImport(
        filePath: file.path,
        avatarBatchWriter: avatarBatchWriter,
        settingsRepo: settingsRepo,
        spImportDao: spImportDao,
        exportData: exportData,
        skipMemberIds: skipMemberIds,
        onProgress: onProgress,
        emitInitialScanningProgress: false,
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Cache cleanup must not replace the import's more useful outcome.
      }
    }
  }

  Future<SpAvatarZipImportResult> _runFileImport({
    required String filePath,
    required NormalizedAvatarBatchWriter avatarBatchWriter,
    required SystemSettingsRepository? settingsRepo,
    required SpImportDao? spImportDao,
    required SpExportData? exportData,
    required Set<String> skipMemberIds,
    required void Function(SpAvatarZipProgress progress)? onProgress,
    bool emitInitialScanningProgress = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (emitInitialScanningProgress) {
      onProgress?.call(_initialScanningProgress);
    }
    final mappings = await _loadMemberMappings(spImportDao);
    final eligibleMappings = <String, String>{
      for (final entry in mappings.entries)
        if (!skipMemberIds.contains(entry.value)) entry.key: entry.value,
    };
    final systemId = exportData?.systemId?.trim();
    final normalizedSystemId = systemId == null || systemId.isEmpty
        ? null
        : systemId;

    final warnings = <String>[];
    final updatedIds = <String>{};
    final unchangedIds = <String>{};
    final missingIds = <String>{};
    var systemAvatarUpdated = false;
    var processedDescriptors = 0;
    var committedChunks = 0;
    var totalCandidates = 0;
    var latestStats = const SpAvatarZipScanStats();
    var readyStats = const SpAvatarZipScanStats();
    var completion = SpAvatarZipImportCompletion.complete;
    var terminalReceived = false;
    var aggregateWarningsAppended = false;

    int skippedCount(SpAvatarZipScanStats stats) =>
        stats.unmatchedImages +
        stats.duplicateImages +
        stats.oversizedImages +
        stats.emptyImages +
        stats.invalidImages +
        missingIds.length;

    int processedCount(SpAvatarZipScanStats stats) {
      final invalidAfterScan = max(
        0,
        stats.invalidImages - readyStats.invalidImages,
      );
      final emptyAfterScan = max(0, stats.emptyImages - readyStats.emptyImages);
      final oversizedAfterScan = max(
        0,
        stats.oversizedImages - readyStats.oversizedImages,
      );
      return min(
        totalCandidates,
        processedDescriptors +
            invalidAfterScan +
            emptyAfterScan +
            oversizedAfterScan,
      );
    }

    void publish(SpAvatarZipProgressPhase phase, SpAvatarZipScanStats stats) {
      onProgress?.call(
        SpAvatarZipProgress(
          phase: phase,
          processedCandidates:
              phase == SpAvatarZipProgressPhase.complete &&
                  completion == SpAvatarZipImportCompletion.complete
              ? totalCandidates
              : processedCount(stats),
          totalCandidates: totalCandidates,
          committedMemberUpdates: updatedIds.length,
          skippedImages: skippedCount(stats),
          warningCount:
              warnings.length +
              (aggregateWarningsAppended
                  ? 0
                  : _aggregateWarningCategoryCount(
                      stats,
                      missingMembers: missingIds.length,
                    )),
        ),
      );
    }

    final session = await _workerRunner.start(
      SpAvatarZipWorkerTask(
        filePath: filePath,
        prismMemberIdBySpId: eligibleMappings,
        systemSpId: normalizedSystemId,
      ),
    );

    try {
      await for (final event in session.events) {
        switch (event) {
          case SpAvatarZipWorkerReady(:final stats):
            latestStats = stats;
            readyStats = stats;
            totalCandidates = stats.processableImages;
            publish(SpAvatarZipProgressPhase.normalizingAndSaving, stats);

          case SpAvatarZipWorkerChunk():
            latestStats = event.stats;
            try {
              final memberBytes = <String, Uint8List>{};
              SpAvatarZipChunkDescriptor? systemDescriptor;
              for (final descriptor in event.descriptors) {
                switch (descriptor.targetKind) {
                  case SpAvatarZipTargetKind.member:
                    memberBytes[descriptor.targetId] = event.bytesFor(
                      descriptor,
                    );
                  case SpAvatarZipTargetKind.system:
                    systemDescriptor = descriptor;
                }
              }

              if (memberBytes.isNotEmpty) {
                final result = await avatarBatchWriter
                    .applyNormalizedAvatarBatch(memberBytes);
                updatedIds.addAll(result.updatedMemberIds);
                unchangedIds.addAll(result.unchangedMemberIds);
                missingIds.addAll(result.missingOrDeletedMemberIds);
              }

              if (systemDescriptor != null) {
                if (settingsRepo == null) {
                  warnings.add(
                    'Skipped the system avatar because system settings were '
                    'unavailable.',
                  );
                } else {
                  try {
                    final candidate = event.bytesFor(systemDescriptor);
                    final existing =
                        (await settingsRepo.getSettings()).systemAvatarData;
                    if (!_byteListsEqual(existing, candidate)) {
                      await settingsRepo.updateSystemAvatarData(candidate);
                    }
                    // Idempotent retries still suppress remote fallback.
                    systemAvatarUpdated = true;
                  } catch (_) {
                    warnings.add('Could not save the system avatar from ZIP.');
                  }
                }
              }

              processedDescriptors += event.descriptors.length;
              committedChunks++;
              publish(
                SpAvatarZipProgressPhase.normalizingAndSaving,
                event.stats,
              );
              session.acknowledge(event.sequence);
            } catch (_, stack) {
              if (committedChunks == 0) {
                Error.throwWithStackTrace(
                  StateError('Could not save avatar images from ZIP.'),
                  stack,
                );
              }
              completion = SpAvatarZipImportCompletion.partial;
              warnings.add(
                'Avatar ZIP stopped after saving ${updatedIds.length} of '
                '$totalCandidates matched images: could not save an avatar '
                'batch.',
              );
              session.cancel('avatar batch persistence failed');
              terminalReceived = true;
            }

          case SpAvatarZipWorkerComplete(:final stats):
            latestStats = stats;
            terminalReceived = true;

          case SpAvatarZipWorkerFailed():
            latestStats = event.stats;
            terminalReceived = true;
            if (completion == SpAvatarZipImportCompletion.partial) break;
            if (committedChunks == 0) throw _exceptionForFailure(event);
            completion = SpAvatarZipImportCompletion.partial;
            warnings.add(
              'Avatar ZIP stopped after saving ${updatedIds.length} of '
              '$totalCandidates matched images: ${event.safeMessage}',
            );
        }

        if (completion == SpAvatarZipImportCompletion.partial &&
            terminalReceived) {
          break;
        }
      }

      if (!terminalReceived) {
        throw StateError('Avatar ZIP worker stopped without a result.');
      }
    } finally {
      await session.dispose();
    }

    _appendAggregateWarnings(
      warnings,
      stats: latestStats,
      missingMembers: missingIds.length,
    );
    aggregateWarningsAppended = true;
    stopwatch.stop();
    publish(SpAvatarZipProgressPhase.complete, latestStats);

    return SpAvatarZipImportResult(
      entriesScanned: latestStats.entriesScanned,
      imagesFound: latestStats.supportedImages,
      memberAvatarsUpdated: updatedIds.length,
      memberIdsUpdated: Set.unmodifiable(updatedIds),
      memberAvatarsUnchanged: unchangedIds.length,
      memberIdsUnchanged: Set.unmodifiable(unchangedIds),
      memberIdsMissingOrDeleted: Set.unmodifiable(missingIds),
      systemAvatarUpdated: systemAvatarUpdated,
      unmatchedImages: latestStats.unmatchedImages + missingIds.length,
      warnings: List.unmodifiable(warnings),
      duration: stopwatch.elapsed,
      completion: completion,
    );
  }

  Future<Map<String, String>> _loadMemberMappings(
    SpImportDao? spImportDao,
  ) async {
    if (spImportDao == null) return const {};

    final mappings = <String, String>{};
    final rows = await spImportDao.getAllMappings();
    for (final row in rows) {
      if (row.entityType == 'member') mappings[row.spId] = row.prismId;
    }
    return mappings;
  }
}

const _initialScanningProgress = SpAvatarZipProgress(
  phase: SpAvatarZipProgressPhase.scanning,
  processedCandidates: 0,
  totalCandidates: 0,
  committedMemberUpdates: 0,
  skippedImages: 0,
  warningCount: 0,
);

bool _byteListsEqual(Uint8List? first, Uint8List second) {
  if (first == null || first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

int _aggregateWarningCategoryCount(
  SpAvatarZipScanStats stats, {
  required int missingMembers,
}) {
  var count = 0;
  if (stats.supportedImages == 0) count++;
  if (stats.unmatchedImages > 0) count++;
  if (stats.duplicateImages > 0) count++;
  if (stats.oversizedImages > 0) count++;
  if (stats.emptyImages > 0) count++;
  if (stats.invalidImages > 0) count++;
  if (missingMembers > 0) count++;
  return count;
}

Object _exceptionForFailure(SpAvatarZipWorkerFailed failure) {
  if (failure.code == 'invalid_zip') {
    return FormatException(failure.safeMessage);
  }
  return StateError(failure.safeMessage);
}

void _appendAggregateWarnings(
  List<String> warnings, {
  required SpAvatarZipScanStats stats,
  required int missingMembers,
}) {
  if (stats.supportedImages == 0) {
    warnings.add('No supported images were found in the avatar ZIP.');
  }
  if (stats.unmatchedImages > 0) {
    warnings.add(
      'Skipped ${stats.unmatchedImages} ZIP image(s) that did not match '
      'available imported '
      'Simply Plural members.',
    );
  }
  if (stats.duplicateImages > 0) {
    warnings.add(
      'Found ${stats.duplicateImages} duplicate ZIP image(s); the last image '
      'for each Simply Plural id was used.',
    );
  }
  if (stats.oversizedImages > 0) {
    warnings.add('Skipped ${stats.oversizedImages} oversized ZIP image(s).');
  }
  if (stats.emptyImages > 0) {
    warnings.add('Skipped ${stats.emptyImages} empty ZIP image(s).');
  }
  if (stats.invalidImages > 0) {
    warnings.add('Skipped ${stats.invalidImages} unsupported ZIP image(s).');
  }
  if (missingMembers > 0) {
    warnings.add(
      'Skipped $missingMembers avatar(s) for missing or deleted members.',
    );
  }
}
