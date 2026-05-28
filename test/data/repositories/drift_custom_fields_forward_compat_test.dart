// ignore_for_file: avoid_print
//
// Forward-compatibility and orphan-on-read tests.
//
// NOTE: Widget tests in the 'unsupported field rendering' group are intentionally
// committed but expected to fail to compile in CI until the pre-existing FFI
// compile chain is resolved (verifyMnemonicPin is not in the pinned prism-sync).
// The FFI block is tracked separately; these tests will auto-enable when it clears.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/orphan_promotion.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';

// ---------------------------------------------------------------------------
// Harness — suppresses FFI sync-record calls so tests don't need a Rust handle
// ---------------------------------------------------------------------------

class _SilentRepo extends DriftCustomFieldsRepository {
  _SilentRepo(CustomFieldsDao dao) : super(dao, null);

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CustomField _field({
  required String id,
  String? parentFieldId,
  String fieldTypeId = 'text',
}) {
  return CustomField(
    id: id,
    name: 'Field $id',
    fieldType: CustomFieldType.text,
    displayOrder: 0,
    createdAt: DateTime.utc(2026, 5, 25),
    fieldTypeId: fieldTypeId,
    parentFieldId: parentFieldId,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late _SilentRepo repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = _SilentRepo(database.customFieldsDao);
  });

  tearDown(() async {
    await database.close();
  });

  // ── Group-delete race (orphan-on-read) ─────────────────────────────────────
  //
  // These tests duplicate the orphan-on-read tests in
  // drift_custom_fields_repository_group_test.dart but from the forward-compat
  // angle: specifically, that a child field whose parent is tombstoned or
  // outright missing renders at top level WITHOUT mutating the DB row.

  group('orphan-on-render (group-delete race)', () {
    // Orphan promotion lives in the render-layer helper
    // `promoteOrphansForRender` (driven by `topLevelCustomFieldsProvider`).
    // The repo stream exposes the raw on-disk view so write paths and group
    // editors see the actual stored
    // `parent_field_id`. These tests cover both halves of the contract.
    test(
      'raw stream preserves parent ref + render helper promotes when parent is tombstoned',
      () async {
        // Set up: G (group) + C (child of G).
        final fieldG = _field(id: 'G', fieldTypeId: 'group');
        final fieldC = _field(id: 'C', parentFieldId: 'G');

        await repo.createField(fieldG);
        await repo.createField(fieldC);

        // Soft-delete G directly via DAO, bypassing deleteField's promote logic.
        // This simulates the race: a remote peer's delete-with-promote arrived
        // AFTER the child write landed on this peer but BEFORE the parent-clear
        // was applied, leaving C orphaned in storage.
        await database.customFieldsDao.deleteField('G');

        // Raw stream still emits C with its original parent_field_id.
        final raw = await repo.watchAllFields().first;
        expect(raw.map((f) => f.id), isNot(contains('G')));
        final rawC = raw.firstWhere((f) => f.id == 'C');
        expect(rawC.parentFieldId, 'G',
            reason: 'raw repo stream must preserve on-disk parent_field_id');

        // Render-layer projection promotes the orphan.
        final projected = promoteOrphansForRender(raw);
        final projectedC = projected.firstWhere((f) => f.id == 'C');
        expect(projectedC.parentFieldId, isNull,
            reason: 'orphaned child must render at top level after projection');
      },
    );

    test(
      'raw stream preserves parent ref + render helper promotes when parent id is never-existent',
      () async {
        // Insert C with a parentFieldId that was never in the DB (e.g. peer
        // created C referencing G, but G's row arrived on this device later
        // or was dropped).
        final fieldC = _field(id: 'C', parentFieldId: 'never-exists');
        await repo.createField(fieldC);

        // Raw view preserves the bogus parent ref so sync re-attach can fire
        // naturally if the parent arrives later.
        final raw = await repo.watchAllFields().first;
        final rawC = raw.firstWhere((f) => f.id == 'C');
        expect(rawC.parentFieldId, 'never-exists',
            reason: 'raw repo stream must preserve on-disk parent_field_id');

        // Render-layer projection promotes the orphan.
        final projected = promoteOrphansForRender(raw);
        final projectedC = projected.firstWhere((f) => f.id == 'C');
        expect(projectedC.parentFieldId, isNull,
            reason: 'child of never-existent parent must render at top level');

        // Storage must NOT have been mutated: the raw DB row should still
        // carry the original parent ref so re-attach is automatic.
        final rawRow = await database.customFieldsDao.getFieldById('C');
        expect(rawRow?.parentFieldId, 'never-exists',
            reason:
                'in-memory promotion must NOT clear storage — sync re-attach depends on this');
      },
    );
  });

  // ── Unknown field_type_id forward compat ──────────────────────────────────
  //
  // v28 readers must not crash when they encounter a field_type_id that was
  // added by a future version. The mapper must preserve the id and the raw
  // config bytes for sync re-emit.

  group('unknown field_type_id forward compat', () {
    test('mapper preserves unknown id and gracefully returns null config', () async {
      // Insert a row directly via the DB — simulates sync delivering a row
      // written by a future client that introduced 'future_type'.
      await database.into(database.customFields).insert(
        CustomFieldsCompanion.insert(
          id: 'x',
          name: 'Future Field',
          fieldType: 99, // out-of-range int for v28 enum
          fieldTypeId: const Value('future_type'),
          typeConfigJson:
              const Value('{"runtimeType":"future_type","whatever":42}'),
          createdAt: DateTime.utc(2026, 5, 25),
        ),
      );

      // Read via the mapper (as repo would).
      final row = await database.customFieldsDao.getFieldById('x');
      expect(row, isNotNull);
      final domain = CustomFieldMapper.toDomain(row!);

      // fieldTypeId must survive — used by future callers once they upgrade.
      expect(domain.fieldTypeId, 'future_type',
          reason: 'unknown fieldTypeId must round-trip through mapper');

      // typeConfig is null because the codec couldn't match the runtimeType.
      // This is the graceful-degradation behaviour; no crash.
      expect(domain.typeConfig, isNull,
          reason:
              'unknown runtimeType should degrade to null typeConfig, not throw');

      // fieldType falls back to text (index 0) for the v28 enum, since 99 is
      // out of range for the current enum.
      expect(domain.fieldType, CustomFieldType.text,
          reason:
              'out-of-range field_type int must fall back to CustomFieldType.text');

      // Round-trip through toCompanion: fieldTypeId must survive.
      final companion = CustomFieldMapper.toCompanion(domain);
      expect(companion.fieldTypeId.value, 'future_type',
          reason: 'fieldTypeId must survive toDomain → toCompanion round-trip');
    });

    test(
      'field_type = 99 with NULL field_type_id falls back through legacy guard',
      () async {
        // v28 readers receiving a row with a new int and no field_type_id
        // (e.g., an extremely old pre-migration row) must not crash.
        await database.into(database.customFields).insert(
          CustomFieldsCompanion.insert(
            id: 'y',
            name: 'Old Future Field',
            fieldType: 99,
            // field_type_id intentionally null: simulate pre-v28 row with
            // a new type int that wasn't backfilled.
            createdAt: DateTime.utc(2026, 5, 25),
          ),
        );

        final row = await database.customFieldsDao.getFieldById('y');
        expect(row, isNotNull);
        final domain = CustomFieldMapper.toDomain(row!);

        // With both field_type_id=null and an unrecognised int, the mapper
        // falls back to 'text' as the fieldTypeId (via _legacyIntToId returning
        // null → default 'text') and CustomFieldType.text as fieldType.
        // This is the v27-reader-graceful-degradation path.
        expect(domain.fieldType, CustomFieldType.text,
            reason:
                'out-of-range field_type with null id must fall back to text');
        // fieldTypeId should be 'text' (the default fallback).
        expect(domain.fieldTypeId, isNotNull,
            reason: 'fallback fieldTypeId must be non-null');
        // No crash — that is the primary invariant.
      },
    );
  });

  // Followup: widget-level coverage for unknown-fieldTypeId rendering
  // ("no exception when it reaches the renderer"). The mapper-level
  // round-trip above pins the storage contract.

  // ── type_config_json forward compat (unknown runtimeType) ─────────────────
  //
  // Adding 4 new known variants (TextConfig / ColorConfig / DateConfig /
  // LongTextConfig) must NOT accidentally start swallowing unrecognised
  // runtimeType values. These tests pin the preservation contract.

  group('type_config_json forward compat (unknown runtimeType)', () {
    test(
      'unknown runtimeType is preserved verbatim after new variants land',
      () async {
        // Raw JSON simulating a row written by an even-newer build that
        // introduced a type this build will never know about.
        const rawJson = '{"runtimeType":"futureType","foo":1}';

        await database.into(database.customFields).insert(
          CustomFieldsCompanion.insert(
            id: 'future1',
            name: 'Future Field',
            fieldType: 0,
            fieldTypeId: const Value('futureType'),
            typeConfigJson: const Value(rawJson),
            createdAt: DateTime.utc(2026, 5, 25),
          ),
        );

        final row = await database.customFieldsDao.getFieldById('future1');
        expect(row, isNotNull);
        final domain = CustomFieldMapper.toDomain(row!);

        // The codec throws for 'futureType' → caught → unknownTypeConfigRaw.
        expect(domain.typeConfig, isNull,
            reason:
                'unknown runtimeType must degrade to null typeConfig, not throw');
        expect(domain.unknownTypeConfigRaw, rawJson,
            reason: 'unknown runtimeType raw bytes must be preserved verbatim');

        // toCompanion must echo back the original raw bytes (no mutation).
        final companion = CustomFieldMapper.toCompanion(domain);
        expect(companion.typeConfigJson.value, rawJson,
            reason:
                'toCompanion must re-emit unknownTypeConfigRaw byte-for-byte');
      },
    );

    test(
      'known new variant TextConfig decodes to first-class TextConfig (not unknownTypeConfigRaw)',
      () async {
        // Simulate a row written by this build (or an identical one) carrying
        // the new TextConfig variant with hideTitleOnProfile = true.
        const rawJson = '{"runtimeType":"text","hideTitleOnProfile":true}';

        await database.into(database.customFields).insert(
          CustomFieldsCompanion.insert(
            id: 'text1',
            name: 'Pronouns',
            fieldType: 0,
            fieldTypeId: const Value('text'),
            typeConfigJson: const Value(rawJson),
            createdAt: DateTime.utc(2026, 5, 25),
          ),
        );

        final row = await database.customFieldsDao.getFieldById('text1');
        expect(row, isNotNull);
        final domain = CustomFieldMapper.toDomain(row!);

        // Must produce a typed TextConfig, NOT fall into unknownTypeConfigRaw.
        expect(domain.unknownTypeConfigRaw, isNull,
            reason: 'TextConfig is a known variant — must not land in unknownTypeConfigRaw');
        expect(domain.typeConfig, isA<TextConfig>(),
            reason: 'runtimeType "text" must decode to TextConfig');
        final textConfig = domain.typeConfig! as TextConfig;
        expect(textConfig.hideTitleOnProfile, isTrue,
            reason: 'hideTitleOnProfile:true must survive toDomain');

        // Round-trip via toCompanion must preserve the flag.
        final companion = CustomFieldMapper.toCompanion(domain);
        final reEncoded = companion.typeConfigJson.value;
        expect(reEncoded, isNotNull,
            reason: 'toCompanion must produce non-null typeConfigJson for TextConfig');
        expect(reEncoded, contains('"hideTitleOnProfile":true'),
            reason: 'hideTitleOnProfile:true must survive toDomain → toCompanion');
      },
    );
  });
}
