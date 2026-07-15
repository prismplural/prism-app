import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase, MembersCompanion, SpIdMapTableCompanion;
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/normalized_avatar_batch_writer.dart';
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late FakeMemberRepository memberRepo;
  late FakeSystemSettingsRepository settingsRepo;
  late _FakeNormalizedAvatarBatchWriter avatarBatchWriter;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sp-avatar-zip-test-');
    db = AppDatabase(NativeDatabase.memory());
    memberRepo = FakeMemberRepository();
    settingsRepo = FakeSystemSettingsRepository();
    avatarBatchWriter = _FakeNormalizedAvatarBatchWriter(memberRepo);
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
      await _mapMember(db, 'sp-alice', 'prism-alice');

      final replacement = _jpegBytes(220, 20, 20);
      final zipPath = await _writeZip(tempDir, {
        'sp-alice.jpg': replacement,
        'sp-unknown.jpg': _jpegBytes(20, 20, 220),
        'notes.txt': Uint8List.fromList([1, 2, 3]),
      });

      final result = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        settingsRepo: settingsRepo,
        spImportDao: db.spImportDao,
      );

      final updated = await memberRepo.getMemberById('prism-alice');
      expect(updated!.name, 'Edited Alice');
      expect(updated.avatarImageData, replacement);
      expect(result.imagesFound, 2);
      expect(result.memberAvatarsUpdated, 1);
      expect(result.memberIdsUpdated, {'prism-alice'});
      expect(result.unmatchedImages, 1);
      expect(result.completion, SpAvatarZipImportCompletion.complete);
    },
  );

  test(
    'updates the system avatar when export data has its system id',
    () async {
      final bytes = _jpegBytes(20, 220, 20);
      final zipPath = await _writeZip(tempDir, {'sp-system.jpg': bytes});

      final result = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
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
      avatarBatchWriter: avatarBatchWriter,
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
        avatarBatchWriter: avatarBatchWriter,
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
        avatarBatchWriter: avatarBatchWriter,
        settingsRepo: settingsRepo,
        spImportDao: db.spImportDao,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('warns and continues for an image declaring too many pixels', () async {
    memberRepo.seed([
      Member(id: 'prism-alice', name: 'Alice', createdAt: DateTime.utc(2024)),
    ]);
    await _mapMember(db, 'sp-alice', 'prism-alice');
    final zipPath = await _writeZip(tempDir, {
      'sp-alice.jpg': _jpegWithDeclaredDimensions(8000, 8000),
    });

    final result = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      avatarBatchWriter: avatarBatchWriter,
      settingsRepo: settingsRepo,
      spImportDao: db.spImportDao,
    );

    expect(result.memberAvatarsUpdated, 0);
    expect(result.warnings, contains('Skipped 1 unsupported ZIP image(s).'));
  });

  test('reports mapped images whose members are missing', () async {
    await _mapMember(db, 'sp-missing', 'prism-missing');
    final zipPath = await _writeZip(tempDir, {
      'sp-missing.jpg': _jpegBytes(220, 20, 20),
    });

    final result = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      avatarBatchWriter: avatarBatchWriter,
      settingsRepo: settingsRepo,
      spImportDao: db.spImportDao,
    );

    expect(result.memberAvatarsUpdated, 0);
    expect(result.unmatchedImages, 1);
    expect(result.memberIdsMissingOrDeleted, {'prism-missing'});
    expect(
      result.warnings,
      contains('Skipped 1 avatar(s) for missing or deleted members.'),
    );
  });

  test('system avatar retry is successful without a duplicate write', () async {
    final countingSettings = _CountingSystemSettingsRepository();
    final bytes = _jpegBytes(20, 220, 20);
    final zipPath = await _writeZip(tempDir, {'sp-system.jpg': bytes});

    final first = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      avatarBatchWriter: avatarBatchWriter,
      settingsRepo: countingSettings,
      spImportDao: db.spImportDao,
      exportData: _emptyExport(systemId: 'sp-system'),
    );
    final retry = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      avatarBatchWriter: avatarBatchWriter,
      settingsRepo: countingSettings,
      spImportDao: db.spImportDao,
      exportData: _emptyExport(systemId: 'sp-system'),
    );

    expect(first.systemAvatarUpdated, isTrue);
    expect(retry.systemAvatarUpdated, isTrue);
    expect(countingSettings.avatarWriteCount, 1);
  });

  test(
    'excluded linked members are never offered to the batch writer',
    () async {
      memberRepo.seed([
        Member(
          id: 'prism-linked',
          name: 'Linked',
          createdAt: DateTime.utc(2024),
        ),
      ]);
      await _mapMember(db, 'sp-linked', 'prism-linked');
      final zipPath = await _writeZip(tempDir, {
        'sp-linked.jpg': _jpegBytes(220, 20, 20),
      });

      final result = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        spImportDao: db.spImportDao,
        skipMemberIds: const {'prism-linked'},
      );

      expect(avatarBatchWriter.calls, 0);
      expect(result.memberIdsUpdated, isEmpty);
      expect(result.unmatchedImages, 1);
    },
  );

  test('progress is monotonic and ends at committed terminal state', () async {
    const count = 40;
    await _seedFakeMembersAndMappings(db, memberRepo, count);
    final zipPath = await _writeZip(tempDir, {
      for (var i = 0; i < count; i++) 'sp-$i.jpg': _jpegBytes(i % 255, 20, 30),
    });
    final progress = <SpAvatarZipProgress>[];

    final result = await SpAvatarZipImporter().importZipFile(
      filePath: zipPath,
      memberRepo: memberRepo,
      avatarBatchWriter: avatarBatchWriter,
      spImportDao: db.spImportDao,
      onProgress: progress.add,
    );

    expect(progress.first.phase, SpAvatarZipProgressPhase.scanning);
    expect(progress[1].phase, SpAvatarZipProgressPhase.normalizingAndSaving);
    expect(progress[1].processedCandidates, 0);
    expect(progress[1].totalCandidates, count);
    expect(progress.last.phase, SpAvatarZipProgressPhase.complete);
    expect(progress.last.processedCandidates, count);
    expect(progress.last.committedMemberUpdates, count);
    expect(result.memberAvatarsUpdated, count);
    for (var i = 1; i < progress.length; i++) {
      expect(
        progress[i].processedCandidates,
        greaterThanOrEqualTo(progress[i - 1].processedCandidates),
      );
      expect(
        progress[i].committedMemberUpdates,
        greaterThanOrEqualTo(progress[i - 1].committedMemberUpdates),
      );
    }
  });

  test('a first-batch failure throws a sanitized error', () async {
    await _seedFakeMembersAndMappings(db, memberRepo, 1);
    final zipPath = await _writeZip(tempDir, {'sp-0.jpg': _jpegBytes(1, 2, 3)});
    avatarBatchWriter.failOnCall = 1;

    await expectLater(
      SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        spImportDao: db.spImportDao,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Could not save avatar images from ZIP.',
        ),
      ),
    );
  });

  test(
    'returns partial after a later batch fails and retry is idempotent',
    () async {
      const count = 40;
      await _seedFakeMembersAndMappings(db, memberRepo, count);
      final image = _jpegBytes(70, 80, 90);
      final zipPath = await _writeZip(tempDir, {
        for (var i = 0; i < count; i++) 'sp-$i.jpg': image,
      });
      avatarBatchWriter.failOnCall = 2;
      final partialProgress = <SpAvatarZipProgress>[];

      final partial = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        spImportDao: db.spImportDao,
        onProgress: partialProgress.add,
      );

      expect(partial.completion, SpAvatarZipImportCompletion.partial);
      expect(partial.memberAvatarsUpdated, 32);
      expect(partial.warnings.first, contains('stopped after saving 32 of 40'));
      expect(partialProgress.last.phase, SpAvatarZipProgressPhase.complete);
      expect(partialProgress.last.processedCandidates, 32);
      expect(partialProgress.last.totalCandidates, count);

      final writesBeforeRetry = avatarBatchWriter.writeCount;
      final retry = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        spImportDao: db.spImportDao,
      );

      expect(retry.completion, SpAvatarZipImportCompletion.complete);
      expect(retry.memberAvatarsUpdated, 8);
      expect(retry.memberAvatarsUnchanged, 32);
      expect(avatarBatchWriter.writeCount - writesBeforeRetry, 8);

      final secondRetry = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        spImportDao: db.spImportDao,
      );
      expect(secondRetry.memberAvatarsUpdated, 0);
      expect(secondRetry.memberAvatarsUnchanged, count);
    },
  );

  test(
    'bytes input is spooled before progress and deleted after success',
    () async {
      memberRepo.seed([
        Member(id: 'prism-a', name: 'A', createdAt: DateTime.utc(2024)),
      ]);
      await _mapMember(db, 'sp-a', 'prism-a');
      final spoolDir = await Directory('${tempDir.path}/spool').create();
      final bytes = _zipBytes({'sp-a.jpg': _jpegBytes(1, 2, 3)});
      var sourceExistedAtFirstProgress = false;
      var callbacks = 0;

      final result =
          await SpAvatarZipImporter(
            temporaryDirectory: () async => spoolDir,
          ).importZipFileBytes(
            bytes: bytes,
            memberRepo: memberRepo,
            avatarBatchWriter: avatarBatchWriter,
            spImportDao: db.spImportDao,
            onProgress: (_) {
              callbacks++;
              if (callbacks == 1) {
                sourceExistedAtFirstProgress = spoolDir
                    .listSync()
                    .whereType<File>()
                    .isNotEmpty;
              }
            },
          );

      expect(result.memberAvatarsUpdated, 1);
      expect(sourceExistedAtFirstProgress, isTrue);
      expect(spoolDir.listSync(), isEmpty);
    },
  );

  test('bytes input cache file is deleted when worker parsing fails', () async {
    final spoolDir = await Directory('${tempDir.path}/spool-failure').create();
    final phases = <SpAvatarZipProgressPhase>[];

    await expectLater(
      SpAvatarZipImporter(
        temporaryDirectory: () async => spoolDir,
      ).importZipFileBytes(
        bytes: const [1, 2, 3, 4],
        memberRepo: memberRepo,
        avatarBatchWriter: avatarBatchWriter,
        spImportDao: db.spImportDao,
        onProgress: (progress) => phases.add(progress.phase),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(phases, [SpAvatarZipProgressPhase.scanning]);
    expect(spoolDir.listSync(), isEmpty);
  });

  test(
    'streams 5000 avatars through real Drift without retaining all output',
    () async {
      const count = 5000;
      final driftRepo = DriftMemberRepository(db.membersDao, null);
      await db.batch((batch) {
        for (var i = 0; i < count; i++) {
          batch.insert(
            db.members,
            MembersCompanion.insert(
              id: 'prism-$i',
              name: 'Member $i',
              createdAt: DateTime.utc(2024),
            ),
          );
        }
      });
      await db.spImportDao.upsertMappings([
        for (var i = 0; i < count; i++)
          SpIdMapTableCompanion(
            spId: Value('sp-$i'),
            entityType: const Value('member'),
            prismId: Value('prism-$i'),
          ),
      ]);
      final image = _jpegBytes(11, 22, 33);
      final zipPath = await _writeZip(tempDir, {
        for (var i = 0; i < count; i++) 'sp-$i.jpg': image,
      });

      final result = await SpAvatarZipImporter().importZipFile(
        filePath: zipPath,
        memberRepo: driftRepo,
        avatarBatchWriter: driftRepo,
        spImportDao: db.spImportDao,
      );

      expect(result.completion, SpAvatarZipImportCompletion.complete);
      expect(result.memberAvatarsUpdated, count);
      expect(result.memberIdsUpdated, hasLength(count));
      final stored = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM members WHERE avatar_image_data IS NOT NULL',
          )
          .getSingle();
      expect(stored.read<int>('c'), count);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _FakeNormalizedAvatarBatchWriter implements NormalizedAvatarBatchWriter {
  final FakeMemberRepository memberRepo;
  int calls = 0;
  int writeCount = 0;
  int? failOnCall;

  _FakeNormalizedAvatarBatchWriter(this.memberRepo);

  @override
  Future<NormalizedAvatarBatchResult> applyNormalizedAvatarBatch(
    Map<String, Uint8List> bytesByMemberId,
  ) async {
    calls++;
    if (calls == failOnCall) throw StateError('injected batch failure');

    final updated = <String>{};
    final unchanged = <String>{};
    final missing = <String>{};
    for (final entry in bytesByMemberId.entries) {
      final member = await memberRepo.getMemberById(entry.key);
      if (member == null || member.isDeleted) {
        missing.add(entry.key);
      } else if (_bytesEqual(member.avatarImageData, entry.value)) {
        unchanged.add(entry.key);
      } else {
        await memberRepo.updateMember(
          member.copyWith(avatarImageData: entry.value),
        );
        writeCount++;
        updated.add(entry.key);
      }
    }
    return NormalizedAvatarBatchResult(
      requested: bytesByMemberId.length,
      updatedMemberIds: updated,
      unchangedMemberIds: unchanged,
      missingOrDeletedMemberIds: missing,
    );
  }
}

class _CountingSystemSettingsRepository extends FakeSystemSettingsRepository {
  int avatarWriteCount = 0;

  @override
  Future<void> updateSystemAvatarData(Uint8List? value) async {
    avatarWriteCount++;
    await super.updateSystemAvatarData(value);
  }
}

bool _bytesEqual(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> _mapMember(AppDatabase db, String spId, String prismId) =>
    db.spImportDao.upsertMapping(
      SpIdMapTableCompanion(
        spId: Value(spId),
        entityType: const Value('member'),
        prismId: Value(prismId),
      ),
    );

Future<void> _seedFakeMembersAndMappings(
  AppDatabase db,
  FakeMemberRepository memberRepo,
  int count,
) async {
  memberRepo.seed([
    for (var i = 0; i < count; i++)
      Member(id: 'prism-$i', name: 'Member $i', createdAt: DateTime.utc(2024)),
  ]);
  await db.spImportDao.upsertMappings([
    for (var i = 0; i < count; i++)
      SpIdMapTableCompanion(
        spId: Value('sp-$i'),
        entityType: const Value('member'),
        prismId: Value('prism-$i'),
      ),
  ]);
}

Uint8List _jpegWithDeclaredDimensions(int width, int height) {
  final source = img.Image(width: 2, height: 2);
  img.fill(source, color: img.ColorRgb8(1, 2, 3));
  final encoded = Uint8List.fromList(img.encodeJpg(source));
  for (var i = 0; i < encoded.length - 9; i++) {
    if (encoded[i] == 0xFF && encoded[i + 1] == 0xC0) {
      encoded[i + 5] = (height >> 8) & 0xFF;
      encoded[i + 6] = height & 0xFF;
      encoded[i + 7] = (width >> 8) & 0xFF;
      encoded[i + 8] = width & 0xFF;
      return encoded;
    }
  }
  throw StateError('no SOF0 marker found in encoded JPEG');
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
  final file = File('${dir.path}/avatars.zip');
  await file.writeAsBytes(_zipBytes(files));
  return file.path;
}

Uint8List _zipBytes(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
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
