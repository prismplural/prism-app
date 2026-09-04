import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart'
    as repo_iface;
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/reset_data_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeCustomFieldsRepository implements repo_iface.CustomFieldsRepository {
  final List<CustomField> _fields;
  int deleteAllFieldsCallCount = 0;

  _FakeCustomFieldsRepository(this._fields);

  @override
  Stream<List<CustomField>> watchAllFields() => Stream.value(List.of(_fields));

  @override
  Future<List<CustomField>> getAllFields() async => List.of(_fields);

  @override
  Stream<CustomField?> watchFieldById(String id) => Stream.value(
    _fields.cast<CustomField?>().firstWhere(
      (f) => f?.id == id,
      orElse: () => null,
    ),
  );

  @override
  Future<CustomField?> getFieldById(String id) async => _fields
      .cast<CustomField?>()
      .firstWhere((f) => f?.id == id, orElse: () => null);

  @override
  Future<void> createField(CustomField field) async => _fields.add(field);

  @override
  Future<void> createFieldFromImport(CustomField field) async =>
      _fields.add(field);

  @override
  Future<void> updateField(CustomField field) async {}

  @override
  Future<void> renameField(String fieldId, String newName) async {}

  @override
  Future<void> setFieldDatePrecision(
    String fieldId,
    DatePrecision? newPrecision,
  ) async {}

  @override
  Future<void> setFieldDisplayOrder(String fieldId, int newOrder) async {}

  @override
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) async {}

  @override
  Future<void> clearTypedConfig(String fieldId) async {}

  @override
  Future<void> moveFieldToParent(String fieldId, String? newParentId) async {}

  @override
  Future<void> deleteField(String id, {bool deleteChildren = false}) async {
    _fields.removeWhere((f) => f.id == id);
  }

  @override
  Future<void> reorderFields(List<CustomField> fields) async {}

  @override
  Future<void> deleteAllFields() async {
    deleteAllFieldsCallCount++;
    _fields.clear();
  }

  // Value operations — not used in these tests
  @override
  Stream<List<CustomFieldValue>> watchValuesForMember(String memberId) =>
      Stream.value(const []);

  @override
  Stream<List<CustomFieldValue>> watchValuesForField(String fieldId) =>
      Stream.value(const []);

  @override
  Future<List<CustomFieldValue>> getAllValues() async => const [];

  @override
  Future<CustomFieldValue?> getValueForField(
    String customFieldId,
    String memberId,
  ) async => null;

  @override
  Future<void> upsertValue(CustomFieldValue value) async {}

  @override
  Future<void> deleteValue(String id) async {}

  @override
  Future<void> deleteValueFor(String customFieldId, String memberId) async {}

  @override
  Future<void> deleteValuesForField(String fieldId) async {}

  @override
  Future<void> deleteValuesForMember(String memberId) async {}

  @override
  Future<T> commitValueBatch<T>(Future<T> Function() writes) => writes();
}

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

final _oneField = CustomField(
  id: 'test-field-1',
  name: 'Nickname',
  fieldType: CustomFieldType.text,
  createdAt: DateTime.utc(2024),
);

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildSubject({
  required List<CustomField> fields,
  _FakeCustomFieldsRepository? fakeRepo,
  Locale locale = const Locale('en'),
}) {
  final repo = fakeRepo ?? _FakeCustomFieldsRepository(fields);
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      customFieldsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ResetDataScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ResetDataScreen — Custom Fields row', () {
    testWidgets('renders Custom Fields row in Categories section', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(fields: [_oneField]));
      await tester.pumpAndSettle();

      expect(find.text('Custom Fields'), findsOneWidget);
    });

    testWidgets('Custom Fields row is disabled when no fields exist', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(fields: const []));
      await tester.pumpAndSettle();

      // Row exists but tapping it should not open a dialog
      expect(find.text('Custom Fields'), findsOneWidget);

      await tester.tap(find.text('Custom Fields'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // No confirmation dialog should appear
      expect(find.text('Reset Custom Fields?'), findsNothing);
    });

    testWidgets(
      'Custom Fields row opens confirmation dialog with custom copy when tapped',
      (tester) async {
        await tester.pumpWidget(_buildSubject(fields: [_oneField]));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Custom Fields'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Custom Fields'));
        await tester.pumpAndSettle();

        expect(find.text('Reset Custom Fields?'), findsOneWidget);
        expect(
          find.textContaining('definitions and the values your members have'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'confirmed Custom Fields reset calls deleteAllFields on the repository',
      (tester) async {
        final fakeRepo = _FakeCustomFieldsRepository([_oneField]);

        await tester.pumpWidget(
          _buildSubject(fields: [_oneField], fakeRepo: fakeRepo),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Custom Fields'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Custom Fields'));
        await tester.pumpAndSettle();

        expect(find.text('Reset Custom Fields?'), findsOneWidget);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(fakeRepo.deleteAllFieldsCallCount, equals(1));
      },
    );

    testWidgets('sync reset confirmation is localized in Spanish', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(fields: [_oneField], locale: const Locale('es')),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Desconectar sincronización'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Desconectar sincronización'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desconectar sincronización'));
      await tester.pumpAndSettle();

      expect(
        find.text('¿Desconectar la sincronización de este dispositivo?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Prism conservará todos los datos locales'),
        findsOneWidget,
      );
      expect(
        find.text('Desconectar sincronización y conservar datos'),
        findsOneWidget,
      );
      expect(find.textContaining('Disconnect'), findsNothing);
    });
  });
}
