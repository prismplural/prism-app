import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/import_data_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  testWidgets('shows encrypted chat warning during Simply Plural onboarding', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prismFileDialogServiceProvider.overrideWithValue(
            _FakePrismFileDialogService(_encryptedSpExportBytes()),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: ImportDataStep()),
        ),
      ),
    );

    await tester.tap(find.text('Simply Plural'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select Export File'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportDataStep)),
    );
    expect(
      container.read(importerProvider).step,
      ImportState.encryptedChatsDetected,
    );
    expect(find.text('Encrypted Simply Plural chats'), findsOneWidget);
    expect(find.text('Skip chat'), findsOneWidget);
    expect(find.text("I'll get a fresh import"), findsOneWidget);

    final pendingContinue = container.read(
      onboardingPendingImportActionProvider,
    );
    expect(pendingContinue, isNotNull);
    await pendingContinue!();
    await tester.pumpAndSettle();

    expect(container.read(importerProvider).step, ImportState.previewing);
    expect(find.text('Encrypted Simply Plural chats'), findsNothing);
  });

  testWidgets('shows progress instead of a blank body for SP decision states', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importerProvider.overrideWith(
            () => _FakeImporterNotifier(
              MigrationState(
                step: ImportState.matchMembers,
                exportData: _plainSpExportData(),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: ImportDataStep()),
        ),
      ),
    );

    await tester.tap(find.text('Simply Plural'));
    await tester.pump();

    expect(find.text('Preparing member choices...'), findsOneWidget);
  });

  testWidgets('shows SP avatar progress counts during onboarding import', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importerProvider.overrideWith(
            () => _FakeImporterNotifier(
              MigrationState(
                step: ImportState.downloadingAvatars,
                exportData: _plainSpExportData(),
                current: 12,
                total: 194,
                progressLabel: 'Downloading avatars...',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: ImportDataStep()),
        ),
      ),
    );

    await tester.tap(find.text('Simply Plural'));
    await tester.pump();

    expect(find.text('Downloading avatars...'), findsOneWidget);
    expect(find.text('12/194'), findsOneWidget);
  });
}

Uint8List _encryptedSpExportBytes() {
  return utf8.encode(
    jsonEncode({
      'members': [
        {'_id': 'mem1', 'name': 'Alice'},
      ],
      'frontHistory': [],
      'channels': [
        {'_id': 'ch1', 'name': 'General'},
      ],
      'chatMessages': [
        {
          '_id': 'msg1',
          'message': 'rR9y0tk=',
          'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
          'channel': 'ch1',
          'writer': 'mem1',
          'writtenAt': 1774242087364,
        },
      ],
    }),
  );
}

SpExportData _plainSpExportData() {
  return const SpExportData(
    members: [SpMember(id: 'mem1', name: 'Alice')],
    customFronts: [],
    frontHistory: [],
    groups: [],
    channels: [],
    messages: [],
    polls: [],
  );
}

class _FakeImporterNotifier extends ImporterNotifier {
  _FakeImporterNotifier(this.initialState);

  final MigrationState initialState;

  @override
  MigrationState build() => initialState;

  @override
  void continueFromMemberMapping() {}
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SaveFileOutcome> saveExistingFile(ExistingFileSaveRequest request) {
    throw UnimplementedError();
  }
}
