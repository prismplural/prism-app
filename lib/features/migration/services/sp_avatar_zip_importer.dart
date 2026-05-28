import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

/// Summary for a Simply Plural avatar ZIP import.
class SpAvatarZipImportResult {
  final int entriesScanned;
  final int imagesFound;
  final int memberAvatarsUpdated;
  final bool systemAvatarUpdated;
  final int unmatchedImages;
  final List<String> warnings;
  final Duration duration;

  const SpAvatarZipImportResult({
    required this.entriesScanned,
    required this.imagesFound,
    required this.memberAvatarsUpdated,
    required this.systemAvatarUpdated,
    required this.unmatchedImages,
    required this.warnings,
    required this.duration,
  });

  int get totalUpdated => memberAvatarsUpdated + (systemAvatarUpdated ? 1 : 0);
}

const Set<String> _supportedImageExtensions = {
  '.gif',
  '.jpeg',
  '.jpg',
  '.png',
  '.webp',
};

const int _maxImageBytes = 20 * 1024 * 1024;

/// Imports Simply Plural's separate avatar ZIP export.
///
/// SP names each exported image by the source entity id. Prism already keeps
/// the SP member id -> Prism member id map after imports, so this service can
/// repair member photos without touching any non-avatar fields.
class SpAvatarZipImporter {
  /// Tests pass `runInline: true` to keep the CPU-heavy decode loop on the
  /// current isolate. Production code pays the isolate spawn so the main
  /// isolate stays responsive — pure-Dart image decode of a 50-photo zip
  /// will otherwise ANR mid-tier Android.
  final bool _runInline;

  SpAvatarZipImporter({bool runInline = false}) : _runInline = runInline;

  Future<SpAvatarZipImportResult> importZipFile({
    required String filePath,
    required MemberRepository memberRepo,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    SpExportData? exportData,
    Set<String> skipMemberIds = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Avatar ZIP not found', filePath);
    }

    return _runImport(
      input: _ZipProcessingInput(filePath: filePath, bytes: null),
      memberRepo: memberRepo,
      settingsRepo: settingsRepo,
      spImportDao: spImportDao,
      exportData: exportData,
      skipMemberIds: skipMemberIds,
      stopwatch: stopwatch,
    );
  }

  Future<SpAvatarZipImportResult> importZipFileBytes({
    required List<int> bytes,
    required MemberRepository memberRepo,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    SpExportData? exportData,
    Set<String> skipMemberIds = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    final byteList = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return _runImport(
      input: _ZipProcessingInput(filePath: null, bytes: byteList),
      memberRepo: memberRepo,
      settingsRepo: settingsRepo,
      spImportDao: spImportDao,
      exportData: exportData,
      skipMemberIds: skipMemberIds,
      stopwatch: stopwatch,
    );
  }

  Future<SpAvatarZipImportResult> _runImport({
    required _ZipProcessingInput input,
    required MemberRepository memberRepo,
    required SystemSettingsRepository? settingsRepo,
    required SpImportDao? spImportDao,
    required SpExportData? exportData,
    required Set<String> skipMemberIds,
    required Stopwatch stopwatch,
  }) async {
    final memberMappings = await _loadMemberMappings(spImportDao);
    final systemId = exportData?.systemId?.trim();

    final targetSpIds = <String>{
      ...memberMappings.keys,
      if (systemId != null && systemId.isNotEmpty) systemId,
    };

    final task = _ZipProcessingTask(
      input: input,
      targetSpIds: targetSpIds,
      maxImageBytes: _maxImageBytes,
    );

    final processing = _runInline
        ? await _processArchive(task)
        : await Isolate.run(() => _processArchive(task));

    var memberAvatarsUpdated = 0;
    var systemAvatarUpdated = false;
    var unmatchedImages = processing.unmatchedImages;
    final warnings = List<String>.from(processing.warnings);

    for (final image in processing.processed) {
      if (systemId != null && systemId.isNotEmpty && image.spId == systemId) {
        if (settingsRepo != null) {
          await settingsRepo.updateSystemAvatarData(image.normalized);
          systemAvatarUpdated = true;
        }
        continue;
      }

      final memberId = memberMappings[image.spId];
      if (memberId == null) {
        unmatchedImages++;
        continue;
      }
      if (skipMemberIds.contains(memberId)) {
        continue;
      }

      final current = await memberRepo.getMemberById(memberId);
      if (current == null) {
        warnings.add('Skipped ZIP image for missing member: ${image.spId}');
        unmatchedImages++;
        continue;
      }

      await memberRepo.updateMember(
        current.copyWith(avatarImageData: image.normalized),
      );
      memberAvatarsUpdated++;
    }

    if (processing.imagesFound == 0) {
      warnings.add('No supported images were found in the avatar ZIP.');
    } else if (unmatchedImages > 0) {
      warnings.add(
        'Skipped $unmatchedImages ZIP image(s) that did not match imported '
        'Simply Plural members.',
      );
    }

    stopwatch.stop();
    return SpAvatarZipImportResult(
      entriesScanned: processing.entriesScanned,
      imagesFound: processing.imagesFound,
      memberAvatarsUpdated: memberAvatarsUpdated,
      systemAvatarUpdated: systemAvatarUpdated,
      unmatchedImages: unmatchedImages,
      warnings: warnings,
      duration: stopwatch.elapsed,
    );
  }

  Future<Map<String, String>> _loadMemberMappings(
    SpImportDao? spImportDao,
  ) async {
    if (spImportDao == null) return const {};

    final mappings = <String, String>{};
    final rows = await spImportDao.getAllMappings();
    for (final row in rows) {
      if (row.entityType == 'member') {
        mappings[row.spId] = row.prismId;
      }
    }
    return mappings;
  }
}

class _ZipProcessingInput {
  final String? filePath;
  final Uint8List? bytes;

  const _ZipProcessingInput({required this.filePath, required this.bytes});
}

class _ZipProcessingTask {
  final _ZipProcessingInput input;
  final Set<String> targetSpIds;
  final int maxImageBytes;

  const _ZipProcessingTask({
    required this.input,
    required this.targetSpIds,
    required this.maxImageBytes,
  });
}

class _ProcessedImage {
  final String spId;
  final Uint8List normalized;

  const _ProcessedImage(this.spId, this.normalized);
}

class _ZipProcessingOutput {
  final List<_ProcessedImage> processed;
  final List<String> warnings;
  final int entriesScanned;
  final int imagesFound;
  final int unmatchedImages;

  const _ZipProcessingOutput({
    required this.processed,
    required this.warnings,
    required this.entriesScanned,
    required this.imagesFound,
    required this.unmatchedImages,
  });
}

Future<_ZipProcessingOutput> _processArchive(_ZipProcessingTask task) async {
  Uint8List bytes;
  final input = task.input;
  if (input.bytes != null) {
    bytes = input.bytes!;
  } else if (input.filePath != null) {
    bytes = await File(input.filePath!).readAsBytes();
  } else {
    throw const FormatException('Could not read avatar ZIP: no source bytes');
  }

  final archive = _decodeZipBytes(bytes);

  final processed = <_ProcessedImage>[];
  final warnings = <String>[];
  var entriesScanned = 0;
  var imagesFound = 0;
  var unmatchedImages = 0;

  for (final entry in archive.files) {
    entriesScanned++;
    if (!entry.isFile) continue;

    final fileName = p.posix.basename(entry.name.replaceAll('\\', '/'));
    final extension = p.posix.extension(fileName).toLowerCase();
    if (!_supportedImageExtensions.contains(extension)) continue;

    imagesFound++;
    final spId = p.posix.basenameWithoutExtension(fileName).trim();
    if (spId.isEmpty) {
      unmatchedImages++;
      continue;
    }

    if (entry.size > task.maxImageBytes) {
      warnings.add('Skipped oversized ZIP image: $fileName');
      continue;
    }

    // Skip the expensive decompress + decode for ids the caller has no
    // destination for. Without this, a system with 5 mapped members would
    // still pay full image decode cost for every other photo in the zip.
    if (!task.targetSpIds.contains(spId)) {
      unmatchedImages++;
      continue;
    }

    final raw = entry.readBytes();
    if (raw == null || raw.isEmpty) {
      warnings.add('Skipped empty ZIP image: $fileName');
      continue;
    }
    if (raw.length > task.maxImageBytes) {
      warnings.add('Skipped oversized ZIP image: $fileName');
      continue;
    }

    Uint8List? normalized;
    try {
      normalized = AvatarNormalizer.normalize(raw);
    } catch (_) {
      warnings.add('Skipped unsupported ZIP image: $fileName');
      continue;
    }

    if (normalized == null) continue;
    processed.add(_ProcessedImage(spId, normalized));
  }

  return _ZipProcessingOutput(
    processed: processed,
    warnings: warnings,
    entriesScanned: entriesScanned,
    imagesFound: imagesFound,
    unmatchedImages: unmatchedImages,
  );
}

Archive _decodeZipBytes(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    throw const FormatException('Could not read avatar ZIP: invalid ZIP');
  }

  try {
    return ZipDecoder().decodeBytes(bytes);
  } on ArchiveException catch (e) {
    throw FormatException('Could not read avatar ZIP: ${e.message}');
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Could not read avatar ZIP: $e');
  }
}
