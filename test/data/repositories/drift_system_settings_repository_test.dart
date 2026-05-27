import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SleepQuality;
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
  late SystemSettingsDao dao;
  late DriftSystemSettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = SystemSettingsDao(db);
    repo = DriftSystemSettingsRepository(dao, null);
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

    test('palette appearance fields emit sync-safe values', () {
      const settings = SystemSettings(
        paletteSource: PaletteSource.device,
        paletteSeedColorHex: '#ABCDEF',
        paletteMood: PaletteMood.expressive,
        paletteContrast: PaletteContrast.high,
      );
      final fields = repo.debugSettingsFields(settings);

      expect(fields['palette_source'], PaletteSource.device.index);
      expect(fields['palette_seed_color_hex'], '#ABCDEF');
      expect(fields['palette_mood'], PaletteMood.expressive.index);
      expect(fields['palette_contrast'], PaletteContrast.high.index);
      expect(fields['palette_source'], isA<int>());
      expect(fields['palette_mood'], isA<int>());
      expect(fields['palette_contrast'], isA<int>());
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

  group('updateSettings (patch-style emission)', () {
    // Seeds the singleton row by reading once; subsequent reads return the
    // same defaults without recreating it.
    Future<SystemSettings> seed() async {
      return repo.getSettings();
    }

    test('emits only the changed fields', () async {
      final base = await seed();
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSettings(base.copyWith(systemName: 'Renamed'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'system_settings');
      expect(captured.single.entityId, 'singleton');
      // system_settings has no `modified_at` column, so a one-field domain
      // change emits exactly one key.
      expect(captured.single.fields.keys.toSet(), {'system_name'});
      expect(captured.single.fields['system_name'], 'Renamed');
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test('emits nothing when domain matches the stored row', () async {
      final base = await seed();
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSettings(base);

      expect(captured, isEmpty);
    });

    test(
      'persists onboarding completion while syncing only shared fields',
      () async {
        final base = await seed();
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateSettings(
          base.copyWith(
            systemName: 'Prism Collective',
            hasCompletedOnboarding: true,
          ),
        );

        final settings = await repo.getSettings();
        expect(settings.systemName, 'Prism Collective');
        expect(settings.hasCompletedOnboarding, isTrue);
        expect(captured, hasLength(1));
        expect(captured.single.fields.keys.toSet(), {'system_name'});
      },
    );

    test('persists database-only fields omitted from sync map', () async {
      final base = await seed();
      final backfilledAt = DateTime.utc(2026, 5, 20, 12);
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSettings(
        base.copyWith(
          displayFontInAppBar: false,
          defaultSleepQuality: SleepQuality.good,
          boardsEnabled: true,
          spBoardsBackfilledAt: backfilledAt,
          membersShowPronouns: false,
          membersShowFrontButtons: true,
          membersFrontButtonBehavior: FrontStartBehavior.replace,
        ),
      );

      final settings = await repo.getSettings();
      expect(settings.displayFontInAppBar, isFalse);
      expect(settings.defaultSleepQuality, SleepQuality.good);
      expect(settings.boardsEnabled, isTrue);
      expect(settings.spBoardsBackfilledAt?.toUtc(), backfilledAt);
      expect(settings.membersShowPronouns, isFalse);
      expect(settings.membersShowFrontButtons, isTrue);
      expect(settings.membersFrontButtonBehavior, FrontStartBehavior.replace);
      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      // Seed a non-default column value first so the test can prove the
      // partial companion leaves it alone.
      await repo.updateAccentColorHex('#ABCDEF');
      await repo.updatePollsEnabled(false);
      final base = await repo.getSettings();

      await repo.updateSettings(base.copyWith(systemName: 'Touched'));

      final row = await dao.getSettings();
      expect(row.systemName, 'Touched');
      expect(row.accentColorHex, '#ABCDEF');
      expect(row.pollsEnabled, isFalse);
    });

    test('silently no-ops when the row does not exist', () async {
      // Drop the singleton row entirely to simulate an empty table; the
      // patch path must bail without creating one.
      await db.customStatement(
        "DELETE FROM system_settings WHERE id = 'singleton'",
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSettings(const SystemSettings(systemName: 'NoRow'));

      expect(captured, isEmpty);
      final stillMissing = await dao.getSettingsRow();
      expect(stillMissing, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      final base = await seed();
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Touch several fields so the diff has plenty of opportunity to leak
      // an `is_deleted` entry.
      await repo.updateSettings(
        base.copyWith(
          systemName: 'Multi',
          chatEnabled: !base.chatEnabled,
          themeMode: base.themeMode == AppThemeMode.system
              ? AppThemeMode.light
              : AppThemeMode.system,
        ),
      );

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });
}
