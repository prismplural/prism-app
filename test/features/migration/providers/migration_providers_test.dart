import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/system_settings.dart'
    as settings_models;
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  group('ImporterNotifier member matching', () {
    test('skips member matching during onboarding', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final memberRepository = FakeMemberRepository()
        ..seed([
          domain.Member(
            id: 'local-a',
            name: 'Alice',
            createdAt: DateTime(2026),
          ),
        ]);
      final container = _containerFor(
        db: db,
        memberRepository: memberRepository,
      );
      addTearDown(container.dispose);

      await container.read(importerProvider.notifier).selectAndParseFile();
      expect(container.read(importerProvider).step, ImportState.previewing);

      container.read(importerProvider.notifier).proceedFromPreview();
      await pumpEventQueue();

      expect(
        container.read(importerProvider).step,
        ImportState.chooseDispositions,
      );
    });

    test(
      'skips member matching when existing members are auto-mapped',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final memberRepository = FakeMemberRepository()
          ..seed([
            domain.Member(
              id: 'local-a',
              name: 'Alice',
              createdAt: DateTime(2026),
            ),
          ]);
        final container = _containerFor(
          db: db,
          memberRepository: memberRepository,
          settings: const settings_models.SystemSettings(
            hasCompletedOnboarding: true,
          ),
        );
        addTearDown(container.dispose);

        await container.read(importerProvider.notifier).selectAndParseFile();
        expect(container.read(importerProvider).step, ImportState.previewing);

        container.read(importerProvider.notifier).proceedFromPreview();
        await pumpEventQueue();

        expect(
          container.read(importerProvider).step,
          ImportState.chooseDispositions,
        );
      },
    );

    test(
      'shows member matching for existing systems with unresolved members',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final memberRepository = FakeMemberRepository()
          ..seed([
            domain.Member(
              id: 'local-a',
              name: 'Different',
              createdAt: DateTime(2026),
            ),
          ]);
        final container = _containerFor(
          db: db,
          memberRepository: memberRepository,
          settings: const settings_models.SystemSettings(
            hasCompletedOnboarding: true,
          ),
        );
        addTearDown(container.dispose);

        await container.read(importerProvider.notifier).selectAndParseFile();
        expect(container.read(importerProvider).step, ImportState.previewing);

        container.read(importerProvider.notifier).proceedFromPreview();
        await pumpEventQueue();

        expect(container.read(importerProvider).step, ImportState.matchMembers);
      },
    );

    test('skips member matching when the flow disables it', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final memberRepository = FakeMemberRepository()
        ..seed([
          domain.Member(
            id: 'local-a',
            name: 'Different',
            createdAt: DateTime(2026),
          ),
        ]);
      final container = _containerFor(
        db: db,
        memberRepository: memberRepository,
        settings: const settings_models.SystemSettings(
          hasCompletedOnboarding: true,
        ),
      );
      addTearDown(container.dispose);

      await container.read(importerProvider.notifier).selectAndParseFile();
      expect(container.read(importerProvider).step, ImportState.previewing);

      container
          .read(importerProvider.notifier)
          .proceedFromPreview(allowMemberMapping: false);
      await pumpEventQueue();

      expect(
        container.read(importerProvider).step,
        ImportState.chooseDispositions,
      );
    });
  });
}

ProviderContainer _containerFor({
  required AppDatabase db,
  required FakeMemberRepository memberRepository,
  settings_models.SystemSettings settings =
      const settings_models.SystemSettings(),
}) {
  final settingsRepository = FakeSystemSettingsRepository()
    ..settings = settings;
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      memberRepositoryProvider.overrideWithValue(memberRepository),
      systemSettingsRepositoryProvider.overrideWithValue(settingsRepository),
      prismFileDialogServiceProvider.overrideWithValue(
        _FakePrismFileDialogService(_spExportBytes()),
      ),
    ],
  );
}

Uint8List _spExportBytes() {
  return utf8.encode(
    jsonEncode({
      'members': [
        {'_id': 'sp-a', 'name': 'Alice'},
      ],
      'frontStatuses': [
        {'_id': 'cf-sleep', 'name': 'Sleep'},
      ],
    }),
  );
}

class _FakePrismFileDialogService implements PrismFileDialogService {
  const _FakePrismFileDialogService(this.bytes);

  final Uint8List bytes;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    return PickedFileHandle(
      name: 'sp-export.json',
      readAsBytes: () async => bytes,
      openRead: () => Stream.value(bytes),
    );
  }

  @override
  Future<PickedFileHandle?> pickImageFile({String? dialogTitle}) async => null;

  @override
  Future<SaveFileOutcome> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    required List<String> allowedExtensions,
    String? dialogTitle,
    String? mimeType,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SaveFileOutcome> saveExistingFile(ExistingFileSaveRequest request) {
    throw UnimplementedError();
  }
}
