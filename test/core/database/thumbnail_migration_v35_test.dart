import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a v34 database: materialise the current schema via [AppDatabase], then
/// drop the thumbnail thumbnail-hash columns and reset PRAGMA user_version = 34 so the
/// v34→v35 migration is forced to run (and add them back) on the next open.
Future<void> _seedV34Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute(
      'ALTER TABLE media_attachments DROP COLUMN thumbnail_content_hash',
    );
    rawDb.execute(
      'ALTER TABLE media_attachments DROP COLUMN thumbnail_plaintext_hash',
    );
    rawDb.execute('PRAGMA user_version = 34;');
  } finally {
    rawDb.close();
  }
}

Set<String> _columns(String path) {
  final db = raw.sqlite3.open(path);
  try {
    return db
        .select('PRAGMA table_info(media_attachments)')
        .map((r) => r['name'] as String)
        .toSet();
  } finally {
    db.close();
  }
}

void main() {
  test('v34→v35 migration adds the thumbnail-hash columns', () async {
    final dir = await Directory.systemTemp.createTemp('thumb_migration');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/app.db');

    await _seedV34Db(dbFile);

    // Pre-migration: the columns are gone.
    final before = _columns(dbFile.path);
    expect(before.contains('thumbnail_content_hash'), isFalse);
    expect(before.contains('thumbnail_plaintext_hash'), isFalse);

    // Reopen → onUpgrade 34→35 runs.
    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);
    await upgraded.customSelect('SELECT 1').get();

    // The columns exist again and a row round-trips through them.
    final after = _columns(dbFile.path);
    expect(after.contains('thumbnail_content_hash'), isTrue);
    expect(after.contains('thumbnail_plaintext_hash'), isTrue);

    await upgraded
        .into(upgraded.mediaAttachments)
        .insert(
          MediaAttachmentsCompanion.insert(
            id: 'att-1',
            mediaId: const Value('full-1'),
            thumbnailMediaId: const Value('thumb-1'),
            thumbnailContentHash: const Value('tc-hash'),
            thumbnailPlaintextHash: const Value('tp-hash'),
          ),
        );
    final row = await (upgraded.select(
      upgraded.mediaAttachments,
    )..where((t) => t.id.equals('att-1'))).getSingle();
    expect(row.thumbnailContentHash, 'tc-hash');
    expect(row.thumbnailPlaintextHash, 'tp-hash');
  });

  test('opening a current-schema DB at v35 is a no-op (idempotent)', () async {
    final dir = await Directory.systemTemp.createTemp('thumb_migration2');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/app.db');

    // Materialise current schema (columns present), force version back to 34
    // WITHOUT dropping them — the guarded addColumn must not throw.
    final seeded = AppDatabase(NativeDatabase(dbFile));
    await seeded.customSelect('SELECT 1').get();
    await seeded.close();
    final rawDb = raw.sqlite3.open(dbFile.path);
    rawDb.execute('PRAGMA user_version = 34;');
    rawDb.close();

    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);
    await upgraded.customSelect('SELECT 1').get();
    expect(_columns(dbFile.path).contains('thumbnail_content_hash'), isTrue);
  });
}
