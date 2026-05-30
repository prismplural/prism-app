import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';

/// Reshapes the open-able db file's `members.age` column from the current TEXT
/// shape back into a real INTEGER column (the v30 shape) and stamps
/// `user_version`. The current schema declares `age` as TEXT, so without this
/// the v31 INTEGER → TEXT `cast<String>()` transform would never be exercised.
///
/// [ageById] maps member id → the integer age to write (null leaves it NULL).
/// Members must already exist in the file. After reshaping, the stored
/// `user_version` is set to [userVersion] so reopening runs the migration
/// chain from there.
void _reshapeAgeToIntegerAndDowngrade(
  File dbFile, {
  required Map<String, int?> ageById,
  required int userVersion,
  void Function(raw.Database db)? extraSetup,
}) {
  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('ALTER TABLE members DROP COLUMN age');
    rawDb.execute('ALTER TABLE members ADD COLUMN age INTEGER');

    // Sanity-check the column really is INTEGER, so a future schema change
    // can't silently turn the cast assertions into no-ops.
    final preCols = rawDb.select('PRAGMA table_info(members)');
    final ageType = preCols.firstWhere((r) => r['name'] == 'age')['type'];
    if ((ageType as String).toUpperCase() != 'INTEGER') {
      throw StateError('Seed setup failed: age column is $ageType, not INTEGER');
    }

    for (final entry in ageById.entries) {
      rawDb.execute('UPDATE members SET age = ? WHERE id = ?', [
        entry.value,
        entry.key,
      ]);
    }

    extraSetup?.call(rawDb);

    rawDb.execute('PRAGMA user_version = $userVersion');
  } finally {
    rawDb.close();
  }
}

/// Builds the current schema in a temp file, inserts [seed] through the real
/// Drift companion API (so every non-age column is encoded exactly as Drift
/// would on disk), then reshapes age to INTEGER + downgrades to [userVersion].
Future<File> _seedDb(
  String name, {
  required Future<void> Function(AppDatabase db) seed,
  required Map<String, int?> ageById,
  int userVersion = 30,
  void Function(raw.Database db)? extraSetup,
}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seed(seeded);
  await seeded.close();

  _reshapeAgeToIntegerAndDowngrade(
    dbFile,
    ageById: ageById,
    userVersion: userVersion,
    extraSetup: extraSetup,
  );
  return dbFile;
}

Future<int> _ageColumnIsText(AppDatabase db) async {
  final cols = await db.customSelect('PRAGMA table_info(members)').get();
  final ageCol = cols.firstWhere((row) => row.read<String>('name') == 'age');
  expect(
    ageCol.read<String>('type').toUpperCase(),
    contains('TEXT'),
    reason: 'age column should be TEXT after v31',
  );
  final version = await db.customSelect('PRAGMA user_version').getSingle();
  return version.read<int>('user_version');
}

void main() {
  group('schema v30 → v31: age column INT → TEXT', () {
    test('migrates integer age to string and preserves NULL age', () async {
      final dbFile = await _seedDb(
        'prism_migration_v30_to_v31_basic_',
        seed: (db) async {
          await db.into(db.members).insert(
            MembersCompanion.insert(
              id: 'member-age27',
              name: 'AgeTest',
              createdAt: DateTime.utc(2026, 5, 27),
            ),
          );
          await db.into(db.members).insert(
            MembersCompanion.insert(
              id: 'member-null-age',
              name: 'NullAge',
              createdAt: DateTime.utc(2026, 5, 27),
            ),
          );
        },
        ageById: {'member-age27': 27, 'member-null-age': null},
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      expect(await _ageColumnIsText(upgraded), 31);

      final ageRow = await upgraded.membersDao.getMemberById('member-age27');
      expect(ageRow, isNotNull);
      expect(ageRow!.age, '27');

      final nullAgeRow = await upgraded.membersDao.getMemberById(
        'member-null-age',
      );
      expect(nullAgeRow, isNotNull);
      expect(nullAgeRow!.age, isNull);
    });

    test('edge integer ages stringify correctly (0, big, negative)', () async {
      // age=0 must NOT become NULL (falsy-int trap); a value beyond int32 must
      // survive; a negative must keep its sign.
      const cases = <String, ({int seeded, String expected})>{
        'm-zero': (seeded: 0, expected: '0'),
        'm-big': (seeded: 9999999999, expected: '9999999999'),
        'm-neg': (seeded: -1, expected: '-1'),
      };

      final dbFile = await _seedDb(
        'prism_migration_v30_to_v31_edge_',
        seed: (db) async {
          for (final id in cases.keys) {
            await db.into(db.members).insert(
              MembersCompanion.insert(
                id: id,
                name: id,
                createdAt: DateTime.utc(2026, 5, 27),
              ),
            );
          }
        },
        ageById: {for (final e in cases.entries) e.key: e.value.seeded},
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      expect(await _ageColumnIsText(upgraded), 31);

      for (final entry in cases.entries) {
        final row = await upgraded.membersDao.getMemberById(entry.key);
        expect(row, isNotNull, reason: '${entry.key} should still exist');
        expect(
          row!.age,
          entry.value.expected,
          reason: '${entry.key}: ${entry.value.seeded} should stringify',
        );
        expect(row.age, isNotNull, reason: '${entry.key} must not become NULL');
      }
    });

    test('row count and primary-key identity are preserved', () async {
      const n = 12;
      final dbFile = await _seedDb(
        'prism_migration_v30_to_v31_count_',
        seed: (db) async {
          for (var i = 0; i < n; i++) {
            await db.into(db.members).insert(
              MembersCompanion.insert(
                id: 'member-$i',
                name: 'Member $i',
                createdAt: DateTime.utc(2026, 5, 27),
              ),
            );
          }
        },
        // Mix of set and NULL ages across the rows.
        ageById: {
          for (var i = 0; i < n; i++) 'member-$i': i.isEven ? i : null,
        },
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      expect(await _ageColumnIsText(upgraded), 31);

      final countRow = await upgraded
          .customSelect('SELECT COUNT(*) AS c FROM members')
          .getSingle();
      expect(
        countRow.read<int>('c'),
        n,
        reason: 'TableMigration must not lose or duplicate rows',
      );

      for (var i = 0; i < n; i++) {
        final row = await upgraded.membersDao.getMemberById('member-$i');
        expect(row, isNotNull, reason: 'member-$i should survive migration');
        expect(row!.name, 'Member $i');
        expect(row.age, i.isEven ? '$i' : isNull);
      }
    });

    test('all other member columns survive the table recreation', () async {
      // TableMigration recreates the whole members table; prove no collateral
      // damage by populating as many non-default columns as exist at v30 and
      // asserting every one round-trips byte-for-byte.
      final createdAt = DateTime.utc(2025, 3, 1, 8, 30, 15);
      final boardReadAt = DateTime.utc(2026, 2, 14, 9, 0, 0);

      final dbFile = await _seedDb(
        'prism_migration_v30_to_v31_cols_',
        seed: (db) async {
          await db.into(db.members).insert(
            MembersCompanion.insert(
              id: 'fully-loaded',
              name: 'Fully Loaded',
              createdAt: createdAt,
              pronouns: const Value('they/them'),
              emoji: const Value('🦊'),
              bio: const Value('A long bio with **markdown**.'),
              isActive: const Value(false),
              displayOrder: const Value(7),
              isAdmin: const Value(true),
              customColorEnabled: const Value(true),
              customColorHex: const Value('#FF8800'),
              parentSystemId: const Value('parent-sys-1'),
              pluralkitUuid: const Value('pk-uuid-123'),
              pluralkitId: const Value('abcde'),
              pluralkitDisplayName: const Value('PK Display'),
              displayName: const Value('Full Display Name'),
              birthday: const Value('1990-07-04'),
              proxyTagsJson: const Value('[{"prefix":"[","suffix":"]"}]'),
              pkBannerUrl: const Value('https://cdn.example/banner.png'),
              profileHeaderSource: const Value(2),
              profileHeaderLayout: const Value(1),
              profileHeaderVisible: const Value(false),
              nameStyleFont: const Value(3),
              nameStyleBold: const Value(false),
              nameStyleItalic: const Value(true),
              nameStyleColorMode: const Value(2),
              nameStyleColorHex: const Value('#00CC44'),
              pkBannerCachedUrl: const Value('https://cdn.example/cached.png'),
              pluralkitSyncIgnored: const Value(true),
              markdownEnabled: const Value(false),
              isDeleted: const Value(true),
              isAlwaysFronting: const Value(true),
              boardLastReadAt: Value(boardReadAt),
            ),
          );
        },
        ageById: {'fully-loaded': 42},
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      expect(await _ageColumnIsText(upgraded), 31);

      final row = await upgraded.membersDao.getMemberById('fully-loaded');
      expect(row, isNotNull);
      final m = row!;

      // age: now TEXT.
      expect(m.age, '42');

      // Every other seeded column must be unchanged.
      expect(m.id, 'fully-loaded');
      expect(m.name, 'Fully Loaded');
      expect(m.pronouns, 'they/them');
      expect(m.emoji, '🦊');
      expect(m.bio, 'A long bio with **markdown**.');
      expect(m.isActive, false);
      expect(m.createdAt.toUtc(), createdAt);
      expect(m.displayOrder, 7);
      expect(m.isAdmin, true);
      expect(m.customColorEnabled, true);
      expect(m.customColorHex, '#FF8800');
      expect(m.parentSystemId, 'parent-sys-1');
      expect(m.pluralkitUuid, 'pk-uuid-123');
      expect(m.pluralkitId, 'abcde');
      expect(m.pluralkitDisplayName, 'PK Display');
      expect(m.displayName, 'Full Display Name');
      expect(m.birthday, '1990-07-04');
      expect(m.proxyTagsJson, '[{"prefix":"[","suffix":"]"}]');
      expect(m.pkBannerUrl, 'https://cdn.example/banner.png');
      expect(m.profileHeaderSource, 2);
      expect(m.profileHeaderLayout, 1);
      expect(m.profileHeaderVisible, false);
      expect(m.nameStyleFont, 3);
      expect(m.nameStyleBold, false);
      expect(m.nameStyleItalic, true);
      expect(m.nameStyleColorMode, 2);
      expect(m.nameStyleColorHex, '#00CC44');
      expect(m.pkBannerCachedUrl, 'https://cdn.example/cached.png');
      expect(m.pluralkitSyncIgnored, true);
      expect(m.markdownEnabled, false);
      expect(m.isDeleted, true);
      expect(m.isAlwaysFronting, true);
      expect(m.boardLastReadAt?.toUtc(), boardReadAt);
    });

    test('age is read back as a String? through the MemberMapper', () async {
      final dbFile = await _seedDb(
        'prism_migration_v30_to_v31_mapper_',
        seed: (db) async {
          await db.into(db.members).insert(
            MembersCompanion.insert(
              id: 'mapper-member',
              name: 'Mapper Member',
              createdAt: DateTime.utc(2026, 5, 27),
            ),
          );
        },
        ageById: {'mapper-member': 33},
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      expect(await _ageColumnIsText(upgraded), 31);

      // Go through the real DAO → MemberMapper domain path, not a raw read.
      final dbRow = await upgraded.membersDao.getMemberById('mapper-member');
      expect(dbRow, isNotNull);
      final member = MemberMapper.toDomain(dbRow!);
      expect(member.age, isA<String?>());
      expect(member.age, '33');
    });

    test('v31 step composes with the full migration chain (v28 → v31)', () async {
      // Stand up a v28-era database the same way the neighboring tests do
      // (current schema, then drop the columns v29/v30 add so the chain
      // re-adds them) and migrate all the way to v31. Confirms the v30 → v31
      // step runs as part of the chain, not only from exactly v30.
      final dbFile = await _seedDb(
        'prism_migration_v28_to_v31_chain_',
        seed: (db) async {
          await db.into(db.members).insert(
            MembersCompanion.insert(
              id: 'chain-member',
              name: 'Chain Member',
              createdAt: DateTime.utc(2026, 5, 27),
            ),
          );
        },
        ageById: {'chain-member': 19},
        userVersion: 28,
        extraSetup: (rawDb) {
          // v28 → v29 re-adds pk_avatar_cached_url on members.
          rawDb.execute('ALTER TABLE members DROP COLUMN pk_avatar_cached_url');
          // v29 → v30 re-adds members_show_groups on system_settings.
          rawDb.execute(
            'ALTER TABLE system_settings DROP COLUMN members_show_groups',
          );
        },
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      // Whole chain ran: ended at v31 with age TEXT.
      expect(await _ageColumnIsText(upgraded), 31);

      // Columns the chain re-added are present again.
      final cols = await upgraded
          .customSelect('PRAGMA table_info(members)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('pk_avatar_cached_url'));

      final row = await upgraded.membersDao.getMemberById('chain-member');
      expect(row, isNotNull);
      expect(row!.age, '19', reason: 'integer age cast to string across chain');
      expect(row.pkAvatarCachedUrl, isNull);
    });
  });
}
