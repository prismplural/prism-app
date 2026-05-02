import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV9Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded
      .into(seeded.members)
      .insert(
        MembersCompanion.insert(
          id: 'member-with-banner',
          name: 'Banner Member',
          createdAt: DateTime.utc(2026, 4, 29, 12),
          pkBannerUrl: const Value('https://example.invalid/banner.png'),
        ),
      );
  await seeded
      .into(seeded.members)
      .insert(
        MembersCompanion.insert(
          id: 'member-without-banner',
          name: 'No Banner Member',
          createdAt: DateTime.utc(2026, 4, 29, 13),
        ),
      );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_source');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_layout');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_visible');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_font');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_bold');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_italic');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_color_mode');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_color_hex');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_image_data');
    rawDb.execute('ALTER TABLE members DROP COLUMN pk_banner_image_data');
    rawDb.execute('ALTER TABLE members DROP COLUMN pk_banner_cached_url');
    rawDb.execute('PRAGMA user_version = 9;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v10 migration (member profile headers)', () {
    test('fresh schema has member profile header columns', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final columns = await db.customSelect('PRAGMA table_info(members)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('profile_header_source'));
      expect(names, contains('profile_header_layout'));
      expect(names, contains('profile_header_visible'));
      expect(names, contains('profile_header_image_data'));
      expect(names, contains('pk_banner_image_data'));
      expect(names, contains('pk_banner_cached_url'));
    });

    test(
      'v9 -> v10 adds header columns and leaves source default for URL-only rows',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v9_to_v10_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v9_to_v10.db');
        await _seedV9Db(dbFile);

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        // At v9 the rows have a URL but no resolved image bytes (the
        // column doesn't even exist yet). After the v10 migration the
        // image-data column is null, so the predicate must NOT flip the
        // source to PluralKit — a URL alone is not a useful banner.
        final withBanner = await (upgraded.select(
          upgraded.members,
        )..where((m) => m.id.equals('member-with-banner'))).getSingle();
        expect(withBanner.profileHeaderSource, 1);
        expect(withBanner.profileHeaderLayout, 0);
        expect(withBanner.profileHeaderVisible, isTrue);
        expect(withBanner.profileHeaderImageData, isNull);
        expect(withBanner.pkBannerImageData, isNull);
        expect(withBanner.pkBannerCachedUrl, isNull);

        final withoutBanner = await (upgraded.select(
          upgraded.members,
        )..where((m) => m.id.equals('member-without-banner'))).getSingle();
        expect(withoutBanner.profileHeaderSource, 1);
        expect(withoutBanner.profileHeaderLayout, 0);
        expect(withoutBanner.profileHeaderVisible, isTrue);

        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.first.read<int>('user_version'), 14);
      },
    );
  });
}
