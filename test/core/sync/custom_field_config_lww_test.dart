import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

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

CustomField _textField({required String id, bool hideTitleOnProfile = false}) {
  return CustomField(
    id: id,
    name: 'Bio',
    fieldType: CustomFieldType.text,
    fieldTypeId: 'text',
    typeConfig: TextConfig(hideTitleOnProfile: hideTitleOnProfile),
    displayOrder: 0,
    createdAt: DateTime.utc(2026, 5, 25),
  );
}

CustomField _choiceField({required String id}) {
  return CustomField(
    id: id,
    name: 'Faves',
    fieldType: CustomFieldType.choice,
    fieldTypeId: 'choice',
    typeConfig: const ChoiceConfig(
      options: [
        ChoiceOption(id: 'a', label: 'Apple', sortOrder: 0),
        ChoiceOption(id: 'b', label: 'Banana', sortOrder: 1),
        ChoiceOption(id: 'c', label: 'Cherry', sortOrder: 2),
      ],
    ),
    displayOrder: 0,
    createdAt: DateTime.utc(2026, 5, 25),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('whole-config LWW invariant', () {
    late AppDatabase db;
    late _SilentRepo repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = _SilentRepo(db.customFieldsDao);
      // Seed a choice field with 3 options.
      await repo.createField(_choiceField(id: 'f1'));
    });

    tearDown(() => db.close());

    // ── 1. LWW: later write wins entirely (no per-key merge) ─────────────────

    test('writeTypedConfig writes the entire blob (no field-level merge)', () async {
      // Read current config.
      final initial = await repo.getFieldById('f1');
      expect(initial, isNotNull);
      final initialConfig = initial!.typeConfig as ChoiceConfig;
      expect(initialConfig.options.length, 3);

      // Device A: rename option 'a' from 'Apple' to 'Apricot'.
      final deviceAConfig = initialConfig.copyWith(
        options: [
          initialConfig.options[0].copyWith(label: 'Apricot'),
          initialConfig.options[1],
          initialConfig.options[2],
        ],
      );
      await repo.writeTypedConfig('f1', deviceAConfig);

      // Verify Device A's write landed.
      final afterA = await repo.getFieldById('f1');
      expect((afterA!.typeConfig as ChoiceConfig).options[0].label, 'Apricot');

      // Device B (concurrent, racing): deletes option 'c' (soft-delete),
      // but its blob started from the ORIGINAL config — NOT from Device A's
      // mutated copy. In real CRDT this would be a concurrent write.
      // We're testing the invariant that the LATER writeTypedConfig call
      // replaces the ENTIRE blob, so Device A's rename must NOT survive.
      final deviceBConfig = initialConfig.copyWith(
        options: [
          initialConfig.options[0], // <- 'Apple' label, NOT 'Apricot'
          initialConfig.options[1],
          initialConfig.options[2].copyWith(isDeleted: true),
        ],
      );
      await repo.writeTypedConfig('f1', deviceBConfig);

      // Verify: final state is Device B's blob in its entirety.
      // The rename from Device A is GONE (label is 'Apple', not 'Apricot').
      // This proves the LWW invariant: no per-key merge, last write wins.
      final finalField = await repo.getFieldById('f1');
      final finalConfig = finalField!.typeConfig as ChoiceConfig;
      expect(finalConfig.options.length, 3);
      expect(
        finalConfig.options[0].label,
        'Apple',
        reason: "Device B's blob fully replaced Device A's — rename is gone",
      );
      expect(
        finalConfig.options[2].isDeleted,
        isTrue,
        reason: "Device B's soft-delete is preserved",
      );
    });

    // ── 2. Forward-compat: extra (unknown) keys survive parse → mutate → write ─

    test('writeTypedConfig preserves extra (forward-compat) keys', () async {
      // Simulate a future-version peer delivering a raw blob with an unknown
      // top-level key 'futureFeature'. We write it directly to the DB, bypassing
      // the repo's serialize path, to simulate receiving it over sync.
      const raw =
          '{"runtimeType":"choice",'
          '"options":[{"id":"a","label":"Apple","sortOrder":0,'
          '"colorHex":null,"isDeleted":false}],'
          '"allowsMultiple":false,"allowsOther":false,'
          '"futureFeature":"preserved"}';

      await db.customStatement(
        "UPDATE custom_fields SET type_config_json = ? WHERE id = 'f1'",
        [raw],
      );

      // Read via repo → parses through CustomFieldTypeConfigCodec.
      // The unknown 'futureFeature' key should land in config.extra.
      final after = await repo.getFieldById('f1');
      expect(after, isNotNull);
      final config = after!.typeConfig as ChoiceConfig;
      expect(config.extra['futureFeature'], 'preserved');

      // Mutate the options (rename 'Apple' → 'Apricot') and write back.
      final mutated = config.copyWith(
        options: [config.options[0].copyWith(label: 'Apricot')],
      );
      await repo.writeTypedConfig('f1', mutated);

      // Re-read the raw JSON from the DB directly.
      final rawAfterResult = await db.customSelect(
        "SELECT type_config_json FROM custom_fields WHERE id = 'f1'",
      ).getSingle();
      final rawAfter = rawAfterResult.read<String>('type_config_json');

      // The 'futureFeature' key must survive the full parse → mutate → write
      // round-trip. This is the forward-compat invariant.
      expect(rawAfter, contains('futureFeature'),
          reason: 'unknown key must survive parse → mutate → write round-trip');
      expect(rawAfter, contains('preserved'));

      // The mutation should also be reflected.
      final decoded = jsonDecode(rawAfter) as Map<String, dynamic>;
      final options = decoded['options'] as List<dynamic>;
      expect((options[0] as Map<String, dynamic>)['label'], 'Apricot');
    });
  });

  // ── TextConfig LWW invariant ──────────────────────────────────────────────
  //
  // New minimal variants (TextConfig / ColorConfig / etc.) must round-trip
  // their `hideTitleOnProfile` flag through writeTypedConfig / getFieldById,
  // and a later write of `false` must fully replace an earlier `true`
  // (whole-config LWW, no per-key merge).

  group('TextConfig LWW invariant', () {
    late AppDatabase db2;
    late _SilentRepo repo2;

    setUp(() async {
      db2 = AppDatabase(NativeDatabase.memory());
      repo2 = _SilentRepo(db2.customFieldsDao);
      await repo2.createField(_textField(id: 't1', hideTitleOnProfile: false));
    });

    tearDown(() => db2.close());

    test(
      'writeTypedConfig persists TextConfig(hideTitleOnProfile: true) and reads back',
      () async {
        await repo2.writeTypedConfig(
          't1',
          const TextConfig(hideTitleOnProfile: true),
        );

        final field = await repo2.getFieldById('t1');
        expect(field, isNotNull);
        expect(field!.typeConfig, isA<TextConfig>(),
            reason: 'should decode back to TextConfig, not unknownTypeConfigRaw');
        expect(
          (field.typeConfig! as TextConfig).hideTitleOnProfile,
          isTrue,
          reason: 'hideTitleOnProfile:true must survive writeTypedConfig → getFieldById',
        );
      },
    );

    test(
      'later writeTypedConfig(false) wins over earlier writeTypedConfig(true) — whole-config LWW',
      () async {
        // Earlier write: hideTitleOnProfile = true.
        await repo2.writeTypedConfig(
          't1',
          const TextConfig(hideTitleOnProfile: true),
        );
        final afterTrue = await repo2.getFieldById('t1');
        expect((afterTrue!.typeConfig! as TextConfig).hideTitleOnProfile, isTrue);

        // Later write: hideTitleOnProfile = false.  Must replace entire blob.
        await repo2.writeTypedConfig(
          't1',
          const TextConfig(hideTitleOnProfile: false),
        );
        final afterFalse = await repo2.getFieldById('t1');
        expect(
          (afterFalse!.typeConfig! as TextConfig).hideTitleOnProfile,
          isFalse,
          reason:
              'second write of false must fully overwrite first write of true (whole-config LWW)',
        );
      },
    );
  });
}
