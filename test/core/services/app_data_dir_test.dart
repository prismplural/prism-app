import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prism_plurality/core/services/app_data_dir.dart';

void main() {
  group('migrateWindowsLegacyAppSupportDirIfNeeded', () {
    late Directory tempDir;
    late Directory currentDir;
    late Directory legacyDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('prism_app_data_test_');
      currentDir = Directory(p.join(tempDir.path, 'Prism Plural', 'Prism'));
      legacyDir = Directory(
        p.join(tempDir.path, 'com.prismplural', 'prism_plurality'),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<bool> noCurrentUserData(Directory _) async => false;
    Future<void> skipVerification(Directory _) async {}

    test('is a no-op without injected directories on non-Windows', () async {
      if (Platform.isWindows) return;

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded();

      expect(result.migrated, isFalse);
      expect(result.reason, 'not-windows');
    });

    test(
      'moves legacy data into branded path and backs up current data',
      () async {
        await legacyDir.create(recursive: true);
        await File(p.join(legacyDir.path, 'prism.db')).writeAsString('old-db');
        await File(
          p.join(legacyDir.path, 'flutter_secure_storage.dat'),
        ).writeAsString('old-key');
        await File(
          p.join(legacyDir.path, 'shared_preferences.json'),
        ).writeAsString('{"sentinel":true}');
        await Directory(p.join(legacyDir.path, 'prism_media')).create();
        await File(
          p.join(legacyDir.path, 'prism_media', 'avatar.bin'),
        ).writeAsString('old-media');

        await currentDir.create(recursive: true);
        await File(
          p.join(currentDir.path, 'prism.db'),
        ).writeAsString('blank-db');

        final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
          currentDir: currentDir,
          legacyDir: legacyDir,
          now: () => DateTime.utc(2026, 5, 19, 12, 34, 56),
          currentHasUserData: noCurrentUserData,
          verifyRestoredData: skipVerification,
        );

        expect(result.migrated, isTrue);
        expect(result.backupPath, isNotNull);
        expect(
          await File(p.join(currentDir.path, 'prism.db')).readAsString(),
          'old-db',
        );
        expect(
          await File(
            p.join(currentDir.path, 'flutter_secure_storage.dat'),
          ).readAsString(),
          'old-key',
        );
        expect(
          await File(
            p.join(currentDir.path, 'prism_media', 'avatar.bin'),
          ).readAsString(),
          'old-media',
        );
        expect(
          await File(p.join(result.backupPath!, 'prism.db')).readAsString(),
          'blank-db',
        );
        expect(
          await File(
            p.join(currentDir.path, '.prism_windows_app_data_migrated_v1'),
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            p.join(
              legacyDir.path,
              '.prism_windows_app_data_migrated_to_prism_v1',
            ),
          ).exists(),
          isTrue,
        );
      },
    );

    test('migrates into an empty current directory without backup', () async {
      await legacyDir.create(recursive: true);
      await File(p.join(legacyDir.path, 'prism.db')).writeAsString('old-db');
      await currentDir.create(recursive: true);

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
        currentDir: currentDir,
        legacyDir: legacyDir,
        currentHasUserData: noCurrentUserData,
        verifyRestoredData: skipVerification,
      );

      expect(result.migrated, isTrue);
      expect(result.backupPath, isNull);
      expect(
        await File(p.join(currentDir.path, 'prism.db')).readAsString(),
        'old-db',
      );
    });

    test('skips when current directory already has migration marker', () async {
      await legacyDir.create(recursive: true);
      await File(p.join(legacyDir.path, 'prism.db')).writeAsString('old-db');
      await currentDir.create(recursive: true);
      await File(
        p.join(currentDir.path, '.prism_windows_app_data_migrated_v1'),
      ).writeAsString('already');

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
        currentDir: currentDir,
        legacyDir: legacyDir,
      );

      expect(result.migrated, isFalse);
      expect(result.reason, 'already-migrated');
    });

    test('skips when legacy directory already has migration marker', () async {
      await legacyDir.create(recursive: true);
      await File(p.join(legacyDir.path, 'prism.db')).writeAsString('old-db');
      await File(
        p.join(legacyDir.path, '.prism_windows_app_data_migrated_to_prism_v1'),
      ).writeAsString('already');

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
        currentDir: currentDir,
        legacyDir: legacyDir,
      );

      expect(result.migrated, isFalse);
      expect(result.reason, 'legacy-already-migrated');
    });

    test('skips when current directory contains user data', () async {
      await legacyDir.create(recursive: true);
      await File(p.join(legacyDir.path, 'prism.db')).writeAsString('old-db');
      await currentDir.create(recursive: true);
      await File(p.join(currentDir.path, 'prism.db')).writeAsString('new-db');

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
        currentDir: currentDir,
        legacyDir: legacyDir,
        currentHasUserData: (_) async => true,
      );

      expect(result.migrated, isFalse);
      expect(result.reason, 'current-has-user-data');
      expect(
        await File(p.join(currentDir.path, 'prism.db')).readAsString(),
        'new-db',
      );
      expect(
        await File(p.join(legacyDir.path, 'prism.db')).readAsString(),
        'old-db',
      );
    });

    test('skips when legacy directory has no Prism data', () async {
      await legacyDir.create(recursive: true);
      await File(p.join(legacyDir.path, 'unrelated.txt')).writeAsString('x');

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
        currentDir: currentDir,
        legacyDir: legacyDir,
      );

      expect(result.migrated, isFalse);
      expect(result.reason, 'no-legacy-data');
      expect(await currentDir.exists(), isFalse);
    });

    test('rolls back current and restores legacy when copy fails', () async {
      await legacyDir.create(recursive: true);
      await File(p.join(legacyDir.path, 'prism.db')).writeAsString('old-db');
      await currentDir.create(recursive: true);
      await File(p.join(currentDir.path, 'prism.db')).writeAsString('new-db');

      final result = await migrateWindowsLegacyAppSupportDirIfNeeded(
        currentDir: currentDir,
        legacyDir: legacyDir,
        currentHasUserData: noCurrentUserData,
        verifyRestoredData: skipVerification,
        copyDirectory: (source, destination) async {
          await destination.create(recursive: true);
          await File(
            p.join(destination.path, 'partial'),
          ).writeAsString(source.path);
          throw StateError('copy failed');
        },
      );

      expect(result.migrated, isFalse);
      expect(result.reason, 'migration-failed');
      expect(
        await File(p.join(currentDir.path, 'prism.db')).readAsString(),
        'new-db',
      );
      expect(
        await File(p.join(legacyDir.path, 'prism.db')).readAsString(),
        'old-db',
      );
      expect(
        await File(
          p.join(currentDir.path, '.prism_windows_app_data_migrated_v1'),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          p.join(
            legacyDir.parent.path,
            'prism_plurality.migration-in-progress',
          ),
        ).exists(),
        isFalse,
      );
    });
  });
}
