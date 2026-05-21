import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/views/data_export_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

Widget _buildSubject({
  required EncryptedExportFile exportedFile,
  required ExportShareHandler shareExport,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: DataExportSheet(
          initialExportedFile: exportedFile,
          shareExport: shareExport,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('share anchors the popover and keeps the export ready', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'prism_export_sheet_test',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final file = File('${tempDir.path}/backup.prism');
    file.writeAsBytesSync(const [1, 2, 3, 4]);
    final exportedFile = EncryptedExportFile(
      file: file,
      fileName: 'backup.prism',
      sizeBytes: file.lengthSync(),
    );

    Rect? sharePositionOrigin;
    var shareCalls = 0;

    await tester.pumpWidget(
      _buildSubject(
        exportedFile: exportedFile,
        shareExport: (sharedFile, origin) async {
          shareCalls += 1;
          expect(sharedFile.path, file.path);
          sharePositionOrigin = origin;
        },
      ),
    );

    expect(find.text('Export Ready'), findsOneWidget);

    final shareButton = find.widgetWithText(PrismButton, 'Share');
    expect(shareButton, findsOneWidget);
    final shareButtonRect = tester.getRect(shareButton);

    await tester.tap(shareButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(shareCalls, 1);
    expect(sharePositionOrigin, shareButtonRect);
    expect(find.text('Export Ready'), findsOneWidget);
    expect(find.text('Export Complete'), findsNothing);
    expect(file.existsSync(), isTrue);
  });
}
