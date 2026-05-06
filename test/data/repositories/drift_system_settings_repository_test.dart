import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';

/// Sync-emit contract: fronting preference fields must appear in
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

  group('_settingsFields emits fronting preference keys', () {
    test('default settings emit enum prefs plus the auto-promote bool', () {
      const settings = SystemSettings();
      final fields = repo.debugSettingsFields(settings);

      expect(fields, contains('fronting_list_view_mode'));
      expect(fields, contains('add_front_default_behavior'));
      expect(fields, contains('quick_front_default_behavior'));
      expect(fields, contains('auto_promote_long_fronting_sessions'));

      expect(fields['fronting_list_view_mode'], 0);
      expect(fields['add_front_default_behavior'], 0);
      expect(fields['quick_front_default_behavior'], 0);
      expect(fields['auto_promote_long_fronting_sessions'], isTrue);
    });

    test('non-default values flow through as enum indices', () {
      const settings = SystemSettings(
        frontingListViewMode: FrontingListViewMode.timeline,
        addFrontDefaultBehavior: FrontStartBehavior.replace,
        quickFrontDefaultBehavior: FrontStartBehavior.replace,
        autoPromoteLongFrontingSessions: false,
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
      expect(fields['auto_promote_long_fronting_sessions'], isFalse);
    });

    test('enum prefs remain ints and auto-promote remains bool', () {
      const settings = SystemSettings();
      final fields = repo.debugSettingsFields(settings);

      expect(fields['fronting_list_view_mode'], isA<int>());
      expect(fields['add_front_default_behavior'], isA<int>());
      expect(fields['quick_front_default_behavior'], isA<int>());
      expect(fields['auto_promote_long_fronting_sessions'], isA<bool>());
    });

    test('has_completed_onboarding stays local-only', () {
      const settings = SystemSettings(hasCompletedOnboarding: true);
      final fields = repo.debugSettingsFields(settings);

      expect(fields, isNot(contains('has_completed_onboarding')));
    });
  });

  group('system avatar round-trip', () {
    test('stores decodable picker-style avatar bytes in settings', () async {
      final source = img.Image(width: 720, height: 720);
      img.fill(source, color: img.ColorRgb8(15, 45, 75));
      img.fillRect(
        source,
        x1: 180,
        y1: 180,
        x2: 539,
        y2: 539,
        color: img.ColorRgb8(230, 200, 90),
      );
      final avatarBytes = encodeAvatarOutputForStorage(
        Uint8List.fromList(img.encodePng(source)),
      );

      await repo.updateSystemAvatarData(avatarBytes);

      final settings = await repo.getSettings();
      expect(settings.systemAvatarData, isNotNull);
      expect(settings.systemAvatarData, avatarBytes);

      final decoded = img.decodeJpg(settings.systemAvatarData!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);
    });

    test(
      'field update creates the singleton row on a fresh database',
      () async {
        await repo.updateSystemName('Prism');

        final settings = await repo.getSettings();
        expect(settings.systemName, 'Prism');
      },
    );
  });
}
