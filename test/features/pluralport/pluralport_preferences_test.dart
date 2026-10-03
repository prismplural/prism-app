import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

import 'harness.dart';

void main() {
  for (final restore in [false, true]) {
    test(
      'preference restore $restore preserves local security and opaque keys',
      () async {
        final db = makeDb();
        addTearDown(db.close);
        final settings = DriftSystemSettingsRepository(
          db.systemSettingsDao,
          null,
        );
        await settings.updateSettings(
          (await settings.getSettings()).copyWith(
            pinLockEnabled: true,
            biometricLockEnabled: true,
            hasCompletedOnboarding: true,
            sharingId: 'existing-sharing-id',
            accentColorHex: '#112233',
          ),
        );
        final service = PluralPortService(
          db: db,
          exporter: makeExport(db),
          importer: makeImport(db),
          supportDirectory: () async => Directory.systemTemp,
        );
        final incoming = PluralPortBundle({
          'pluralport_version': '0.1',
          'producer': {'app': 'Prism', 'app_id': 'prism'},
          'extensions': {
            'prism': {
              'native_modules': {
                'systemSettings': [
                  {
                    'accentColorHex': '#abcdef',
                    'sharingId': 'foreign-sharing-id',
                    'pinLockEnabled': false,
                    'biometricLockEnabled': false,
                    'hasCompletedOnboarding': false,
                    'pkGroupSyncV2Enabled': true,
                    'gifConsentState': 1,
                    'futureSetting': {'opaque': true},
                  },
                ],
                'appPreferences': [
                  {
                    'key': 'privacy.hide_total_member_count',
                    'valueType': 'bool',
                    'valueJson': 'true',
                  },
                  {
                    'key': 'unknown.future_preference',
                    'valueType': 'string',
                    'valueJson': '"opaque"',
                  },
                ],
              },
            },
          },
        });
        await service.importPlan(
          PluralPortMapper.plan(incoming),
          restorePrismPreferences: restore,
        );
        final current = await settings.getSettings();
        expect(current.pinLockEnabled, isTrue);
        expect(current.biometricLockEnabled, isTrue);
        expect(current.hasCompletedOnboarding, isTrue);
        expect(current.sharingId, 'existing-sharing-id');
        expect(current.pkGroupSyncV2Enabled, isFalse);
        expect(current.accentColorHex, restore ? '#abcdef' : '#112233');
        final native = (await makeExport(db).buildExport()).toJson();
        expect(
          PluralPortMapper.rows(native, 'appPreferences').map((r) => r['key']),
          restore ? ['privacy.hide_total_member_count'] : isEmpty,
        );
        final outgoing = await service.exportBundle();
        final modules =
            ((outgoing.envelope['extensions'] as Map)['prism']
                    as Map)['native_modules']
                as Map;
        expect(
          (modules['appPreferences'] as List).last['key'],
          'unknown.future_preference',
        );
        expect((modules['systemSettings'] as List).first['futureSetting'], {
          'opaque': true,
        });
        if (restore) {
          await settings.updateSettings(
            current.copyWith(accentColorHex: '#fedcba'),
          );
          final edited = await service.exportBundle();
          final editedModules =
              ((edited.envelope['extensions'] as Map)['prism']
                      as Map)['native_modules']
                  as Map;
          expect(
            (editedModules['systemSettings'] as List).single['accentColorHex'],
            '#fedcba',
          );
        }
      },
    );
  }
}
