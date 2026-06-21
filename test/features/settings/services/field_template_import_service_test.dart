/// Tests for [FieldTemplateImportService] — the correctness-critical import
/// path for field templates. Validates:
///   - Validation runs before any DB write (boundary gate).
///   - toDomainFields produces fresh UUIDs; two imports = two independent groups.
///   - Groups are inserted before children (no orphan FK / depth-validation fail).
///   - Sync ops are captured and persisted inside the fenced transaction.
///   - A mid-import failure rolls back BOTH data rows AND outbox rows.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/features/settings/services/field_template_import_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// A thin template: one group + two text children.
FieldTemplate _groupPlusTwoChildren() => const FieldTemplate(
  version: 1,
  entries: [
    FieldTemplateEntry(name: 'My Group', fieldTypeId: kGroupFieldTypeId),
    FieldTemplateEntry(
      name: 'Child A',
      fieldTypeId: 'text',
      parentIndex: 0,
    ),
    FieldTemplateEntry(
      name: 'Child B',
      fieldTypeId: 'text',
      parentIndex: 0,
    ),
  ],
);

/// Fake repo that throws on the N-th createFieldAtEnd call (1-based).
class _ThrowingOnNthRepo extends DriftCustomFieldsRepository {
  _ThrowingOnNthRepo(CustomFieldsDao dao, {required int throwOnCall})
      : _throwOnCall = throwOnCall,
        super(dao, null);

  final int _throwOnCall;
  int _callCount = 0;

  @override
  Future<void> createFieldAtEnd(field) async {
    _callCount++;
    if (_callCount == _throwOnCall) {
      throw Exception('Simulated failure on call $_throwOnCall');
    }
    return super.createFieldAtEnd(field);
  }
}

// ── Test helpers ─────────────────────────────────────────────────────────────

/// Count all custom_fields rows (active + deleted).
Future<int> _rowCount(AppDatabase db) =>
    (db.select(db.customFields)).get().then((r) => r.length);

/// Count sync_op_outbox rows.
Future<int> _outboxCount(AppDatabase db) =>
    db.syncOutboxDao.allInIdOrder().then((r) => r.length);

// ── Main ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;
  late DriftCustomFieldsRepository repo;
  late FieldTemplateImportService svc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftCustomFieldsRepository(db.customFieldsDao, null);
    svc = FieldTemplateImportService(db, repo);
    // Tests run without sync credentials → outbox gates are off by default.
    syncCredentialsPersisted.value = false;
  });

  tearDown(() async {
    await db.close();
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  test('happy: imports group + 2 children → 3 rows, correct parent links', () async {
    final result = await svc.importTemplate(_groupPlusTwoChildren());

    expect(result.fieldsImported, 3);
    expect(result.groupIds, hasLength(1));

    final rows = await db.select(db.customFields).get();
    expect(rows, hasLength(3));

    final groupId = result.groupIds.first;
    final group = rows.firstWhere((r) => r.id == groupId);
    expect(group.name, 'My Group');
    expect(group.parentFieldId, isNull);
    expect(group.fieldTypeId, kGroupFieldTypeId);

    final children = rows.where((r) => r.parentFieldId == groupId).toList();
    expect(children, hasLength(2));
    expect(
      children.map((c) => c.name).toSet(),
      {'Child A', 'Child B'},
    );
  });

  test('happy: displayOrder is appended after a pre-seeded field', () async {
    // Seed one existing field so the imported group gets a non-zero displayOrder.
    await db.customFieldsDao.createField(
      CustomFieldsCompanion.insert(
        id: 'pre-existing',
        name: 'Existing',
        fieldType: 0,
        createdAt: DateTime.now(),
      ),
    );

    await svc.importTemplate(_groupPlusTwoChildren());

    final rows = await db.select(db.customFields).get();
    // Pre-existing field has displayOrder 0 (default insert), imported group > 0.
    final group = rows.firstWhere((r) => r.name == 'My Group');
    final existing = rows.firstWhere((r) => r.id == 'pre-existing');
    expect(group.displayOrder, greaterThan(existing.displayOrder));
  });

  // ── Re-import identity ─────────────────────────────────────────────────────

  test('re-import: two imports of same template → 6 rows, two independent groups', () async {
    final r1 = await svc.importTemplate(_groupPlusTwoChildren());
    final r2 = await svc.importTemplate(_groupPlusTwoChildren());

    expect(await _rowCount(db), 6);
    expect(r1.groupIds.first, isNot(equals(r2.groupIds.first)));

    // Both groups must exist in the DB.
    final rows = await db.select(db.customFields).get();
    final groupIds = rows
        .where((r) => r.fieldTypeId == kGroupFieldTypeId)
        .map((r) => r.id)
        .toSet();
    expect(groupIds, containsAll([r1.groupIds.first, r2.groupIds.first]));
  });

  // ── Validation at the boundary ─────────────────────────────────────────────

  test('validation: >50 entries → throws invalid, writes nothing', () async {
    final oversized = FieldTemplate(
      version: 1,
      entries: List.generate(
        51,
        (i) => FieldTemplateEntry(name: 'F$i', fieldTypeId: 'text'),
      ),
    );
    await expectLater(
      svc.importTemplate(oversized),
      throwsA(
        isA<FieldTemplateCodecException>().having(
          (e) => e.kind,
          'kind',
          FieldTemplateCodecError.invalid,
        ),
      ),
    );
    expect(await _rowCount(db), 0);
  });

  test('validation: depth-2 nesting → throws invalid, writes nothing', () async {
    // Entry 0 = group; entry 1 = child of 0; entry 2 = child of 1 (depth 2 → invalid).
    const tooDeep = FieldTemplate(
      version: 1,
      entries: [
        FieldTemplateEntry(name: 'G', fieldTypeId: kGroupFieldTypeId),
        FieldTemplateEntry(
          name: 'Child',
          fieldTypeId: kGroupFieldTypeId,
          parentIndex: 0,
        ),
        FieldTemplateEntry(
          name: 'GrandChild',
          fieldTypeId: 'text',
          parentIndex: 1,
        ),
      ],
    );
    await expectLater(
      svc.importTemplate(tooDeep),
      throwsA(isA<FieldTemplateCodecException>().having(
        (e) => e.kind,
        'kind',
        FieldTemplateCodecError.invalid,
      )),
    );
    expect(await _rowCount(db), 0);
  });

  test('validation: bad colorHex → throws invalid, writes nothing', () async {
    const badColor = FieldTemplate(
      version: 1,
      entries: [
        FieldTemplateEntry(
          name: 'Choice',
          fieldTypeId: 'choice',
          compactConfig: {
            'options': [
              {'label': 'Red', 'colorHex': 'notacolor'},
            ],
          },
        ),
      ],
    );
    await expectLater(
      svc.importTemplate(badColor),
      throwsA(isA<FieldTemplateCodecException>().having(
        (e) => e.kind,
        'kind',
        FieldTemplateCodecError.invalid,
      )),
    );
    expect(await _rowCount(db), 0);
  });

  test('validation: malformed config (options not a list) → invalid, writes nothing', () async {
    // Passes structural validation but throws when inflated — the service must
    // surface a typed invalid (not a raw _TypeError) and write nothing.
    const malformed = FieldTemplate(
      version: 1,
      entries: [
        FieldTemplateEntry(
          name: 'Choice',
          fieldTypeId: 'choice',
          compactConfig: {'runtimeType': 'choice', 'options': 'notalist'},
        ),
      ],
    );
    await expectLater(
      svc.importTemplate(malformed),
      throwsA(isA<FieldTemplateCodecException>().having(
        (e) => e.kind,
        'kind',
        FieldTemplateCodecError.invalid,
      )),
    );
    expect(await _rowCount(db), 0);
  });

  test('validation: out-of-range parentIndex → imported top-level, no throw', () async {
    const withBadParent = FieldTemplate(
      version: 1,
      entries: [
        FieldTemplateEntry(
          name: 'Orphan',
          fieldTypeId: 'text',
          parentIndex: 99, // out of range → promoted
        ),
      ],
    );
    final result = await svc.importTemplate(withBadParent);
    expect(result.fieldsImported, 1);

    final rows = await db.select(db.customFields).get();
    expect(rows, hasLength(1));
    expect(rows.first.parentFieldId, isNull);
  });

  // ── Sync emission ──────────────────────────────────────────────────────────

  test('sync emission: one create op captured per field (verified via outbox)', () async {
    // Inside runFencedEmissionTransaction, the zone capture context takes
    // precedence over the test capture sink — ops go to the service's internal
    // `captured` list, not to any external sink. The authoritative proof is that
    // persistCapturedOpsToOutbox wrote one outbox row per field.
    syncCredentialsPersisted.value = true;
    try {
      final result = await svc.importTemplate(_groupPlusTwoChildren());
      final outboxRows = await db.syncOutboxDao.allInIdOrder();

      // N fields → N outbox rows, all 'create', all on 'custom_fields'.
      expect(outboxRows, hasLength(result.fieldsImported));
      expect(outboxRows.map((r) => r.opType), everyElement('create'));
      expect(
        outboxRows.map((r) => r.entityTable).toSet(),
        {'custom_fields'},
      );
    } finally {
      syncCredentialsPersisted.value = false;
    }
  });

  test('sync outbox: rows persisted when credentials on', () async {
    syncCredentialsPersisted.value = true;
    try {
      final result = await svc.importTemplate(_groupPlusTwoChildren());
      expect(await _outboxCount(db), result.fieldsImported);
    } finally {
      syncCredentialsPersisted.value = false;
    }
  });

  test('sync outbox: rows NOT persisted when credentials off', () async {
    // syncCredentialsPersisted.value == false (setUp default)
    await svc.importTemplate(_groupPlusTwoChildren());
    expect(await _outboxCount(db), 0);
  });

  // ── Rollback safety ────────────────────────────────────────────────────────

  test('rollback: failure mid-import → zero data rows AND zero outbox rows', () async {
    syncCredentialsPersisted.value = true;

    // Repo that throws on the 2nd createFieldAtEnd call (after inserting the group).
    final throwingRepo = _ThrowingOnNthRepo(
      db.customFieldsDao,
      throwOnCall: 2,
    );
    final throwingSvc = FieldTemplateImportService(db, throwingRepo);

    await expectLater(
      throwingSvc.importTemplate(_groupPlusTwoChildren()),
      throwsA(isA<Exception>()),
    );

    expect(await _rowCount(db), 0, reason: 'transaction must have rolled back');
    expect(
      await _outboxCount(db),
      0,
      reason: 'outbox rows must roll back with data rows',
    );

    syncCredentialsPersisted.value = false;
  });
}
