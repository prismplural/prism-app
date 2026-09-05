import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/import_data_step.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  test(
    'path-backed Simply Plural picked files parse through importerProvider',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-sp-import-test',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final bytes = _encryptedSpExportBytes();
      final file = File('${tempDir.path}/sp-export.json');
      await file.writeAsBytes(bytes);

      final container = ProviderContainer(
        overrides: [
          prismFileDialogServiceProvider.overrideWithValue(
            _FakePrismFileDialogService(
              bytes,
              name: 'sp-export.json',
              path: file.path,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(importerProvider.notifier).selectAndParseFile();

      expect(
        container.read(importerProvider).step,
        ImportState.encryptedChatsDetected,
      );
      expect(
        container.read(importerProvider).exportData?.messages,
        hasLength(1),
      );
    },
  );

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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportDataStep)),
    );
    expect(find.text('Select Saved Export'), findsOneWidget);
    await tester.runAsync(() async {
      await container.read(importerProvider.notifier).selectAndParseFile();
    });
    await tester.pump();

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

  testWidgets('Prism export onboarding unlocks encrypted files and previews', (
    tester,
  ) async {
    const password = 'correct horse staple';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prismFileDialogServiceProvider.overrideWithValue(
            _FakePrismFileDialogService(
              _encryptedPrismExportBytes(password),
              name: 'prism-export.prism',
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

    await tester.tap(find.text('Prism Export'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportDataStep)),
    );
    await _runPendingOnboardingImportAction(tester, container);

    expect(find.text('Encrypted Export'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, password);
    await _runPendingOnboardingImportAction(tester, container);

    expect(find.text('Ready to import'), findsOneWidget);
    _expectPreviewRow(label: 'Members', count: '2');
    _expectPreviewRow(label: 'Fronting sessions', count: '3');
    _expectPreviewRow(label: 'Groups', count: '2');
    _expectPreviewRow(label: 'Custom fields', count: '2');
    _expectPreviewRow(label: 'Total records', count: '14');
    expect(find.text('Import and Continue'), findsOneWidget);
  });

  testWidgets('Prism export onboarding rejects unencrypted backups', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prismFileDialogServiceProvider.overrideWithValue(
            _FakePrismFileDialogService(
              utf8.encode(_prismExportJson()),
              name: 'prism-export.json',
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

    await tester.tap(find.text('Prism Export'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportDataStep)),
    );
    await _runPendingOnboardingImportAction(tester, container);

    expect(
      find.text(
        "This backup isn't encrypted. Re-export from the app to get a secure .prism file.",
      ),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);
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

  testWidgets('localizes SP progress labels in Spanish', (tester) async {
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
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en'), Locale('es')],
          home: Scaffold(body: ImportDataStep()),
        ),
      ),
    );

    await tester.tap(find.text('Simply Plural'));
    await tester.pump();

    expect(find.text('Descargando avatares...'), findsOneWidget);
    expect(find.text('12/194'), findsOneWidget);
  });
}

Future<void> _runPendingOnboardingImportAction(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final pendingAction = container.read(onboardingPendingImportActionProvider);
  expect(pendingAction, isNotNull);
  await tester.runAsync(() async {
    await pendingAction!();
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectPreviewRow({required String label, required String count}) {
  final labelFinder = find.text(label);
  expect(labelFinder, findsOneWidget);

  final rowFinder = find.ancestor(of: labelFinder, matching: find.byType(Row));
  expect(rowFinder, findsOneWidget);
  expect(
    find.descendant(of: rowFinder, matching: find.text(count)),
    findsOneWidget,
  );
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

Uint8List _encryptedPrismExportBytes(String password) {
  return ExportCrypto.encrypt(_prismExportJson(), const [], password);
}

String _prismExportJson() {
  const now = '2026-06-02T12:00:00.000Z';
  return jsonEncode({
    'formatVersion': '1.0',
    'version': '1.0',
    'appName': 'Prism Plurality',
    'exportDate': now,
    'totalRecords': 14,
    'headmates': [
      {
        'id': 'member-1',
        'name': 'Alice',
        'pronouns': 'she/her',
        'emoji': 'moon',
        'createdAt': now,
        'displayOrder': 0,
      },
      {
        'id': 'member-2',
        'name': 'Bob',
        'pronouns': 'he/him',
        'emoji': 'sun',
        'createdAt': now,
        'displayOrder': 1,
      },
    ],
    'frontSessions': [
      {
        'id': 'front-1',
        'memberId': 'member-1',
        'startTime': '2026-06-02T09:00:00.000Z',
        'endTime': '2026-06-02T10:00:00.000Z',
        'sessionType': 0,
      },
      {
        'id': 'front-2',
        'memberId': 'member-2',
        'startTime': '2026-06-02T10:00:00.000Z',
        'endTime': '2026-06-02T11:00:00.000Z',
        'sessionType': 0,
      },
      {
        'id': 'front-3',
        'memberId': 'member-1',
        'startTime': '2026-06-02T11:00:00.000Z',
        'endTime': null,
        'sessionType': 0,
      },
    ],
    'sleepSessions': [],
    'conversations': [],
    'messages': [],
    'polls': [],
    'pollOptions': [],
    'systemSettings': [],
    'habits': [],
    'habitCompletions': [],
    'memberGroups': [
      {
        'id': 'group-1',
        'name': 'Frequent fronters',
        'description': 'Long realistic group description for import preview.',
        'emoji': 'star',
        'createdAt': now,
        'displayOrder': 0,
      },
      {
        'id': 'group-2',
        'name': 'Nested subgroup',
        'parentGroupId': 'group-1',
        'createdAt': now,
        'displayOrder': 1,
      },
    ],
    'memberGroupEntries': [
      {'id': 'entry-1', 'groupId': 'group-1', 'memberId': 'member-1'},
      {'id': 'entry-2', 'groupId': 'group-2', 'memberId': 'member-2'},
    ],
    'customFields': [
      {
        'id': 'field-1',
        'name': 'Role',
        'fieldType': 0,
        'createdAt': now,
        'displayOrder': 0,
      },
      {
        'id': 'field-2',
        'name': 'Long description',
        'fieldType': 2,
        'createdAt': now,
        'displayOrder': 1,
      },
    ],
    'customFieldValues': [
      {
        'id': 'value-1',
        'customFieldId': 'field-1',
        'memberId': 'member-1',
        'value': 'Host',
      },
      {
        'id': 'value-2',
        'customFieldId': 'field-2',
        'memberId': 'member-2',
        'value': 'A longer custom field value to keep parsing realistic.',
      },
    ],
    'notes': [
      {
        'id': 'note-1',
        'title': 'Import note',
        'body': 'This note gives the fixture another preview category.',
        'memberId': 'member-1',
        'date': now,
        'createdAt': now,
        'modifiedAt': now,
      },
    ],
  });
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
  const _FakePrismFileDialogService(
    this.bytes, {
    this.name = 'sp-export.json',
    this.path,
  });

  final Uint8List bytes;
  final String name;
  final String? path;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    return PickedFileHandle(
      name: name,
      path: path,
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
