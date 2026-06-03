import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';

const _presetName = String.fromEnvironment(
  'PRISM_STRESS_PRESET',
  defaultValue: 'reportedLarge',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed stress fixture into simulator app database', (_) async {
    final preset = switch (_presetName) {
      'reportedLarge' => StressPreset.reportedLarge,
      'heavy5k' => StressPreset.heavyFiveThousand,
      'huge' => StressPreset.huge,
      'massive' => StressPreset.massive,
      _ => throw ArgumentError('Unknown PRISM_STRESS_PRESET: $_presetName'),
    };

    final probe = await probeAppDatabaseStartup();
    expect(probe.state, DbStartupState.ready);
    expect(probe.keyInMemory, isNotNull);

    final container = ProviderContainer(
      overrides: [
        verifiedStartupKeyProvider.overrideWithValue(probe.keyInMemory),
      ],
    );
    addTearDown(container.dispose);

    final db = container.read(databaseProvider);
    final generator = StressDataGenerator(db);
    await generator.clearStressData();

    final started = DateTime.now();
    await for (final progress in generator.generate(preset)) {
      final percent = (progress.fraction * 100).toStringAsFixed(1);
      // ignore: avoid_print
      print('[seed] ${progress.phase}: $percent%');
    }
    final elapsed = DateTime.now().difference(started);

    await db.systemSettingsDao.updateSystemName('Prism $preset.label Fixture');
    await db.systemSettingsDao.updateHasCompletedOnboarding(true);
    await db.systemSettingsDao.updateBoardsEnabled(true);
    await db.systemSettingsDao.updateSleepTrackingEnabled(true);

    final memberCount = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM members WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    final groupCount = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM member_groups WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    final customFieldValueCount = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM custom_field_values '
          "WHERE id LIKE 'stress-%'",
        )
        .getSingle();

    expect(memberCount.read<int>('c'), preset.members);
    expect(groupCount.read<int>('c'), preset.groups);
    expect(customFieldValueCount.read<int>('c'), greaterThan(preset.members));

    // ignore: avoid_print
    print(
      '[seed] Seeded ${preset.label}: ${preset.members} members, '
      '${preset.groups} groups in ${elapsed.inSeconds}s',
    );
  });
}
