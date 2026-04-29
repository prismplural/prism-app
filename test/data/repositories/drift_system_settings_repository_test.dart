import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

/// Sync-emit contract: the three Phase 1B preference fields must appear in
/// `_settingsFields` (the map handed to `syncRecordUpdate`). Adapter-level
/// parity (sync_schema_parity_test) only catches drift between the engine's
/// schema and the adapter's `toSyncFields`. A field that is silently dropped
/// from the repository's emit map would create rows locally but never
/// propagate the missing fields to other devices.
void main() {
  late AppDatabase db;
  late DriftSystemSettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftSystemSettingsRepository(SystemSettingsDao(db), null);
  });

  tearDown(() => db.close());

  group('_settingsFields emits Phase 1B preference keys', () {
    test('default settings emit all three preference keys with index 0', () {
      const settings = SystemSettings();
      final fields = repo.debugSettingsFields(settings);

      expect(fields, contains('fronting_list_view_mode'));
      expect(fields, contains('add_front_default_behavior'));
      expect(fields, contains('quick_front_default_behavior'));

      expect(fields['fronting_list_view_mode'], 0);
      expect(fields['add_front_default_behavior'], 0);
      expect(fields['quick_front_default_behavior'], 0);
    });

    test('non-default values flow through as enum indices', () {
      const settings = SystemSettings(
        frontingListViewMode: FrontingListViewMode.timeline,
        addFrontDefaultBehavior: FrontStartBehavior.replace,
        quickFrontDefaultBehavior: FrontStartBehavior.replace,
      );
      final fields = repo.debugSettingsFields(settings);

      expect(
        fields['fronting_list_view_mode'],
        FrontingListViewMode.timeline.index,
      );
      expect(
        fields['add_front_default_behavior'],
        FrontStartBehavior.replace.index,
      );
      expect(
        fields['quick_front_default_behavior'],
        FrontStartBehavior.replace.index,
      );
    });

    test('every emitted preference value is an int (matches schema "Int")', () {
      const settings = SystemSettings();
      final fields = repo.debugSettingsFields(settings);

      expect(fields['fronting_list_view_mode'], isA<int>());
      expect(fields['add_front_default_behavior'], isA<int>());
      expect(fields['quick_front_default_behavior'], isA<int>());
    });
  });
}
