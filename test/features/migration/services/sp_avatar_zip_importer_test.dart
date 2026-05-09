import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase, SpIdMapTableCompanion;
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late FakeMemberRepository memberRepo;
  late FakeSystemSettingsRepository settingsRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sp-avatar-zip-test-');
    db = AppDatabase(NativeDatabase.memory());
    memberRepo = FakeMemberRepository();
    settingsRepo = FakeSystemSettingsRepository();
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'updates matching member avatars without changing other fields',
    () async {
      final original = Member(
        id: 'prism-alice',
        name: 'Edited Alice',
        createdAt: DateTime.utc(2024),
        avatarImageData: _jpegBytes(0, 0, 0),
      );
      memberRepo.seed([original]);
      await db.spImportDao.upsertMapping(
        const SpIdMapTableCompanion(
          spId: Value('sp-alice'),
          entityType: Value('member'),
          prismId: Value('prism-alice'),
        ),
      );

      final replacement = _jpegBytes(220, 20, 20);
      final zipPath = await _writeZip(tempDir, {
        'sp-alice.jpg': replacement,
        'sp-unknown.jpg': _jpegBytes(20, 20, 220),
        'notes.txt': Uint8List.fromList([1, 2, 3]),
      });

      final result = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        settingsRepo: settingsRepo,
        spImportDao: db.spImportDao,
      );

      final updated = await memberRepo.getMemberById('prism-alice');
      expect(updated!.name, 'Edited Alice');
      expect(updated.avatarImageData, replacement);
      expect(result.imagesFound, 2);
      expect(result.memberAvatarsUpdated, 1);
      expect(result.unmatchedImages, 1);
    },
  );

  test(
    'updates the system avatar when paired export data has system id',
    () async {
      final bytes = _jpegBytes(20, 220, 20);
      final zipPath = await _writeZip(tempDir, {'sp-system.jpg': bytes});

      final result = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        settingsRepo: settingsRepo,
        spImportDao: db.spImportDao,
        exportData: _emptyExport(systemId: 'sp-system'),
      );

      expect(result.memberAvatarsUpdated, 0);
      expect(result.systemAvatarUpdated, isTrue);
      expect(settingsRepo.settings.systemAvatarData, bytes);
    },
  );

  test('reports no supported images for non-image zips', () async {
    final zipPath = await _writeZip(tempDir, {
      'readme.txt': Uint8List.fromList([1, 2, 3]),
    });

    final result = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      settingsRepo: settingsRepo,
      spImportDao: db.spImportDao,
    );

    expect(result.imagesFound, 0);
    expect(result.memberAvatarsUpdated, 0);
    expect(result.warnings.single, contains('No supported images'));
  });

  test('throws when the selected ZIP does not exist', () async {
    await expectLater(
      SpAvatarZipImporter().importZipFile(
        filePath: '${tempDir.path}/missing.zip',
        memberRepo: memberRepo,
        settingsRepo: settingsRepo,
        spImportDao: db.spImportDao,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('throws FormatException for invalid ZIP bytes', () async {
    final file = File('${tempDir.path}/not-a-zip.zip');
    await file.writeAsBytes([1, 2, 3, 4]);

    await expectLater(
      SpAvatarZipImporter().importZipFile(
        filePath: file.path,
        memberRepo: memberRepo,
        settingsRepo: settingsRepo,
        spImportDao: db.spImportDao,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('warns when a mapped ZIP image points to a missing member', () async {
    await db.spImportDao.upsertMapping(
      const SpIdMapTableCompanion(
        spId: Value('sp-missing'),
        entityType: Value('member'),
        prismId: Value('prism-missing'),
      ),
    );
    final zipPath = await _writeZip(tempDir, {
      'sp-missing.jpg': _jpegBytes(220, 20, 20),
    });

    final result = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      settingsRepo: settingsRepo,
      spImportDao: db.spImportDao,
    );

    expect(result.memberAvatarsUpdated, 0);
    expect(result.unmatchedImages, 1);
    expect(
      result.warnings,
      contains('Skipped ZIP image for missing member: sp-missing'),
    );
  });
}

Uint8List _jpegBytes(int r, int g, int b) {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<String> _writeZip(Directory dir, Map<String, Uint8List> files) async {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  final zipBytes = ZipEncoder().encode(archive);
  final file = File('${dir.path}/avatars.zip');
  await file.writeAsBytes(zipBytes);
  return file.path;
}

SpExportData _emptyExport({String? systemId}) => SpExportData(
  members: const [],
  customFronts: const [],
  frontHistory: const [],
  groups: const [],
  channels: const [],
  messages: const [],
  polls: const [],
  systemId: systemId,
);
