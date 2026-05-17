import 'dart:io';
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

/// Imports Simply Plural's separate avatar ZIP export.
///
/// SP names each exported image by the source entity id. Prism already keeps
/// the SP member id -> Prism member id map after imports, so this service can
/// repair member photos without touching any non-avatar fields.
class SpAvatarZipImporter {
  static const _supportedImageExtensions = {
    '.gif',
    '.jpeg',
    '.jpg',
    '.png',
    '.webp',
  };

  static const _maxImageBytes = 20 * 1024 * 1024;

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

    return _importArchiveFiles(
      archiveFiles: _decodeZip(await file.readAsBytes()).files,
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
    return _importArchiveFiles(
      archiveFiles: _decodeZip(bytes).files,
      memberRepo: memberRepo,
      settingsRepo: settingsRepo,
      spImportDao: spImportDao,
      exportData: exportData,
      skipMemberIds: skipMemberIds,
      stopwatch: stopwatch,
    );
  }

  Future<SpAvatarZipImportResult> _importArchiveFiles({
    required List<ArchiveFile> archiveFiles,
    required MemberRepository memberRepo,
    SystemSettingsRepository? settingsRepo,
    SpImportDao? spImportDao,
    SpExportData? exportData,
    Set<String> skipMemberIds = const {},
    required Stopwatch stopwatch,
  }) async {
    final memberMappings = await _loadMemberMappings(spImportDao);
    final systemId = exportData?.systemId?.trim();
    final warnings = <String>[];

    var entriesScanned = 0;
    var imagesFound = 0;
    var memberAvatarsUpdated = 0;
    var systemAvatarUpdated = false;
    var unmatchedImages = 0;

    for (final entry in archiveFiles) {
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

      if (entry.size > _maxImageBytes) {
        warnings.add('Skipped oversized ZIP image: $fileName');
        continue;
      }

      final normalized = _normalizedBytes(entry, fileName, warnings);
      if (normalized == null) continue;

      if (systemId != null && systemId.isNotEmpty && spId == systemId) {
        if (settingsRepo != null) {
          await settingsRepo.updateSystemAvatarData(normalized);
          systemAvatarUpdated = true;
        }
        continue;
      }

      final memberId = memberMappings[spId];
      if (memberId == null) {
        unmatchedImages++;
        continue;
      }
      if (skipMemberIds.contains(memberId)) {
        continue;
      }

      final current = await memberRepo.getMemberById(memberId);
      if (current == null) {
        warnings.add('Skipped ZIP image for missing member: $spId');
        unmatchedImages++;
        continue;
      }

      await memberRepo.updateMember(
        current.copyWith(avatarImageData: normalized),
      );
      memberAvatarsUpdated++;
    }

    if (imagesFound == 0) {
      warnings.add('No supported images were found in the avatar ZIP.');
    } else if (unmatchedImages > 0) {
      warnings.add(
        'Skipped $unmatchedImages ZIP image(s) that did not match imported '
        'Simply Plural members.',
      );
    }

    stopwatch.stop();
    return SpAvatarZipImportResult(
      entriesScanned: entriesScanned,
      imagesFound: imagesFound,
      memberAvatarsUpdated: memberAvatarsUpdated,
      systemAvatarUpdated: systemAvatarUpdated,
      unmatchedImages: unmatchedImages,
      warnings: warnings,
      duration: stopwatch.elapsed,
    );
  }

  Archive _decodeZip(List<int> bytes) {
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

  Uint8List? _normalizedBytes(
    ArchiveFile entry,
    String fileName,
    List<String> warnings,
  ) {
    final raw = entry.readBytes();
    if (raw == null || raw.isEmpty) {
      warnings.add('Skipped empty ZIP image: $fileName');
      return null;
    }
    if (raw.length > _maxImageBytes) {
      warnings.add('Skipped oversized ZIP image: $fileName');
      return null;
    }

    try {
      return AvatarNormalizer.normalize(raw);
    } catch (_) {
      warnings.add('Skipped unsupported ZIP image: $fileName');
      return null;
    }
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
