import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import '../../../helpers/bio_image_test_utils.dart';

void main() {
  Widget buildHost({TestBioImageInfra? imageInfra}) {
    return ProviderScope(
      overrides: [
        if (imageInfra != null) ...[
          databaseProvider.overrideWithValue(imageInfra.database),
          prismSyncHandleProvider.overrideWithBuild((ref, notifier) => null),
          mediaServiceProvider.overrideWithValue(imageInfra.mediaService),
        ],
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showFullScreenMarkdownEditor(
                    context: context,
                    title: 'Bio',
                    initialText: '',
                    hintText: 'Write something',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dirty markdown editor shows discard dialog on drag-to-dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost());

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'unsaved progress');
    await tester.pumpAndSettle();

    await tester.drag(find.byType(TextField), const Offset(0, 700));
    await tester.pumpAndSettle();

    expect(find.text('Bio'), findsOneWidget);
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Bio'), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('unsaved progress'), findsOneWidget);
  });

  testWidgets(
    'clean markdown editor dismisses on drag-to-close without a dialog',
    (tester) async {
      await tester.pumpWidget(buildHost());

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Bio'), findsOneWidget);

      await tester.drag(find.byType(TextField), const Offset(0, 700));
      await tester.pumpAndSettle();

      expect(find.text('Bio'), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
    },
  );

  testWidgets(
    'image-only staged edit shows discard dialog on drag-to-dismiss',
    (tester) async {
      final imageInfra = TestBioImageInfra.create();
      addTearDown(imageInfra.close);

      await tester.pumpWidget(buildHost(imageInfra: imageInfra));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final imageButton = tester.widget<MarkdownImageButton>(
        find.byType(MarkdownImageButton),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MarkdownImageButton)),
      );
      final processor = container.read(
        bioImageProcessorProvider(imageButton.sessionId),
      );
      processor.staged.add(testStagedBioImage());

      await tester.enterText(find.byType(TextField), 'temporary text');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.drag(find.byType(TextField), const Offset(0, 700));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(processor.staged, isNotEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Bio'), findsOneWidget);
      expect(processor.staged, isNotEmpty);

      await tester.drag(find.byType(TextField), const Offset(0, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(processor.staged, isEmpty);
      expect(find.text('Bio'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
