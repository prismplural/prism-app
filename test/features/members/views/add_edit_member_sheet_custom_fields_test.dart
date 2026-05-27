import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

Finder _prismField(String label) => find.byWidgetPredicate(
  (widget) => widget is PrismTextField && widget.labelText == label,
);

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('save button persists a focused custom field value', (
    tester,
  ) async {
    _useTallViewport(tester);

    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final member = Member(
      id: 'm-1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
    );
    await database.membersDao.insertMember(
      db.MembersCompanion.insert(
        id: member.id,
        name: member.name,
        createdAt: member.createdAt,
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'role',
        name: 'Role',
        fieldType: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          terminologySettingProvider.overrideWithValue((
            term: SystemTerminology.members,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AddEditMemberSheet(
              member: member,
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    // Scope to PrismSettingsRow — the editor's own "Custom Fields" header
    // is mounted off-screen in the detail view and would match find.text.
    final customFieldsRow = find.widgetWithText(
      PrismSettingsRow,
      'Custom Fields',
    );
    await tester.scrollUntilVisible(
      customFieldsRow,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(customFieldsRow);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: _prismField('Role'),
        matching: find.byType(EditableText),
      ),
      'Protector',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Save member'));
    await tester.pumpAndSettle();

    final values = await database.customFieldsDao.getAllValues();
    expect(values, hasLength(1));
    expect(values.single.customFieldId, 'role');
    expect(values.single.memberId, 'm-1');
    expect(values.single.value, 'Protector');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'a per-field write failure during bulk save still persists the member '
    'row update (best-effort commit)',
    (tester) async {
      _useTallViewport(tester);

      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final member = Member(
        id: 'm-1',
        name: 'Alice',
        createdAt: DateTime(2026, 1, 1),
      );
      await database.membersDao.insertMember(
        db.MembersCompanion.insert(
          id: member.id,
          name: member.name,
          createdAt: member.createdAt,
        ),
      );
      // Three text fields; we'll stage all three but force a failure on
      // the middle one. The member's own row write (display name change)
      // must still persist alongside fields 1 + 3.
      for (final spec in [
        ('role', 'Role'),
        ('mood', 'Mood'),
        ('color', 'Color'),
      ]) {
        await database.customFieldsDao.createField(
          db.CustomFieldsCompanion.insert(
            id: spec.$1,
            name: spec.$2,
            fieldType: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            // Wrap the real repo so we keep schema + watch streams, but force
            // upsertValue to throw for the 'mood' field. This lets the
            // member-row write proceed on the real DAO unaffected.
            customFieldsRepositoryProvider.overrideWith(
              (ref) => _FailingCustomFieldsRepository(
                inner: DriftCustomFieldsRepository(
                  database.customFieldsDao,
                  null,
                ),
                failOnFieldId: 'mood',
              ),
            ),
            terminologySettingProvider.overrideWithValue((
              term: SystemTerminology.members,
              customSingular: null,
              customPlural: null,
              useEnglish: false,
            )),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AddEditMemberSheet(
                member: member,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Rename the member to confirm the member row update lands.
      await tester.enterText(
        find.descendant(
          of: _prismField('Name *'),
          matching: find.byType(EditableText),
        ),
        'Alice Renamed',
      );
      await tester.pump();

      // Open the custom fields detail view.
      final customFieldsRow = find.widgetWithText(
        PrismSettingsRow,
        'Custom Fields',
      );
      await tester.scrollUntilVisible(
        customFieldsRow,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(customFieldsRow);
      await tester.pumpAndSettle();

      // Stage all three fields.
      await tester.enterText(
        find.descendant(
          of: _prismField('Role'),
          matching: find.byType(EditableText),
        ),
        'Protector',
      );
      await tester.enterText(
        find.descendant(
          of: _prismField('Mood'),
          matching: find.byType(EditableText),
        ),
        'Happy',
      );
      await tester.enterText(
        find.descendant(
          of: _prismField('Color'),
          matching: find.byType(EditableText),
        ),
        'Blue',
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Save member'));
      await tester.pumpAndSettle();

      // Member row update landed (best-effort: did NOT bail on the failed
      // field) — this is the regression that prompted the fix.
      final members = await database.membersDao.getAllMembers();
      expect(
        members.single.name,
        'Alice Renamed',
        reason: 'member row must persist even when a custom field write fails',
      );

      // Successful fields landed.
      final values = await database.customFieldsDao.getAllValues();
      final valuesByField = {
        for (final v in values) v.customFieldId: v.value,
      };
      expect(valuesByField['role'], 'Protector');
      expect(valuesByField['color'], 'Blue');
      // Failed field did not land.
      expect(valuesByField.containsKey('mood'), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

/// Test-only repo wrapper that proxies every call to [inner] except for
/// upserts targeting [failOnFieldId], which always throw. Used to simulate a
/// single custom-field write failing mid-bulk-commit while the rest of the
/// schema/watch surface still works.
class _FailingCustomFieldsRepository implements CustomFieldsRepository {
  _FailingCustomFieldsRepository({
    required this.inner,
    required this.failOnFieldId,
  });

  final CustomFieldsRepository inner;
  final String failOnFieldId;

  @override
  Future<void> upsertValue(CustomFieldValue value) async {
    if (value.customFieldId == failOnFieldId) {
      throw Exception('forced failure for ${value.customFieldId}');
    }
    return inner.upsertValue(value);
  }

  // Everything else passes through.
  @override
  Future<void> createField(CustomField field) => inner.createField(field);

  @override
  Future<void> createFieldFromImport(CustomField field) =>
      inner.createFieldFromImport(field);

  @override
  Future<void> deleteField(String id, {bool deleteChildren = false}) =>
      inner.deleteField(id, deleteChildren: deleteChildren);

  @override
  Future<void> deleteValue(String id) => inner.deleteValue(id);

  @override
  Future<void> deleteValuesForField(String fieldId) =>
      inner.deleteValuesForField(fieldId);

  @override
  Future<void> deleteValuesForMember(String memberId) =>
      inner.deleteValuesForMember(memberId);

  @override
  Future<void> deleteAllFields() => inner.deleteAllFields();

  @override
  Future<List<CustomField>> getAllFields() => inner.getAllFields();

  @override
  Future<List<CustomFieldValue>> getAllValues() => inner.getAllValues();

  @override
  Future<CustomField?> getFieldById(String id) => inner.getFieldById(id);

  @override
  Future<CustomFieldValue?> getValueForField(
    String fieldId,
    String memberId,
  ) => inner.getValueForField(fieldId, memberId);

  @override
  Future<void> moveFieldToParent(String fieldId, String? newParentId) =>
      inner.moveFieldToParent(fieldId, newParentId);

  @override
  Future<void> renameField(String fieldId, String newName) =>
      inner.renameField(fieldId, newName);

  @override
  Future<void> reorderFields(List<CustomField> fields) =>
      inner.reorderFields(fields);

  @override
  Future<void> setFieldDatePrecision(
    String fieldId,
    DatePrecision? newPrecision,
  ) => inner.setFieldDatePrecision(fieldId, newPrecision);

  @override
  Future<void> setFieldDisplayOrder(String fieldId, int newOrder) =>
      inner.setFieldDisplayOrder(fieldId, newOrder);

  @override
  Future<void> updateField(CustomField field) => inner.updateField(field);

  @override
  Stream<List<CustomField>> watchAllFields() => inner.watchAllFields();

  @override
  Stream<CustomField?> watchFieldById(String id) => inner.watchFieldById(id);

  @override
  Stream<List<CustomFieldValue>> watchValuesForField(String fieldId) =>
      inner.watchValuesForField(fieldId);

  @override
  Stream<List<CustomFieldValue>> watchValuesForMember(String memberId) =>
      inner.watchValuesForMember(memberId);

  @override
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) => inner.writeTypedConfig(fieldId, newConfig);
}
